-- ============================================================
-- Plan pricing, lifetime and paid add-ons (migration 0096).
--
-- HOW TO RUN — on a STAGING copy, after 0096:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the last line shows "pricing_addons tests passed". The
-- first failed check stops the run with "FAIL …".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('96969696-0000-0000-0000-0000000000ad', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'price-admin@test.invalid'),
  ('96969696-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'price-owner@test.invalid');
insert into public.businesses (id, name, state_code, phone) values
  ('96969696-1111-0000-0000-00000000000a', 'Price Test Shop', '21', '9000096096');
update public.profiles set role = 'admin' where id = '96969696-0000-0000-0000-0000000000ad';
update public.profiles set business_id = '96969696-1111-0000-0000-00000000000a', role = 'owner'
  where id = '96969696-0000-0000-0000-00000000000a';
insert into public.feature_flags (business_id) values ('96969696-1111-0000-0000-00000000000a')
  on conflict (business_id) do nothing;

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

-- The shop's AI and login limit, read with the database's own rights:
-- the real functions are closed to users (only the server calls them).
create or replace function pg_temp.has_ai(p uuid) returns boolean
  language sql security definer as $$ select public.business_has_ai(p) $$;
create or replace function pg_temp.user_limit(p uuid) returns integer
  language sql security definer as $$ select public.business_user_limit(p) $$;

set local role authenticated;

do $$
declare
  admin constant uuid := '96969696-0000-0000-0000-0000000000ad';
  owner constant uuid := '96969696-0000-0000-0000-00000000000a';
  shop  constant uuid := '96969696-1111-0000-0000-00000000000a';
  std uuid; stdai uuid; life uuid; r jsonb; v jsonb; n integer;
begin
  -- Plans are readable by the admin only (0055).
  perform pg_temp.act(admin);
  select id into std from public.plans where name = 'Standard';
  select id into stdai from public.plans where name = 'Standard + AI';
  select id into life from public.plans where name = 'Lifetime';
  if std is null or stdai is null or life is null then raise exception 'FAIL 1a: the three plans are missing'; end if;
  if (select list_price from public.plans where id = stdai) <> 5999
     or (select lowest_price from public.plans where id = life) <> 15000
     or (select user_limit from public.plans where id = std) <> 3
     or (select billing from public.plans where id = life) <> 'lifetime' then
    raise exception 'FAIL 1b: plan prices or limits';
  end if;
  raise notice 'PASS 1 (three plans seeded)';

  -- 2. The website gets list and website prices, never the lowest price.
  v := public.public_site_info();
  if v::text like '%lowest%' then raise exception 'FAIL 2a: lowest price on the website'; end if;
  if not exists (select 1 from jsonb_array_elements(v -> 'plans') x
                 where x ->> 'name' = 'Standard' and (x ->> 'list_price')::numeric = 3499
                   and (x ->> 'website_price')::numeric
                       = round(3499 * (1 - (v ->> 'website_discount_pct')::numeric / 100))) then
    raise exception 'FAIL 2b: Standard on the website: %', v -> 'plans';
  end if;
  raise notice 'PASS 2 (website prices)';

  -- 3. Standard: 3 logins, no AI. A sale with 1 extra staff makes 4.
  perform pg_temp.act(admin);
  r := public.admin_record_sale(shop, jsonb_build_object('plan_id', std, 'extra_staff', 1,
         'amount', 3500, 'mode', 'upi', 'reference', 'UTR1'));
  if (r ->> 'list_total')::numeric <> 4499 then raise exception 'FAIL 3a: list total %', r; end if;
  if pg_temp.user_limit(shop) <> 4 then
    raise exception 'FAIL 3b: user limit %', pg_temp.user_limit(shop);
  end if;
  if pg_temp.has_ai(shop) or (select ai_assistant from public.feature_flags where business_id = shop) then
    raise exception 'FAIL 3c: AI on a Standard shop';
  end if;
  if (r ->> 'below_lowest')::boolean then raise exception 'FAIL 3d: 3500 flagged below lowest'; end if;
  if (select breakdown ->> 'plan' from public.subscription_payments where receipt_no = r ->> 'receipt_no') <> 'Standard' then
    raise exception 'FAIL 3e: receipt breakdown';
  end if;
  raise notice 'PASS 3 (Standard + 1 staff)';

  -- 4. Lifetime with the AI add-on: expiry 2099, AI on; the add-on ends → AI off.
  r := public.admin_record_sale(shop, jsonb_build_object('plan_id', life, 'ai_addon', true,
         'amount', 14000, 'mode', 'other'));
  if (r ->> 'expiry_date')::date <> date '2099-12-31' then raise exception 'FAIL 4a: lifetime expiry %', r; end if;
  if not (r ->> 'below_lowest')::boolean then raise exception 'FAIL 4b: 14000 not flagged below lowest'; end if;
  if not pg_temp.has_ai(shop) or not (select ai_assistant from public.feature_flags where business_id = shop) then
    raise exception 'FAIL 4c: AI add-on not on';
  end if;
  update public.shop_addons set valid_until = public.ist_date(now()) - 1 where business_id = shop and kind = 'ai';
  if pg_temp.has_ai(shop) then raise exception 'FAIL 4d: expired AI add-on still counts'; end if;
  raise notice 'PASS 4 (lifetime and the AI add-on)';
end $$;

-- The nightly job turns the AI switch off once the add-on has run out.
reset role;
do $$
declare
  n integer;
begin
  n := public.expire_addons();
  if (select ai_assistant from public.feature_flags
      where business_id = '96969696-1111-0000-0000-00000000000a') then
    raise exception 'FAIL 4e: AI switch not turned off (switched off %)', n;
  end if;
  raise notice 'PASS 4e (nightly add-on expiry)';
end $$;
set local role authenticated;

do $$
declare
  admin constant uuid := '96969696-0000-0000-0000-0000000000ad';
  owner constant uuid := '96969696-0000-0000-0000-00000000000a';
  shop  constant uuid := '96969696-1111-0000-0000-00000000000a';
  stdai uuid; v jsonb;
begin
  perform pg_temp.act(admin);
  select id into stdai from public.plans where name = 'Standard + AI';

  -- 5. A staff login bought on its own; the shop can't buy or see prices.
  perform public.admin_add_addon(shop, jsonb_build_object('kind', 'staff', 'quantity', 2, 'amount', 2000));
  if pg_temp.user_limit(shop) <> 3 + 1 + 2 then
    raise exception 'FAIL 5a: user limit %', pg_temp.user_limit(shop);
  end if;
  perform pg_temp.act(owner);
  begin
    perform public.admin_add_addon(shop, jsonb_build_object('kind', 'staff', 'quantity', 5));
    raise exception 'FAIL 5b: a shop owner added an add-on';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  if (select count(*) from public.shop_addons) <> 0 then
    raise exception 'FAIL 5c: a shop reads the add-on table directly';
  end if;
  v := public.my_addons();
  if v::text like '%price%' or jsonb_array_length(v) < 1 then raise exception 'FAIL 5d: my_addons %', v; end if;
  raise notice 'PASS 5 (staff add-on; shops see add-ons without prices)';

  -- 6. Standard + AI includes AI; an AI add-on on it is refused.
  perform pg_temp.act(admin);
  perform public.admin_record_sale(shop, jsonb_build_object('plan_id', stdai, 'amount', 4500, 'mode', 'upi'));
  if not pg_temp.has_ai(shop) then raise exception 'FAIL 6a: Standard + AI without AI'; end if;
  begin
    perform public.admin_add_addon(shop, jsonb_build_object('kind', 'ai', 'amount', 1499));
    raise exception 'FAIL 6b: AI add-on on a plan with AI';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 6 (Standard + AI)';

  -- 7. Pricing is saved by the admin only; the lowest can't top the list.
  begin
    perform public.admin_save_plan_pricing((select id from public.plans where name = 'Standard'), jsonb_build_object('billing', 'yearly',
      'list_price', 3000, 'lowest_price', 3200));
    raise exception 'FAIL 7a: lowest above list accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform public.admin_set_website_discount(25);
  if (public.public_site_info() ->> 'website_discount_pct')::numeric <> 25 then
    raise exception 'FAIL 7b: discount not saved';
  end if;
  raise notice 'PASS 7 (pricing rules)';
end $$;

reset role;
select 'pricing_addons tests passed' as result;
rollback;
