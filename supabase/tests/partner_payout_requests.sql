-- ============================================================
-- Partner funnel and payout requests (0108): on trial, trial ended, code
-- uses, sales without shop names, the minimum, one open request, the
-- team's alert, paying closes it.
--
-- HOW TO RUN — on a STAGING copy, after 0108:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the last line shows "partner payout tests passed".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('10810810-0000-0000-0000-0000000000ad', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'preq-owner@test.invalid'),
  ('10810810-0000-0000-0000-00000000000f', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'preq-partner@test.invalid'),
  ('10810810-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'preq-shop-a@test.invalid'),
  ('10810810-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'preq-shop-b@test.invalid');
update public.profiles set role = 'admin' where id = '10810810-0000-0000-0000-0000000000ad';
insert into public.admin_team (user_id, team_role, areas) values
  ('10810810-0000-0000-0000-0000000000ad', 'owner', '{}');
update public.platform_settings set partner_min_payout = 500 where id = 1;

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
  owner constant uuid := '10810810-0000-0000-0000-0000000000ad';
  partner constant uuid := '10810810-0000-0000-0000-00000000000f';
  shop_a constant uuid := '10810810-0000-0000-0000-00000000000a';
  shop_b constant uuid := '10810810-0000-0000-0000-00000000000b';
  biz_a uuid; biz_b uuid; std uuid; pid uuid; ptn jsonb; v jsonb; sale jsonb; comm numeric;
begin
  perform pg_temp.act(owner);
  ptn := public.admin_save_partner(jsonb_build_object('name', 'Preq Neha', 'code', 'PREQTEST'));
  pid := (ptn ->> 'id')::uuid;
  select id into std from public.plans where name = 'Standard';
  perform pg_temp.server();
  perform public.admin_link_partner_login(pid, partner, 'preq-partner@test.invalid');

  -- 1. Two shops join with the code: both on trial, then one trial ends.
  perform pg_temp.act(shop_a);
  biz_a := public.create_business(jsonb_build_object('name', 'Preq Shop A', 'phone', '9000108001'));
  perform public.apply_referral_code('PREQTEST');
  perform pg_temp.act(shop_b);
  biz_b := public.create_business(jsonb_build_object('name', 'Preq Shop B', 'phone', '9000108002'));
  perform public.apply_referral_code('PREQTEST');
  perform pg_temp.act(partner);
  v := public.my_partner();
  if (v ->> 'signups')::int <> 2 or (v ->> 'on_trial')::int <> 2 or (v ->> 'trial_ended')::int <> 0 then
    raise exception 'FAIL 1a: funnel %', v;
  end if;
  perform pg_temp.server();
  update public.subscriptions set expiry_date = public.ist_date(now()) - 2 where business_id = biz_b;
  perform pg_temp.act(partner);
  v := public.my_partner();
  if (v ->> 'on_trial')::int <> 1 or (v ->> 'trial_ended')::int <> 1 then raise exception 'FAIL 1b: funnel %', v; end if;
  raise notice 'PASS 1 (trial funnel)';

  -- 2. Shop A buys with the code: purchased, a code use, a sale without its name.
  perform pg_temp.act(owner);
  sale := public.admin_record_sale(biz_a, jsonb_build_object('plan_id', std, 'amount', 2519, 'mode', 'upi', 'reference', 'UTR108'));
  perform public.admin_redeem_promo('PREQTEST', (sale ->> 'payment_id')::uuid);
  perform pg_temp.act(partner);
  v := public.my_partner();
  if (v ->> 'on_trial')::int <> 0 or (v ->> 'paid_shops')::int <> 1 or (v ->> 'code_uses')::int <> 1
     or jsonb_array_length(v -> 'purchases') <> 1 or (v -> 'purchases' -> 0 ->> 'plan') <> 'Standard' then
    raise exception 'FAIL 2a: %', v;
  end if;
  if v::text like '%Preq Shop%' or v::text like '%9000108%' then raise exception 'FAIL 2b: a shop''s details shown'; end if;
  comm := (v -> 'purchases' -> 0 ->> 'commission')::numeric;
  raise notice 'PASS 2 (sale shown)';

  -- 3. No request during the hold, without a UPI ID, or under the minimum.
  begin
    perform public.my_partner_request_payout();
    raise exception 'FAIL 3a: asked with no UPI ID';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform public.my_partner_set_upi('neha@okaxis');
  begin
    perform public.my_partner_request_payout();
    raise exception 'FAIL 3b: asked during the hold';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform pg_temp.server();
  update public.partner_commissions set payable_on = public.ist_date(now()) - 1 where partner_id = pid;
  update public.platform_settings set partner_min_payout = comm + 1 where id = 1;
  perform pg_temp.act(partner);
  begin
    perform public.my_partner_request_payout();
    raise exception 'FAIL 3c: asked under the minimum';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform pg_temp.server();
  update public.platform_settings set partner_min_payout = comm where id = 1;
  raise notice 'PASS 3 (rules)';

  -- 4. One open request; the team sees it and gets an alert.
  perform pg_temp.act(partner);
  v := public.my_partner_request_payout();
  if (v ->> 'amount')::numeric <> comm then raise exception 'FAIL 4a: %', v; end if;
  begin
    perform public.my_partner_request_payout();
    raise exception 'FAIL 4b: asked twice';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  if (public.my_partner() -> 'payout_request' ->> 'amount')::numeric <> comm then raise exception 'FAIL 4c: not shown to the partner'; end if;
  perform pg_temp.act(owner);
  if not exists (select 1 from jsonb_array_elements(public.admin_partners()) e
                  where (e ->> 'id')::uuid = pid and (e -> 'payout_request' ->> 'amount')::numeric = comm) then
    raise exception 'FAIL 4d: not on the Influencers tab';
  end if;
  if not exists (select 1 from jsonb_array_elements(public.admin_alerts() -> 'items') i where i ->> 'title' like 'Payout requested: Preq Neha%') then
    raise exception 'FAIL 4e: no alert';
  end if;
  raise notice 'PASS 4 (request)';

  -- 5. Paying closes it; a partner can't see another's or the table.
  perform public.admin_pay_partner(pid, jsonb_build_object('reference', 'UTR108P'));
  if (select status from public.partner_payout_requests where partner_id = pid) <> 'paid' then raise exception 'FAIL 5a: still open'; end if;
  perform pg_temp.act(partner);
  v := public.my_partner();
  if v ->> 'payout_request' is not null or (v ->> 'paid')::numeric <> comm or (v -> 'purchases' -> 0 ->> 'status') <> 'paid' then
    raise exception 'FAIL 5b: %', v;
  end if;
  if (select count(*) from public.partner_payout_requests) <> 0 then raise exception 'FAIL 5c: a partner reads the requests table'; end if;
  perform pg_temp.act(shop_b);
  begin
    perform public.my_partner_request_payout();
    raise exception 'FAIL 5d: a shop asked for a payout';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 5 (paid)';
end $$;

reset role;
select 'partner payout tests passed' as result;
rollback;
