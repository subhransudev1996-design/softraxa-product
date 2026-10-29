-- ============================================================
-- Influencer partners (0104): code and link, linking a shop, commission
-- on the first payment, hold, payout, refunds, the stats page.
--
-- HOW TO RUN — on a STAGING copy, after 0104:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the last line shows "partners tests passed".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('10410410-0000-0000-0000-0000000000ad', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'ptn-owner@test.invalid'),
  ('10410410-0000-0000-0000-0000000000ac', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'ptn-accounts@test.invalid'),
  ('10410410-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'ptn-shop-a@test.invalid'),
  ('10410410-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'ptn-shop-b@test.invalid');
update public.profiles set role = 'admin'
  where id in ('10410410-0000-0000-0000-0000000000ad', '10410410-0000-0000-0000-0000000000ac');
insert into public.admin_team (user_id, team_role, areas) values
  ('10410410-0000-0000-0000-0000000000ad', 'owner', '{}'),
  ('10410410-0000-0000-0000-0000000000ac', 'accounts', '{payments}');
update public.platform_settings
   set partner_buyer_off_pct = 10, partner_commission_pct = 20, partner_hold_days = 15
 where id = 1;

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

do $$
declare
  owner constant uuid := '10410410-0000-0000-0000-0000000000ad';
  accounts constant uuid := '10410410-0000-0000-0000-0000000000ac';
  shop_a constant uuid := '10410410-0000-0000-0000-00000000000a';
  shop_b constant uuid := '10410410-0000-0000-0000-00000000000b';
  biz_a uuid; biz_b uuid; std uuid; ptn jsonb; pid uuid; v jsonb; sale jsonb; pay uuid;
  c public.partner_commissions; want numeric; n int; token text;
begin
  perform pg_temp.act(shop_a);
  biz_a := public.create_business(jsonb_build_object('name', 'Ptn Shop A', 'phone', '9000104001'));
  perform pg_temp.act(shop_b);
  biz_b := public.create_business(jsonb_build_object('name', 'Ptn Shop B', 'phone', '9000104002'));

  -- 1. Marketing adds a partner with the default deal; the code is also a 10% promo code.
  perform pg_temp.act(owner);
  select id into std from public.plans where name = 'Standard';
  if std is null then raise exception 'FAIL 0: no Standard plan on this database'; end if;
  ptn := public.admin_save_partner(jsonb_build_object('name', 'Ptn Rahul', 'code', 'ptntest10',
    'handle', '@ptnrahul', 'upi_id', 'rahul@upi'));
  pid := (ptn ->> 'id')::uuid;
  if ptn ->> 'code' <> 'PTNTEST10' or (ptn ->> 'commission_value')::numeric <> 20
     or (ptn ->> 'hold_days')::int <> 15 or length(ptn ->> 'stats_token') <> 32 then
    raise exception 'FAIL 1a: partner %', ptn;
  end if;
  if not exists (select 1 from public.promo_codes where code = 'PTNTEST10' and kind = 'percent' and value = 10 and active) then
    raise exception 'FAIL 1b: no promo code for the partner';
  end if;
  begin
    perform public.admin_save_partner(jsonb_build_object('name', 'Copy', 'code', 'PTNTEST10'));
    raise exception 'FAIL 1c: duplicate code accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform pg_temp.act(accounts);
  begin
    perform public.admin_save_partner(jsonb_build_object('name', 'Nope', 'code', 'PTNNOPE'));
    raise exception 'FAIL 1d: accounts added a partner';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 1 (partner and its code)';

  -- 2. The website: the offer behind the link, and clicks.
  v := public.public_partner('ptntest10');
  if v ->> 'name' <> 'Ptn Rahul' or (v ->> 'buyer_off_pct')::numeric <> 10 then raise exception 'FAIL 2a: %', v; end if;
  perform public.partner_click('PTNTEST10');
  perform public.partner_click('PTNTEST10');
  perform public.partner_click('NOSUCHCODE');
  perform pg_temp.act(owner);
  if (select clicks from public.partner_clicks where partner_id = pid) <> 2 then raise exception 'FAIL 2b: clicks'; end if;
  raise notice 'PASS 2 (link)';

  -- 3. Shop A enters the partner's code in the app (once; not by writing to businesses).
  perform pg_temp.act(shop_a);
  if public.apply_referral_code('ptntest10') <> 'Ptn Rahul' then raise exception 'FAIL 3a: code not applied'; end if;
  if (public.my_referral() ->> 'referred_by') <> 'Ptn Rahul' or (public.my_referral() ->> 'can_enter')::boolean then
    raise exception 'FAIL 3b: my_referral %', public.my_referral();
  end if;
  begin
    perform public.apply_referral_code('PTNTEST10');
    raise exception 'FAIL 3c: a second code accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    update public.businesses set partner_id = null where id = biz_a;
    raise exception 'FAIL 3d: the shop changed its partner';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 3 (shop enters the code)';

  -- 4. Its first payment earns 20% before GST, held 15 days; a renewal earns nothing.
  perform pg_temp.act(accounts);
  v := public.admin_check_promo('PTNTEST10', std);
  sale := public.admin_record_sale(biz_a, jsonb_build_object('plan_id', std, 'amount', (v ->> 'price')::numeric,
    'mode', 'upi', 'reference', 'UTR104A'));
  pay := (sale ->> 'payment_id')::uuid;
  perform public.admin_redeem_promo('PTNTEST10', pay);
  select * into c from public.partner_commissions where business_id = biz_a and kind = 'sale';
  select round(coalesce((tax ->> 'taxable')::numeric, amount) * 0.2) into want from public.subscription_payments where id = pay;
  if c.id is null or c.amount <> want or c.status <> 'pending' or c.rule <> '20%'
     or c.payable_on <> (select payment_date + 15 from public.subscription_payments where id = pay) then
    raise exception 'FAIL 4a: commission % (want %)', to_jsonb(c), want;
  end if;
  perform public.admin_record_sale(biz_a, jsonb_build_object('plan_id', std, 'amount', 1000, 'mode', 'upi', 'reference', 'UTR104B'));
  select count(*) into n from public.partner_commissions where business_id = biz_a;
  if n <> 1 then raise exception 'FAIL 4b: % commissions for one shop', n; end if;
  raise notice 'PASS 4 (commission)';

  -- 5. Nothing to pay during the hold; after it, one payout and a commission expense.
  begin
    perform public.admin_pay_partner(pid, jsonb_build_object('reference', 'UTR104P1'));
    raise exception 'FAIL 5a: paid during the hold';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform pg_temp.act(owner);
  update public.partner_commissions set payable_on = public.ist_date(now()) - 1 where id = c.id;
  perform pg_temp.act(accounts);
  v := public.admin_pay_partner(pid, jsonb_build_object('reference', 'UTR104P1'));
  if (v ->> 'amount')::numeric <> want then raise exception 'FAIL 5b: payout %', v; end if;
  if (select status from public.partner_commissions where id = c.id) <> 'paid' then raise exception 'FAIL 5c: not marked paid'; end if;
  if not exists (select 1 from public.business_expenses where category = 'commission' and amount = want and vendor = 'Ptn Rahul') then
    raise exception 'FAIL 5d: no expense';
  end if;
  raise notice 'PASS 5 (payout)';

  -- 6. A half refund after the payout takes half back from the next payout.
  perform public.admin_record_refund(pay, jsonb_build_object('amount',
    (select amount / 2 from public.subscription_payments where id = pay), 'reason', 'Test refund', 'reference', 'R104'));
  select coalesce(sum(amount), 0) into want from public.partner_commissions
   where partner_id = pid and kind = 'refund' and status = 'pending';
  if want >= 0 or abs(want + round(c.full_amount / 2)) > 1 then raise exception 'FAIL 6a: refund row %', want; end if;
  begin
    perform public.admin_pay_partner(pid, jsonb_build_object('reference', 'UTR104P2'));
    raise exception 'FAIL 6b: paid while owed back';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 6 (refund after payout)';

  -- 7. Shop B never entered a code: using it on the first payment links it;
  --    a full refund during the hold cancels the commission.
  sale := public.admin_record_sale(biz_b, jsonb_build_object('plan_id', std, 'amount', 2000, 'mode', 'upi', 'reference', 'UTR104C'));
  perform public.admin_redeem_promo('PTNTEST10', (sale ->> 'payment_id')::uuid);
  if (select partner_id from public.businesses where id = biz_b) is distinct from pid then raise exception 'FAIL 7a: not linked'; end if;
  if not exists (select 1 from public.partner_commissions where business_id = biz_b and status = 'pending') then
    raise exception 'FAIL 7b: no commission';
  end if;
  perform public.admin_record_refund((sale ->> 'payment_id')::uuid, jsonb_build_object('amount', 2000, 'reason', 'Test'));
  if (select status from public.partner_commissions where business_id = biz_b) <> 'cancelled' then
    raise exception 'FAIL 7c: commission not cancelled';
  end if;
  raise notice 'PASS 7 (code on payment, full refund)';

  -- 8. The stats page: counts and money, no shop names; a new link ends the old one.
  perform pg_temp.act(owner);
  v := public.admin_partners();
  select e into v from jsonb_array_elements(v) e where (e ->> 'id')::uuid = pid;
  if (v ->> 'signups')::int <> 2 or (v ->> 'paid_shops')::int <> 1 or (v ->> 'clicks')::int <> 2 then
    raise exception 'FAIL 8a: admin_partners %', v;
  end if;
  token := v ->> 'stats_token';
  v := public.partner_stats(token);
  if v is null or (v ->> 'signups')::int <> 2 or (v ->> 'paid')::numeric <= 0 or v::text like '%Ptn Shop%' then
    raise exception 'FAIL 8b: stats %', v;
  end if;
  if public.partner_stats('0123456789abcdef0123456789abcdef') is not null then raise exception 'FAIL 8c: any token works'; end if;
  perform public.admin_new_partner_link(pid);
  if public.partner_stats(token) is not null then raise exception 'FAIL 8d: old link still works'; end if;
  raise notice 'PASS 8 (stats page)';

  -- 9. Switched off: the link and the code stop.
  perform public.admin_save_partner(jsonb_build_object('id', pid, 'name', 'Ptn Rahul', 'active', false));
  if public.public_partner('PTNTEST10') is not null then raise exception 'FAIL 9a: link still live'; end if;
  if (public.admin_check_promo('PTNTEST10', std) ->> 'ok')::boolean then raise exception 'FAIL 9b: code still works'; end if;
  raise notice 'PASS 9 (switched off)';
end $$;

reset role;
select 'partners tests passed' as result;
rollback;
