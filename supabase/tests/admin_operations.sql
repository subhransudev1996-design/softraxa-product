-- ============================================================
-- Admin operations: manual renewals, payment claims, Today list,
-- logged corrections, system health (migration 0053).
--
-- HOW TO RUN — on a STAGING copy, after 0053:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('dfdfdfdf-0000-0000-0000-0000000000ad', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'ops-admin@test.invalid'),
  ('dfdfdfdf-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'ops-owner@test.invalid'),
  ('dfdfdfdf-0000-0000-0000-00000000000c', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'ops-staff@test.invalid'),
  ('dfdfdfdf-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'ops-other@test.invalid');

insert into public.businesses (id, name, state_code, phone) values
  ('dfdfdfdf-1111-0000-0000-00000000000a', 'OPS Expired Shop', '27', '9000011111'),
  ('dfdfdfdf-1111-0000-0000-00000000000b', 'OPS Other Shop', '27', '9000022222');
update public.profiles set role = 'admin' where id = 'dfdfdfdf-0000-0000-0000-0000000000ad';
update public.profiles set business_id = 'dfdfdfdf-1111-0000-0000-00000000000a', role = 'owner'
  where id = 'dfdfdfdf-0000-0000-0000-00000000000a';
update public.profiles set business_id = 'dfdfdfdf-1111-0000-0000-00000000000a', role = 'staff'
  where id = 'dfdfdfdf-0000-0000-0000-00000000000c';
update public.profiles set business_id = 'dfdfdfdf-1111-0000-0000-00000000000b', role = 'owner'
  where id = 'dfdfdfdf-0000-0000-0000-00000000000b';

insert into public.plans (id, name, monthly_price, yearly_price, included_features) values
  ('dfdfdfdf-9999-0000-0000-00000000000a', 'OPS Pro', 499, 4999, '["gst_billing", "reports"]');

-- Shop A expired 5 days ago (no plan). Shop B: an old expired row and a
-- newer active one — only the newer one may count.
insert into public.subscriptions (business_id, status, expiry_date, grace_days, created_at) values
  ('dfdfdfdf-1111-0000-0000-00000000000a', 'active', current_date - 5, 0, now() - interval '40 days'),
  ('dfdfdfdf-1111-0000-0000-00000000000b', 'expired', current_date - 100, 0, now() - interval '200 days'),
  ('dfdfdfdf-1111-0000-0000-00000000000b', 'active', current_date + 100, 0, now() - interval '5 days');

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

-- Keep the real UPI settings; set a test value inside this transaction.
update public.platform_settings set payment_upi_id = 'softraxa@okaxis' where id = 1;

set local role authenticated;

do $$
declare
  admin  constant uuid := 'dfdfdfdf-0000-0000-0000-0000000000ad';
  owner  constant uuid := 'dfdfdfdf-0000-0000-0000-00000000000a';
  staff  constant uuid := 'dfdfdfdf-0000-0000-0000-00000000000c';
  other  constant uuid := 'dfdfdfdf-0000-0000-0000-00000000000b';
  shop   constant uuid := 'dfdfdfdf-1111-0000-0000-00000000000a';
  shop_b constant uuid := 'dfdfdfdf-1111-0000-0000-00000000000b';
  pro    constant uuid := 'dfdfdfdf-9999-0000-0000-00000000000a';
  today  constant date := public.ist_date(now());
  v jsonb; claim uuid; claim2 uuid; exp1 date;
begin
  -- 1. The expired shop sees how to pay.
  perform pg_temp.act(owner);
  v := public.get_payment_info();
  if v ->> 'upi_id' <> 'softraxa@okaxis' or (v ->> 'expiry_date')::date <> current_date - 5 then
    raise exception 'FAIL 1: %', v;
  end if;
  raise notice 'PASS 1 (blocked shop gets the UPI ID and its expiry)';

  -- 2. Only the owner reports a payment; it needs the UTR; at most 3 wait.
  perform pg_temp.act(staff);
  begin
    perform public.submit_renewal_claim(499, 'UTR1');
    raise exception 'FAIL 2a: staff reported a payment';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform pg_temp.act(owner);
  begin
    perform public.submit_renewal_claim(499, '  ');
    raise exception 'FAIL 2b: claim without a reference';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  claim := public.submit_renewal_claim(499, '412345678901', 'paid on GPay');
  claim2 := public.submit_renewal_claim(499, '412345678902');
  perform public.submit_renewal_claim(499, '412345678903');
  begin
    perform public.submit_renewal_claim(499, '412345678904');
    raise exception 'FAIL 2c: fourth pending claim accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 2 (owner only, UTR required, max 3 waiting)';

  -- 3. Another shop can't see these claims; a shop can't renew itself.
  perform pg_temp.act(other);
  if exists (select 1 from public.renewal_claims where business_id = shop) then
    raise exception 'FAIL 3a: another shop sees the claims';
  end if;
  begin
    perform public.admin_renew_subscription(shop_b, null, 'year', null, 0);
    raise exception 'FAIL 3b: a shop renewed itself';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 3 (claims private; renew is admin only)';

  -- 4. Today shows the claims and the expired shop.
  perform pg_temp.act(admin);
  v := public.get_admin_today();
  if not exists (select 1 from jsonb_array_elements(v -> 'claims') c where (c ->> 'id')::uuid = claim)
     or not exists (select 1 from jsonb_array_elements(v -> 'expired') e
                    where (e ->> 'business_id')::uuid = shop) then
    raise exception 'FAIL 4: today %', left(v::text, 300);
  end if;
  raise notice 'PASS 4 (Today lists the claims and the expired shop)';

  -- 5. Renew from the claim: 1 month from TODAY (it had expired), plan Pro
  --    with its features, receipt numbered, claim verified, logged.
  v := public.admin_renew_subscription(shop, pro, 'month', null, 499, 'upi', '', null, '', claim);
  exp1 := (v ->> 'expiry_date')::date;
  if exp1 <> (today + interval '1 month')::date or v ->> 'receipt_no' not like 'SR-%'
     or (select status from public.renewal_claims where id = claim) <> 'verified'
     or (select reference from public.subscription_payments where id = (v ->> 'payment_id')::uuid) <> '412345678901'
     or (select status::text from public.latest_subscriptions where business_id = shop) <> 'active'
     or not (select reports from public.feature_flags where business_id = shop)
     or (select excel_import from public.feature_flags where business_id = shop)
     or not exists (select 1 from public.audit_logs where business_id = shop and action = 'subscription.renewed') then
    raise exception 'FAIL 5: %', v;
  end if;
  raise notice 'PASS 5 (renewed to %, receipt %, Pro features applied, logged)', exp1, v ->> 'receipt_no';

  -- 6. Renewing again extends from the current expiry, not from today.
  v := public.admin_renew_subscription(shop, null, 'year', null, 4999, 'cash', 'cash at shop');
  if (v ->> 'expiry_date')::date <> (exp1 + interval '1 year')::date then
    raise exception 'FAIL 6: %', v;
  end if;
  raise notice 'PASS 6 (second renewal adds a year to %)', exp1;

  -- 7. Rejecting a claim needs a reason; the shop sees it.
  begin
    perform public.admin_reject_renewal_claim(claim2, '');
    raise exception 'FAIL 7a: rejected without a reason';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform public.admin_reject_renewal_claim(claim2, 'No payment with this UTR');
  perform pg_temp.act(owner);
  if (public.get_payment_info() -> 'last_rejected' ->> 'reason') <> 'No payment with this UTR' then
    raise exception 'FAIL 7b: shop does not see the rejection';
  end if;
  raise notice 'PASS 7 (rejection with a reason the shop sees)';

  -- 8. Corrections need a reason and are logged; unknown features refused.
  perform pg_temp.act(admin);
  begin
    perform public.admin_update_subscription(shop, pro, 'active', today + 10, 0, '');
    raise exception 'FAIL 8a: change without a reason';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform public.admin_update_subscription(shop, pro, 'active', today + 10, 3, 'Typed the wrong year');
  begin
    perform public.admin_set_feature(shop, 'rocket_mode', true);
    raise exception 'FAIL 8b: unknown feature accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform public.admin_set_feature(shop, 'excel_import', true);
  if (select expiry_date from public.latest_subscriptions where business_id = shop) <> today + 10
     or not (select excel_import from public.feature_flags where business_id = shop)
     or (select count(*) from public.audit_logs where business_id = shop
         and action in ('subscription.updated', 'feature.enabled')) <> 2 then
    raise exception 'FAIL 8c: correction not applied or not logged';
  end if;
  raise notice 'PASS 8 (corrections need a reason and are logged)';

  -- 9. Each shop counts once (its latest subscription).
  if (select count(*) from public.latest_subscriptions where business_id = shop_b) <> 1
     or (select status::text from public.latest_subscriptions where business_id = shop_b) <> 'active' then
    raise exception 'FAIL 9: latest subscription wrong';
  end if;
  raise notice 'PASS 9 (Other Shop counted once, as active)';

  -- 10. System health answers, and 0053 is detected.
  v := public.get_system_health();
  if not (v -> 'migrations' ->> '0053')::boolean or not (v ->> 'payment_upi_set')::boolean then
    raise exception 'FAIL 10: %', v;
  end if;
  raise notice 'PASS 10 (health: 0053 applied, UPI set; nightly job %, ImageKit key %)',
    v ->> 'nightly_job', coalesce(v ->> 'imagekit_key', 'unknown');
end $$;

reset role;
do $$ begin raise notice 'ALL ADMIN OPERATIONS CHECKS PASSED — rolling back test data'; end $$;
rollback;
