-- ============================================================
-- Paying influencers (0110): PAN kept to the payments area, declining a
-- request with a reason, TDS on a payout, the deposit note, the board.
--
-- HOW TO RUN — on a STAGING copy, after 0110:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the last line shows "partner payouts tests passed".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('11011010-0000-0000-0000-0000000000ad', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'tds-owner@test.invalid'),
  ('11011010-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'tds-marketing@test.invalid'),
  ('11011010-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'tds-accounts@test.invalid'),
  ('11011010-0000-0000-0000-00000000000f', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'tds-partner@test.invalid'),
  ('11011010-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'tds-shop@test.invalid');
update public.profiles set role = 'admin' where id in
  ('11011010-0000-0000-0000-0000000000ad', '11011010-0000-0000-0000-0000000000a1', '11011010-0000-0000-0000-0000000000a2');
insert into public.admin_team (user_id, team_role, areas) values
  ('11011010-0000-0000-0000-0000000000ad', 'owner', '{}'),
  ('11011010-0000-0000-0000-0000000000a1', 'custom', '{marketing}'),
  ('11011010-0000-0000-0000-0000000000a2', 'custom', '{payments}');
update public.platform_settings set partner_min_payout = 1 where id = 1;

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
  owner constant uuid := '11011010-0000-0000-0000-0000000000ad';
  mkt constant uuid := '11011010-0000-0000-0000-0000000000a1';
  acc constant uuid := '11011010-0000-0000-0000-0000000000a2';
  partner constant uuid := '11011010-0000-0000-0000-00000000000f';
  shop constant uuid := '11011010-0000-0000-0000-00000000000a';
  today date := public.ist_date(now());
  ptn jsonb; v jsonb; b jsonb; r jsonb; pid uuid; biz uuid; std uuid; comm numeric; req uuid; payout uuid;
begin
  perform pg_temp.act(mkt);
  ptn := public.admin_save_partner(jsonb_build_object('name', 'Tds Neha', 'code', 'TDSTEST', 'upi_id', 'neha@okaxis'));
  pid := (ptn ->> 'id')::uuid;
  perform pg_temp.server();
  perform public.admin_link_partner_login(pid, partner, 'tds-partner@test.invalid');

  -- 1. PAN: format checked, the partner sees the last 4, only payments reads it.
  perform pg_temp.act(partner);
  begin
    perform public.my_partner_set_pan('NOTAPAN');
    raise exception 'FAIL 1a: bad PAN';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  if public.my_partner_set_pan(' abcde1234f ') <> '234F' then raise exception 'FAIL 1b: last 4'; end if;
  v := public.my_partner();
  if (v ->> 'has_pan')::boolean is not true or v ->> 'pan_last4' <> '234F' or v::text like '%ABCDE1234F%' then raise exception 'FAIL 1c: %', v; end if;
  if (select count(*) from public.partner_tax_details) <> 0 then raise exception 'FAIL 1d: partner reads the table'; end if;
  perform pg_temp.server();
  if public.partner_stats_of(pid)::text like '%1234F%' then raise exception 'FAIL 1e: PAN on the stats page'; end if;
  perform pg_temp.act(mkt);
  if (select count(*) from public.partner_tax_details) <> 0 then raise exception 'FAIL 1f: marketing reads PAN'; end if;
  if public.admin_partners()::text like '%1234F%' then raise exception 'FAIL 1g: PAN in admin_partners'; end if;
  begin
    perform public.admin_partner_payouts(today, today);
    raise exception 'FAIL 1h: marketing read the board';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    perform public.admin_partner_pan(pid);
    raise exception 'FAIL 1i: marketing read the PAN';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform pg_temp.act(acc);
  if public.admin_partner_pan(pid) <> 'ABCDE1234F' then raise exception 'FAIL 1j: payments can''t read it'; end if;
  perform public.admin_set_partner_pan(pid, 'zzzzz9999z');
  if public.admin_partner_pan(pid) <> 'ZZZZZ9999Z' then raise exception 'FAIL 1k: not changed'; end if;
  perform pg_temp.server();
  if exists (select 1 from public.audit_logs l where l.details::text like '%ZZZZZ9999Z%') then raise exception 'FAIL 1l: PAN in the log'; end if;
  perform pg_temp.act(acc);
  raise notice 'PASS 1 (PAN)';

  -- A sale, past the hold.
  perform pg_temp.act(shop);
  biz := public.create_business(jsonb_build_object('name', 'Tds Shop', 'phone', '9000110001'));
  perform public.apply_referral_code('TDSTEST');
  perform pg_temp.act(owner);
  select id into std from public.plans where name = 'Standard';
  perform public.admin_record_sale(biz, jsonb_build_object('plan_id', std, 'amount', 2519, 'mode', 'upi', 'reference', 'UTR110'));
  perform pg_temp.server();
  update public.partner_commissions set payable_on = today - 1 where partner_id = pid;
  select amount into comm from public.partner_commissions where partner_id = pid and kind = 'sale';

  -- 2. Declining: payments only, a reason needed; the partner sees it and can ask again.
  perform pg_temp.act(partner);
  r := public.my_partner_request_payout();
  perform pg_temp.act(acc);
  b := public.admin_partner_payouts(today, today);
  select e into v from jsonb_array_elements(b -> 'partners') e where (e ->> 'id')::uuid = pid;
  if (v ->> 'requested')::numeric <> comm or (v ->> 'payable')::numeric <> comm or v ->> 'pan' <> 'ZZZZZ9999Z' then raise exception 'FAIL 2a: %', v; end if;
  req := (v ->> 'request_id')::uuid;
  begin
    perform public.admin_decline_payout_request(req, '  ');
    raise exception 'FAIL 2b: no reason';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform pg_temp.act(mkt);
  begin
    perform public.admin_decline_payout_request(req, 'Nope');
    raise exception 'FAIL 2c: marketing declined';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform pg_temp.act(acc);
  perform public.admin_decline_payout_request(req, 'Your UPI ID bounced');
  begin
    perform public.admin_decline_payout_request(req, 'Again');
    raise exception 'FAIL 2d: declined twice';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  if exists (select 1 from jsonb_array_elements(public.admin_alerts() -> 'items') i where i ->> 'title' like 'Payout requested: Tds Neha%') then
    raise exception 'FAIL 2e: alert stays after declining';
  end if;
  b := public.admin_partner_payouts(today, today);
  select e into v from jsonb_array_elements(b -> 'partners') e where (e ->> 'id')::uuid = pid;
  if v ->> 'request_id' is not null or (v ->> 'payable')::numeric <> comm then raise exception 'FAIL 2f: still ready to pay: %', v; end if;
  perform pg_temp.act(partner);
  v := public.my_partner();
  if v -> 'last_declined' ->> 'reason' <> 'Your UPI ID bounced' or v ->> 'payout_request' is not null then raise exception 'FAIL 2g: %', v; end if;
  perform public.my_partner_request_payout();
  v := public.my_partner();
  if v ->> 'last_declined' is not null or v ->> 'payout_request' is null then raise exception 'FAIL 2h: %', v; end if;
  raise notice 'PASS 2 (decline)';

  -- 3. Paying with TDS: limits, the expense stays the full amount, the request closes.
  perform pg_temp.act(acc);
  begin
    perform public.admin_pay_partner(pid, jsonb_build_object('reference', 'UTR1', 'tds', comm));
    raise exception 'FAIL 3a: TDS of the whole payout';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    perform public.admin_pay_partner(pid, jsonb_build_object('reference', 'UTR1', 'tds', -1));
    raise exception 'FAIL 3b: negative TDS';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  r := public.admin_pay_partner(pid, jsonb_build_object('reference', 'UTR110P', 'tds', 10));
  payout := (r ->> 'payout_id')::uuid;
  if (r ->> 'net')::numeric <> comm - 10 or (r ->> 'amount')::numeric <> comm then raise exception 'FAIL 3c: %', r; end if;
  if (select e.amount from public.business_expenses e join public.partner_payouts o on o.expense_id = e.id where o.id = payout) <> comm then
    raise exception 'FAIL 3d: expense not the full amount';
  end if;
  if not exists (select 1 from public.partner_payout_requests where partner_id = pid and status = 'paid' and payout_id = payout) then
    raise exception 'FAIL 3e: open request not closed';
  end if;
  if (select status from public.partner_payout_requests where id = req) <> 'declined' then raise exception 'FAIL 3f: the declined one changed'; end if;
  perform pg_temp.act(partner);
  v := public.my_partner();
  if (v ->> 'paid')::numeric <> comm or (v ->> 'tds')::numeric <> 10 or (v -> 'payouts' -> 0 ->> 'tds')::numeric <> 10 or v ->> 'last_declined' is not null then
    raise exception 'FAIL 3g: %', v;
  end if;
  raise notice 'PASS 3 (TDS)';

  -- 4. The deposit note and the board; the old call still works without TDS.
  perform pg_temp.act(mkt);
  begin
    perform public.admin_set_tds_deposit(payout, jsonb_build_object('deposited_on', today, 'challan', 'C1'));
    raise exception 'FAIL 4a: marketing noted a deposit';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform pg_temp.act(acc);
  perform public.admin_set_tds_deposit(payout, jsonb_build_object('deposited_on', today, 'challan', 'C110'));
  b := public.admin_partner_payouts(today - 1, today + 1);
  select e into v from jsonb_array_elements(b -> 'payouts') e where (e ->> 'id')::uuid = payout;
  if (v ->> 'net')::numeric <> comm - 10 or v ->> 'tds_challan' <> 'C110' or v ->> 'pan' <> 'ZZZZZ9999Z' then raise exception 'FAIL 4b: %', v; end if;
  if exists (select 1 from jsonb_array_elements(b -> 'partners') e where (e ->> 'id')::uuid = pid) then
    raise exception 'FAIL 4c: paid partner still listed';
  end if;
  if (b -> 'declined' -> 0 ->> 'decline_reason') <> 'Your UPI ID bounced' then raise exception 'FAIL 4d: %', b -> 'declined'; end if;
  perform public.admin_set_tds_deposit(payout, jsonb_build_object('deposited_on', ''));
  if (select tds_deposited_on from public.partner_payouts where id = payout) is not null
     or (select tds_challan from public.partner_payouts where id = payout) <> '' then
    raise exception 'FAIL 4e: not cleared';
  end if;
  if jsonb_array_length(public.admin_partner_payouts(today + 5, today + 6) -> 'payouts') <> 0 then raise exception 'FAIL 4f: date range'; end if;
  raise notice 'PASS 4 (deposit, board)';

  -- 5. A shop can't reach any of it.
  perform pg_temp.act(shop);
  begin
    perform public.admin_set_partner_pan(pid, 'AAAAA1111A');
    raise exception 'FAIL 5a: a shop set a PAN';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    perform public.my_partner_set_pan('AAAAA1111A');
    raise exception 'FAIL 5b: a shop used the partner call';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    perform public.admin_partner_payouts(today, today);
    raise exception 'FAIL 5c: a shop read the board';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 5 (shop)';
end $$;

reset role;
select 'partner payouts tests passed' as result;
rollback;
