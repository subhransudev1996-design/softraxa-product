-- ============================================================
-- Launch fixes: trial status, staff over the user limit, account
-- deletion requests (migration 0058).
--
-- HOW TO RUN — on a STAGING copy (or your database), after 0058:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('e8e8e8e8-0000-0000-0000-0000000000ad', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'lf-admin@test.invalid'),
  ('e8e8e8e8-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'lf-owner@test.invalid'),
  ('e8e8e8e8-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'lf-staff1@test.invalid'),
  ('e8e8e8e8-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'lf-staff2@test.invalid'),
  ('e8e8e8e8-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'lf-client1@test.invalid'),
  ('e8e8e8e8-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'lf-client2@test.invalid');

update public.profiles set role = 'admin' where id = 'e8e8e8e8-0000-0000-0000-0000000000ad';

-- A shop on a 2-user plan with an owner and two staff (staff 1 added first).
insert into public.plans (id, name, software_id, user_limit, included_features)
select 'e8e8e8e8-9999-0000-0000-00000000000a', 'LF Two Users', id, 2, '[]'
from public.software_products where slug = 'dukania';
insert into public.businesses (id, name, state_code, phone) values
  ('e8e8e8e8-1111-0000-0000-00000000000a', 'LF Shop', '27', '9000088888');
update public.profiles set business_id = 'e8e8e8e8-1111-0000-0000-00000000000a', role = 'owner'
  where id = 'e8e8e8e8-0000-0000-0000-00000000000a';
update public.profiles set business_id = 'e8e8e8e8-1111-0000-0000-00000000000a', role = 'staff',
  created_at = now() - interval '2 days' where id = 'e8e8e8e8-0000-0000-0000-000000000001';
update public.profiles set business_id = 'e8e8e8e8-1111-0000-0000-00000000000a', role = 'staff',
  created_at = now() - interval '1 day' where id = 'e8e8e8e8-0000-0000-0000-000000000002';
insert into public.subscriptions (business_id, plan_id, status, expiry_date) values
  ('e8e8e8e8-1111-0000-0000-00000000000a', 'e8e8e8e8-9999-0000-0000-00000000000a', 'active', current_date + 30);
insert into public.products (business_id, name, selling_price) values
  ('e8e8e8e8-1111-0000-0000-00000000000a', 'LF Product', 10);

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

do $$
declare
  admin  constant uuid := 'e8e8e8e8-0000-0000-0000-0000000000ad';
  owner  constant uuid := 'e8e8e8e8-0000-0000-0000-00000000000a';
  staff1 constant uuid := 'e8e8e8e8-0000-0000-0000-000000000001';
  staff2 constant uuid := 'e8e8e8e8-0000-0000-0000-000000000002';
  plan2  constant uuid := 'e8e8e8e8-9999-0000-0000-00000000000a';
  trial uuid; b1 uuid; b2 uuid; s record; t1 uuid; t2 uuid; v jsonb;
begin
  -- 1. Clients created in the admin panel on the trial plan, or with no
  --    plan, are on trial with the trial plan.
  perform pg_temp.act(admin);
  select id into trial from public.plans where is_trial order by (software_id is null) limit 1;
  if trial is null then raise exception 'FAIL 1a: no trial plan is marked (Plans page)'; end if;
  b1 := public.admin_provision_business('e8e8e8e8-0000-0000-0000-0000000000c1', 'lf-client1@test.invalid',
          'Client One', '{"name": "LF Client One"}', trial, null, null);
  b2 := public.admin_provision_business('e8e8e8e8-0000-0000-0000-0000000000c2', 'lf-client2@test.invalid',
          'Client Two', '{"name": "LF Client Two"}', null, null, null);
  select status::text as status, plan_id into s from public.subscriptions where business_id = b1;
  if s.status <> 'trial' or s.plan_id <> trial then raise exception 'FAIL 1b: on the trial plan: %', s.status; end if;
  select status::text as status, plan_id into s from public.subscriptions where business_id = b2;
  if s.status <> 'trial' or s.plan_id is distinct from trial then
    raise exception 'FAIL 1c: no plan given: % / %', s.status, s.plan_id;
  end if;
  -- Suspend and activate again: still trial.
  perform public.admin_set_business_status(b1, true);
  perform public.admin_set_business_status(b1, false);
  if (select status::text from public.subscriptions where business_id = b1) <> 'trial' then
    raise exception 'FAIL 1d: reactivated trial became active';
  end if;
  raise notice 'PASS 1 (trial plan = trial status, also for admin-made clients)';

  -- 2. On a 2-user plan the owner and the first staff member work; the
  --    second staff member is shut out and told so.
  perform pg_temp.act(staff1);
  if (select count(*) from public.products where name = 'LF Product') <> 1
     or (public.get_my_context() ->> 'over_user_limit')::boolean then
    raise exception 'FAIL 2a: staff 1 lost access';
  end if;
  perform pg_temp.act(staff2);
  if (select count(*) from public.products where name = 'LF Product') <> 0
     or not (public.get_my_context() ->> 'over_user_limit')::boolean then
    raise exception 'FAIL 2b: staff 2 still has access';
  end if;
  perform pg_temp.act(owner);
  if (select count(*) from public.products where name = 'LF Product') <> 1
     or (public.get_my_context() ->> 'over_user_limit')::boolean then
    raise exception 'FAIL 2c: the owner lost access';
  end if;
  -- A bigger plan lets staff 2 back in.
  perform pg_temp.act(admin);
  perform public.admin_save_plan(plan2, jsonb_build_object('name', 'LF Two Users', 'user_limit', 3));
  perform pg_temp.act(staff2);
  if (select count(*) from public.products where name = 'LF Product') <> 1 then
    raise exception 'FAIL 2d: staff 2 not back after the limit was raised';
  end if;
  raise notice 'PASS 2 (staff over the user limit are shut out until the limit allows them)';

  -- 3. Only the owner asks for account deletion; asking twice is one request.
  begin
    perform public.request_account_deletion('testing');
    raise exception 'FAIL 3a: staff asked to delete the account';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform pg_temp.act(owner);
  t1 := public.request_account_deletion('closing the shop');
  t2 := public.request_account_deletion('');
  if t1 is distinct from t2
     or (select subject from public.support_tickets where id = t1) <> 'Account deletion request'
     or (select deletion_requested_at from public.businesses
         where id = 'e8e8e8e8-1111-0000-0000-00000000000a') is null then
    raise exception 'FAIL 3b: deletion request not recorded once';
  end if;
  raise notice 'PASS 3 (owner''s deletion request reaches SOFTRAXA once)';

  -- 4. System health knows 0058.
  perform pg_temp.act(admin);
  v := public.get_system_health();
  if not (v -> 'migrations' ->> '0058')::boolean then raise exception 'FAIL 4: %', v; end if;
  raise notice 'PASS 4 (health: 0058 applied; Dukania trial is % days)', v ->> 'trial_days';
end $$;

reset role;
do $$ begin raise notice 'ALL LAUNCH FIX CHECKS PASSED — rolling back test data'; end $$;
rollback;
