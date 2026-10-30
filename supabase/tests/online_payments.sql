-- ============================================================
-- Online payments (0105): pay links, what a shop can buy and for how
-- much, turning a paid order on (once), wrong amounts, add-ons for the
-- days left, Lifetime, and who can call what.
--
-- HOW TO RUN — on a STAGING copy, after 0105:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the last line shows "online payments tests passed".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('10510510-0000-0000-0000-0000000000ad', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'pay-owner@test.invalid'),
  ('10510510-0000-0000-0000-0000000000ac', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'pay-accounts@test.invalid'),
  ('10510510-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'pay-shop-a@test.invalid'),
  ('10510510-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'pay-shop-b@test.invalid');
update public.profiles set role = 'admin'
  where id in ('10510510-0000-0000-0000-0000000000ad', '10510510-0000-0000-0000-0000000000ac');
insert into public.admin_team (user_id, team_role, areas) values
  ('10510510-0000-0000-0000-0000000000ad', 'owner', '{}'),
  ('10510510-0000-0000-0000-0000000000ac', 'accounts', '{payments}');
update public.platform_settings set online_payments = false where id = 1;

-- A signed-in person, or the server (the razorpay functions' service role).
create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
create or replace function pg_temp.server() returns void language sql as $$
  select set_config('role', 'service_role', true),
         set_config('request.jwt.claims', '{"role":"service_role"}', true);
$$;

set local role authenticated;

do $$
declare
  owner constant uuid := '10510510-0000-0000-0000-0000000000ad';
  accounts constant uuid := '10510510-0000-0000-0000-0000000000ac';
  shop_a constant uuid := '10510510-0000-0000-0000-00000000000a';
  shop_b constant uuid := '10510510-0000-0000-0000-00000000000b';
  biz_a uuid; biz_b uuid; tok text; tok_b text; v jsonb; q jsonb; std public.plans; life public.plans;
  disc numeric; web numeric; n int; exp_a date; sub public.subscriptions;
begin
  perform pg_temp.act(shop_a);
  biz_a := public.create_business(jsonb_build_object('name', 'Pay Shop A', 'phone', '9000105001'));
  perform pg_temp.act(shop_b);
  biz_b := public.create_business(jsonb_build_object('name', 'Pay Shop B', 'phone', '9000105002'));
  perform pg_temp.act(owner);
  select * into std from public.plans where name = 'Standard';
  select * into life from public.plans where name = 'Lifetime';
  if std.id is null or life.id is null then raise exception 'FAIL 0: Standard and Lifetime plans needed'; end if;
  disc := (select website_discount_pct from public.platform_settings where id = 1);
  web := round(std.list_price * (1 - disc / 100));

  -- 1. The switch, and the owner's pay link.
  perform pg_temp.act(shop_a);
  begin
    perform public.create_pay_link();
    raise exception 'FAIL 1a: pay link while switched off';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform pg_temp.act(accounts);
  begin
    perform public.admin_set_online_payments(true);
    raise exception 'FAIL 1b: accounts switched it on';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform pg_temp.act(owner);
  perform public.admin_set_online_payments(true);
  perform pg_temp.act(shop_a);
  if not public.online_payments_on() then raise exception 'FAIL 1c: not on'; end if;
  tok := public.create_pay_link();
  if tok !~ '^[0-9a-f]{32}$' then raise exception 'FAIL 1d: token %', tok; end if;
  perform pg_temp.act(shop_b);
  tok_b := public.create_pay_link();
  raise notice 'PASS 1 (switch and pay link)';

  -- 2. A shop can't use the server's functions or see orders and links.
  perform pg_temp.act(shop_a);
  begin
    perform public.online_quote(biz_a, jsonb_build_object('kind', 'plan', 'plan_id', std.id));
    raise exception 'FAIL 2a: a shop priced its own order';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    perform public.online_order_paid('order_x', '{}'::jsonb);
    raise exception 'FAIL 2b: a shop turned an order on';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  if (select count(*) from public.pay_links) <> 0 then raise exception 'FAIL 2c: a shop reads pay links'; end if;
  raise notice 'PASS 2 (server only)';

  -- 3. The context and the price, worked out on the server.
  perform pg_temp.server();
  v := public.online_context(tok);
  if v ->> 'shop' <> 'Pay Shop A' or jsonb_array_length(v -> 'plans') < 2 then raise exception 'FAIL 3a: context %', v; end if;
  if public.online_context('0123456789abcdef0123456789abcdef') is not null then raise exception 'FAIL 3b: any token works'; end if;
  q := public.online_quote(biz_a, jsonb_build_object('kind', 'plan', 'plan_id', std.id, 'extra_staff', 2));
  if (q ->> 'amount')::numeric <> web + 2 * std.extra_staff_price then raise exception 'FAIL 3c: price %', q; end if;
  insert into public.promo_codes (code, kind, value) values ('PAYTEST100', 'amount', 100);
  q := public.online_quote(biz_a, jsonb_build_object('kind', 'plan', 'plan_id', std.id, 'code', 'paytest100'));
  if (q ->> 'amount')::numeric <> web - 100 or not (q ->> 'code_ok')::boolean then raise exception 'FAIL 3d: with code %', q; end if;
  v := public.online_quote(biz_a, jsonb_build_object('kind', 'plan', 'plan_id', std.id, 'code', 'NOSUCH'));
  if (v ->> 'amount')::numeric <> web or (v ->> 'code_ok')::boolean then raise exception 'FAIL 3e: bad code %', v; end if;
  raise notice 'PASS 3 (price)';

  -- 4. Paid: the plan turns on once, with the code used.
  insert into public.online_orders (business_id, rzp_order_id, kind, item, quote, amount)
  values (biz_a, 'order_TEST105A', 'plan', jsonb_build_object('plan_id', std.id), q, (q ->> 'amount')::numeric);
  v := public.online_order_paid('order_TEST105A', jsonb_build_object('id', 'pay_TEST105A',
         'amount', round((q ->> 'amount')::numeric * 100), 'method', 'upi'));
  if not (v ->> 'ok')::boolean then raise exception 'FAIL 4a: %', v; end if;
  select * into sub from public.subscriptions where business_id = biz_a order by created_at desc limit 1;
  if sub.plan_id <> std.id or sub.status <> 'active' or sub.expiry_date <> (q ->> 'until')::date then
    raise exception 'FAIL 4b: subscription % (want until %)', to_jsonb(sub), q ->> 'until';
  end if;
  if not exists (select 1 from public.subscription_payments where business_id = biz_a and reference = 'pay_TEST105A'
                   and amount = (q ->> 'amount')::numeric and payment_mode = 'upi') then
    raise exception 'FAIL 4c: no payment';
  end if;
  if (select used_count from public.promo_codes where code = 'PAYTEST100') <> 1 then raise exception 'FAIL 4d: code not used'; end if;
  v := public.online_order_paid('order_TEST105A', jsonb_build_object('id', 'pay_TEST105A',
         'amount', round((q ->> 'amount')::numeric * 100), 'method', 'upi'));
  select count(*) into n from public.subscription_payments where business_id = biz_a;
  if not coalesce((v ->> 'already')::boolean, false) or n <> 1 then raise exception 'FAIL 4e: turned on twice (% payments)', n; end if;
  raise notice 'PASS 4 (paid once)';

  -- 5. The wrong amount turns nothing on.
  q := public.online_quote(biz_a, jsonb_build_object('kind', 'plan', 'plan_id', std.id));
  insert into public.online_orders (business_id, rzp_order_id, kind, item, quote, amount)
  values (biz_a, 'order_TEST105B', 'plan', jsonb_build_object('plan_id', std.id), q, (q ->> 'amount')::numeric);
  v := public.online_order_paid('order_TEST105B', jsonb_build_object('id', 'pay_TEST105B', 'amount', 100, 'method', 'card'));
  if (v ->> 'ok')::boolean or (select status from public.online_orders where rzp_order_id = 'order_TEST105B') <> 'failed'
     or (select count(*) from public.subscription_payments where business_id = biz_a) <> 1 then
    raise exception 'FAIL 5: wrong amount %', v;
  end if;
  raise notice 'PASS 5 (wrong amount)';

  -- 6. A staff login mid-year: charged for the days left, runs with the plan.
  exp_a := (select expiry_date from public.subscriptions where business_id = biz_a order by created_at desc limit 1);
  q := public.online_quote(biz_a, jsonb_build_object('kind', 'addon', 'addon', 'staff', 'quantity', 1));
  if (q ->> 'amount')::numeric <> round(std.extra_staff_price * least(exp_a - public.ist_date(now()), 365) / 365.0)
     or (q ->> 'until')::date <> exp_a then
    raise exception 'FAIL 6a: add-on price %', q;
  end if;
  insert into public.online_orders (business_id, rzp_order_id, kind, item, quote, amount)
  values (biz_a, 'order_TEST105C', 'addon', jsonb_build_object('addon', 'staff'), q, (q ->> 'amount')::numeric);
  v := public.online_order_paid('order_TEST105C', jsonb_build_object('id', 'pay_TEST105C',
         'amount', round((q ->> 'amount')::numeric * 100), 'method', 'netbanking'));
  if not exists (select 1 from public.shop_addons where business_id = biz_a and kind = 'staff' and valid_until = exp_a)
     or not exists (select 1 from public.subscription_payments where reference = 'pay_TEST105C' and payment_mode = 'other') then
    raise exception 'FAIL 6b: add-on not added %', v;
  end if;
  raise notice 'PASS 6 (add-on for the days left)';

  -- 7. Shop B buys Lifetime: no renewal after that; AI runs a year at full price.
  q := public.online_quote(biz_b, jsonb_build_object('kind', 'plan', 'plan_id', life.id));
  insert into public.online_orders (business_id, rzp_order_id, kind, item, quote, amount)
  values (biz_b, 'order_TEST105D', 'plan', jsonb_build_object('plan_id', life.id), q, (q ->> 'amount')::numeric);
  perform public.online_order_paid('order_TEST105D', jsonb_build_object('id', 'pay_TEST105D',
            'amount', round((q ->> 'amount')::numeric * 100), 'method', 'card'));
  if (select plan_id from public.subscriptions where business_id = biz_b order by created_at desc limit 1) <> life.id then
    raise exception 'FAIL 7a: not on Lifetime';
  end if;
  begin
    perform public.online_quote(biz_b, jsonb_build_object('kind', 'plan', 'plan_id', std.id));
    raise exception 'FAIL 7b: a Lifetime shop was offered a renewal';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  if life.ai_addon_price > 0 then
    q := public.online_quote(biz_b, jsonb_build_object('kind', 'addon', 'addon', 'ai'));
    if (q ->> 'amount')::numeric <> life.ai_addon_price
       or (q ->> 'until')::date <> (public.ist_date(now()) + interval '1 year')::date then
      raise exception 'FAIL 7c: AI for Lifetime %', q;
    end if;
  end if;
  v := public.online_context(tok_b);
  if (v -> 'current' ->> 'billing') <> 'lifetime' or not (v -> 'current' ->> 'active')::boolean then
    raise exception 'FAIL 7d: context %', v;
  end if;
  raise notice 'PASS 7 (lifetime)';

  -- 8. The team sees the orders on the Payments page.
  perform pg_temp.act(accounts);
  if (select count(*) from public.online_orders where business_id in (biz_a, biz_b)) <> 4 then
    raise exception 'FAIL 8: accounts can''t see the orders';
  end if;
  raise notice 'PASS 8 (Payments page)';
end $$;

reset role;
select 'online payments tests passed' as result;
rollback;
