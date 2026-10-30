-- ============================================================
-- The shop's account (0106): pay links with online payments off,
-- upgrades mid-year (the difference for the days left, same end date),
-- to Lifetime (minus the unused days), and the account summary.
--
-- HOW TO RUN — on a STAGING copy, after 0105 and 0106:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the last line shows "shop account tests passed".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('10610610-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'acct-shop-a@test.invalid'),
  ('10610610-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'acct-shop-b@test.invalid');
update public.platform_settings set online_payments = false where id = 1;

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
create or replace function pg_temp.server() returns void language sql as $$
  select set_config('role', 'service_role', true),
         set_config('request.jwt.claims', '{"role":"service_role"}', true);
$$;
-- A paid order for an item, as the razorpay function would record it.
create or replace function pg_temp.pay(p_business uuid, p_order text, p_item jsonb) returns jsonb language plpgsql as $$
declare q jsonb;
begin
  q := public.online_quote(p_business, p_item);
  insert into public.online_orders (business_id, rzp_order_id, kind, item, quote, amount)
  values (p_business, p_order, q ->> 'kind', p_item, q, (q ->> 'amount')::numeric);
  return public.online_order_paid(p_order, jsonb_build_object('id', 'pay_' || p_order,
           'amount', round((q ->> 'amount')::numeric * 100), 'method', 'upi')) || jsonb_build_object('quote', q);
end $$;

set local role authenticated;

do $$
declare
  shop_a constant uuid := '10610610-0000-0000-0000-00000000000a';
  shop_b constant uuid := '10610610-0000-0000-0000-00000000000b';
  biz_a uuid; biz_b uuid; tok text; tok_b text; v jsonb; q jsonb; std public.plans; stdai public.plans; life public.plans;
  disc numeric; d int; exp_a date; sub public.subscriptions; today date := public.ist_date(now());
begin
  perform pg_temp.act(shop_a);
  biz_a := public.create_business(jsonb_build_object('name', 'Acct Shop A', 'phone', '9000106001'));
  perform pg_temp.act(shop_b);
  biz_b := public.create_business(jsonb_build_object('name', 'Acct Shop B', 'phone', '9000106002'));
  perform pg_temp.server();
  select * into std from public.plans where name = 'Standard';
  select * into stdai from public.plans where name = 'Standard + AI';
  select * into life from public.plans where name = 'Lifetime';
  if std.id is null or stdai.id is null or life.id is null then raise exception 'FAIL 0: Standard, Standard + AI and Lifetime needed'; end if;
  disc := (select website_discount_pct from public.platform_settings where id = 1);

  -- 1. A pay link (for the account page) with online payments switched off.
  perform pg_temp.act(shop_a);
  tok := public.create_pay_link();
  perform pg_temp.act(shop_b);
  tok_b := public.create_pay_link();
  if tok !~ '^[0-9a-f]{32}$' then raise exception 'FAIL 1: token %', tok; end if;
  raise notice 'PASS 1 (pay link with payments off)';

  -- 2. A trial can't upgrade; the account shows the trial.
  perform pg_temp.server();
  begin
    perform public.online_quote(biz_a, jsonb_build_object('kind', 'upgrade', 'plan_id', stdai.id));
    raise exception 'FAIL 2a: a trial was offered an upgrade';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  v := public.online_account(tok);
  if not (v -> 'plan' ->> 'is_trial')::boolean or jsonb_array_length(v -> 'upgrades') <> 0 then
    raise exception 'FAIL 2b: trial account %', v;
  end if;
  raise notice 'PASS 2 (trial)';

  -- 3. On Standard: Standard + AI costs the difference for the days left, same end date.
  perform pg_temp.pay(biz_a, 'order_TEST106A', jsonb_build_object('kind', 'plan', 'plan_id', std.id));
  select * into sub from public.subscriptions where business_id = biz_a order by created_at desc limit 1;
  exp_a := sub.expiry_date;
  d := least(exp_a - today, 365);
  q := public.online_quote(biz_a, jsonb_build_object('kind', 'upgrade', 'plan_id', stdai.id));
  if (q ->> 'amount')::numeric <> round(round(stdai.list_price * (1 - disc / 100)) * d / 365.0)
                                   - round(round(std.list_price * (1 - disc / 100)) * d / 365.0)
     or (q ->> 'until')::date <> exp_a then
    raise exception 'FAIL 3a: upgrade price % (days %)', q, d;
  end if;
  begin
    perform public.online_quote(biz_a, jsonb_build_object('kind', 'upgrade', 'plan_id', std.id));
    raise exception 'FAIL 3b: upgrade to the same plan';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  q := public.online_quote(biz_a, jsonb_build_object('kind', 'upgrade', 'plan_id', life.id));
  if (q ->> 'amount')::numeric <> round(life.list_price * (1 - disc / 100)) - round(round(std.list_price * (1 - disc / 100)) * d / 365.0)
     or q ->> 'until' is not null then
    raise exception 'FAIL 3c: lifetime upgrade %', q;
  end if;
  v := public.online_account(tok);
  if jsonb_array_length(v -> 'upgrades') <> 2 or (v -> 'plan' ->> 'days_left')::int <> exp_a - today then
    raise exception 'FAIL 3d: account %', v;
  end if;
  raise notice 'PASS 3 (upgrade prices)';

  -- 4. Paying the upgrade: Standard + AI from today, same end date, a receipt.
  v := pg_temp.pay(biz_a, 'order_TEST106B', jsonb_build_object('kind', 'upgrade', 'plan_id', stdai.id));
  select * into sub from public.subscriptions where business_id = biz_a order by created_at desc limit 1;
  if not (v ->> 'ok')::boolean or sub.plan_id <> stdai.id or sub.expiry_date <> exp_a or sub.status <> 'active' then
    raise exception 'FAIL 4a: after upgrade % %', v, to_jsonb(sub);
  end if;
  if not exists (select 1 from public.subscription_payments where reference = 'pay_order_TEST106B'
                   and breakdown ->> 'upgrade_from' = 'Standard' and receipt_no is not null) then
    raise exception 'FAIL 4b: no upgrade payment';
  end if;
  begin
    perform public.online_quote(biz_a, jsonb_build_object('kind', 'upgrade', 'plan_id', std.id));
    raise exception 'FAIL 4c: a downgrade offered as an upgrade';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 4 (upgrade paid)';

  -- 5. To Lifetime: for life, nothing more to upgrade; the account lists both payments.
  v := pg_temp.pay(biz_a, 'order_TEST106C', jsonb_build_object('kind', 'upgrade', 'plan_id', life.id));
  select * into sub from public.subscriptions where business_id = biz_a order by created_at desc limit 1;
  if sub.plan_id <> life.id or sub.expiry_date <> date '2099-12-31' then raise exception 'FAIL 5a: not lifetime %', to_jsonb(sub); end if;
  v := public.online_account(tok);
  if jsonb_array_length(v -> 'upgrades') <> 0 or jsonb_array_length(v -> 'payments') <> 3
     or (select count(*) from jsonb_array_elements(v -> 'payments') x where x ->> 'kind' = 'upgrade') <> 2 then
    raise exception 'FAIL 5b: account %', v;
  end if;
  raise notice 'PASS 5 (to lifetime)';

  -- 6. A shop can't read another's account or call the server's functions.
  if public.online_account('0123456789abcdef0123456789abcdef') is not null then raise exception 'FAIL 6a: any token works'; end if;
  if (public.online_account(tok_b) ->> 'shop') <> 'Acct Shop B' then raise exception 'FAIL 6b: wrong shop'; end if;
  perform pg_temp.act(shop_b);
  begin
    perform public.online_account(tok);
    raise exception 'FAIL 6c: a shop read an account';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 6 (access)';
end $$;

reset role;
select 'shop account tests passed' as result;
rollback;
