-- ============================================================
-- Plans: managed in the admin panel, shown in the app without prices
-- (migration 0055).
--
-- HOW TO RUN — on a STAGING copy, after 0055:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('e5e5e5e5-0000-0000-0000-0000000000ad', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'plan-admin@test.invalid'),
  ('e5e5e5e5-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'plan-owner@test.invalid'),
  ('e5e5e5e5-0000-0000-0000-00000000000c', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'plan-staff@test.invalid'),
  ('e5e5e5e5-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'plan-other@test.invalid'),
  ('e5e5e5e5-0000-0000-0000-00000000000f', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'plan-fresh@test.invalid');

insert into public.businesses (id, name, state_code, phone) values
  ('e5e5e5e5-1111-0000-0000-00000000000a', 'PL Shop', '27', '9000033333'),
  ('e5e5e5e5-1111-0000-0000-00000000000b', 'PL Other Shop', '27', '9000044444');
update public.profiles set role = 'admin' where id = 'e5e5e5e5-0000-0000-0000-0000000000ad';
update public.profiles set business_id = 'e5e5e5e5-1111-0000-0000-00000000000a', role = 'owner'
  where id = 'e5e5e5e5-0000-0000-0000-00000000000a';
update public.profiles set business_id = 'e5e5e5e5-1111-0000-0000-00000000000a', role = 'staff'
  where id = 'e5e5e5e5-0000-0000-0000-00000000000c';
update public.profiles set business_id = 'e5e5e5e5-1111-0000-0000-00000000000b', role = 'owner'
  where id = 'e5e5e5e5-0000-0000-0000-00000000000b';
insert into public.feature_flags (business_id) values
  ('e5e5e5e5-1111-0000-0000-00000000000a'), ('e5e5e5e5-1111-0000-0000-00000000000b')
  on conflict (business_id) do nothing;

-- Basic: 2 features, 2 logins. Pro: nothing ticked = everything.
-- Custom and Hidden must never be offered.
insert into public.plans
  (id, name, software_id, monthly_price, yearly_price, included_features, user_limit,
   product_limit, is_custom, is_active, sort_order, notes)
select x.id::uuid, x.name, sp.id, x.monthly, x.yearly, x.features::jsonb, x.users,
       x.products, x.custom, x.active, x.ord, 'private note'
from public.software_products sp,
  (values
    ('e5e5e5e5-9999-0000-0000-00000000000a', 'PL Basic', 199, 1999, '["gst_billing", "reports"]', 2, 5, false, true, 1),
    ('e5e5e5e5-9999-0000-0000-00000000000b', 'PL Pro', 399, 3999, '[]', null, null, false, true, 2),
    ('e5e5e5e5-9999-0000-0000-00000000000c', 'PL Custom', 0, 9999, '[]', null, null, true, true, 3),
    ('e5e5e5e5-9999-0000-0000-00000000000d', 'PL Hidden', 99, 999, '[]', null, null, false, false, 4)
  ) as x(id, name, monthly, yearly, features, users, products, custom, active, ord)
where sp.slug = 'dukania';

-- PL Shop is on Basic. PL Other Shop was on Basic and is now on Pro.
insert into public.subscriptions (business_id, plan_id, status, expiry_date, created_at) values
  ('e5e5e5e5-1111-0000-0000-00000000000a', 'e5e5e5e5-9999-0000-0000-00000000000a', 'active',
   current_date + 30, now() - interval '40 days'),
  ('e5e5e5e5-1111-0000-0000-00000000000b', 'e5e5e5e5-9999-0000-0000-00000000000a', 'expired',
   current_date - 100, now() - interval '200 days'),
  ('e5e5e5e5-1111-0000-0000-00000000000b', 'e5e5e5e5-9999-0000-0000-00000000000b', 'active',
   current_date + 100, now() - interval '5 days');

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

do $$
declare
  admin  constant uuid := 'e5e5e5e5-0000-0000-0000-0000000000ad';
  owner  constant uuid := 'e5e5e5e5-0000-0000-0000-00000000000a';
  staff  constant uuid := 'e5e5e5e5-0000-0000-0000-00000000000c';
  fresh  constant uuid := 'e5e5e5e5-0000-0000-0000-00000000000f';
  shop   constant uuid := 'e5e5e5e5-1111-0000-0000-00000000000a';
  shop_b constant uuid := 'e5e5e5e5-1111-0000-0000-00000000000b';
  basic  constant uuid := 'e5e5e5e5-9999-0000-0000-00000000000a';
  pro    constant uuid := 'e5e5e5e5-9999-0000-0000-00000000000b';
  hidden constant uuid := 'e5e5e5e5-9999-0000-0000-00000000000d';
  v jsonb; gold uuid; trial uuid; t1 uuid; t2 uuid; new_shop uuid; days integer;
begin
  -- 1. A shop can't read prices: not from the table, not from its session
  --    data, not from the payment details.
  perform pg_temp.act(owner);
  if (select count(*) from public.plans) <> 0 then
    raise exception 'FAIL 1a: a shop can read the plans table';
  end if;
  v := public.get_my_context();
  if v -> 'subscription' -> 'plan' ->> 'name' is distinct from 'PL Basic'
     or v::text like '%monthly_price%' or v::text like '%yearly_price%'
     or v::text like '%private note%' then
    raise exception 'FAIL 1b: context %', left((v -> 'subscription')::text, 400);
  end if;
  v := public.get_payment_info();
  if v -> 'plan' ->> 'name' is distinct from 'PL Basic' or v::text like '%price%' then
    raise exception 'FAIL 1c: payment info %', v;
  end if;
  raise notice 'PASS 1 (prices and private notes never reach a shop)';

  -- 2. The app's plan list: own plan with usage, the plans on offer with
  --    their features, no custom / hidden / trial plan, no prices.
  v := public.get_plans_for_app();
  if v -> 'current' -> 'plan' ->> 'name' is distinct from 'PL Basic'
     or (v -> 'current' -> 'usage' ->> 'users')::integer <> 2
     or (v -> 'current' -> 'usage' ->> 'user_limit')::integer <> 2
     or (v -> 'current' -> 'usage' ->> 'product_limit')::integer <> 5 then
    raise exception 'FAIL 2a: current %', v -> 'current';
  end if;
  if not exists (select 1 from jsonb_array_elements(v -> 'plans') p where p ->> 'name' = 'PL Pro')
     or exists (select 1 from jsonb_array_elements(v -> 'plans') p
                where p ->> 'name' in ('PL Basic', 'PL Custom', 'PL Hidden')
                   or (p ->> 'is_trial')::boolean)
     or v::text like '%monthly_price%' or v::text like '%yearly_price%'
     or v::text like '%private note%' then
    raise exception 'FAIL 2b: plans %', left((v -> 'plans')::text, 400);
  end if;
  if not exists (select 1 from jsonb_array_elements(v -> 'current' -> 'plan' -> 'features') f
                 where f ->> 'key' = 'reports' and (f ->> 'included')::boolean)
     or not exists (select 1 from jsonb_array_elements(v -> 'current' -> 'plan' -> 'features') f
                    where f ->> 'key' = 'excel_import' and not (f ->> 'included')::boolean)
     or exists (select 1 from jsonb_array_elements(v -> 'plans') p,
                     jsonb_array_elements(p -> 'features') f
                where p ->> 'name' = 'PL Pro' and not (f ->> 'included')::boolean) then
    raise exception 'FAIL 2c: features %', v -> 'current' -> 'plan' -> 'features';
  end if;
  raise notice 'PASS 2 (app sees its plan, usage and the plans on offer)';

  -- 3. A shop can't manage plans.
  begin
    perform public.admin_save_plan(null, '{"name": "PL Hack"}');
    raise exception 'FAIL 3a: a shop created a plan';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    perform public.admin_set_plan_active(pro, false);
    raise exception 'FAIL 3b: a shop hid a plan';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 3 (plans are managed by SOFTRAXA only)';

  -- 4. Saving a plan is checked and logged.
  perform pg_temp.act(admin);
  begin
    perform public.admin_save_plan(null, '{"name": "  "}');
    raise exception 'FAIL 4a: plan without a name';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    perform public.admin_save_plan(null, '{"name": "pl basic"}');
    raise exception 'FAIL 4b: two plans with one name';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    perform public.admin_save_plan(null, '{"name": "PL Gold", "included_features": ["rocket_mode"]}');
    raise exception 'FAIL 4c: unknown feature accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    perform public.admin_save_plan(null, '{"name": "PL Gold", "yearly_price": -1}');
    raise exception 'FAIL 4d: negative price accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    perform public.admin_save_plan(null, '{"name": "PL Gold", "user_limit": 0}');
    raise exception 'FAIL 4e: limit 0 accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  gold := public.admin_save_plan(null, jsonb_build_object(
    'name', 'PL Gold', 'description', 'For bigger shops',
    'highlights', jsonb_build_array('  Priority support ', ''),
    'yearly_price', 5000, 'user_limit', 5,
    'included_features', jsonb_build_array('gst_billing'), 'is_recommended', true));
  if (select highlights from public.plans where id = gold) <> '["Priority support"]'::jsonb
     or (select yearly_price from public.plans where id = gold) <> 5000
     or not (select is_recommended and is_active from public.plans where id = gold)
     or not exists (select 1 from public.audit_logs
                    where action = 'plan.created' and entity_id = gold::text) then
    raise exception 'FAIL 4f: plan not saved or not logged';
  end if;
  raise notice 'PASS 4 (plan saved with checks, logged)';

  -- 5. Changing a plan's features reaches the shops on it now — and only
  --    those (PL Other Shop left Basic for Pro).
  perform public.admin_save_plan(basic, jsonb_build_object(
    'name', 'PL Basic', 'monthly_price', 199, 'yearly_price', 1999,
    'user_limit', 2, 'product_limit', 5,
    'included_features', jsonb_build_array('gst_billing')));
  if (select reports from public.feature_flags where business_id = shop)
     or not (select gst_billing from public.feature_flags where business_id = shop) then
    raise exception 'FAIL 5a: feature change did not reach the shop';
  end if;
  if not (select reports from public.feature_flags where business_id = shop_b) then
    raise exception 'FAIL 5b: a shop that left the plan was changed';
  end if;
  if not exists (select 1 from public.audit_logs
                 where action = 'plan.updated' and entity_id = basic::text) then
    raise exception 'FAIL 5c: plan change not logged';
  end if;
  raise notice 'PASS 5 (feature changes reach current shops only)';

  -- 6. The owner asks for a plan; it arrives as a support request.
  perform pg_temp.act(staff);
  begin
    perform public.request_plan_change(pro);
    raise exception 'FAIL 6a: staff asked for a plan change';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform pg_temp.act(owner);
  begin
    perform public.request_plan_change(basic);
    raise exception 'FAIL 6b: asked for the plan it already has';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    perform public.request_plan_change(hidden);
    raise exception 'FAIL 6c: asked for a hidden plan';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  t1 := public.request_plan_change(pro);
  t2 := public.request_plan_change(pro);
  if t1 is distinct from t2 then raise exception 'FAIL 6d: asking twice made two requests'; end if;
  v := public.get_plans_for_app();
  if (v ->> 'requested_plan_id')::uuid is distinct from pro then
    raise exception 'FAIL 6e: request not shown: %', v ->> 'requested_plan_id';
  end if;
  perform pg_temp.act(admin);
  if not (select t.status <> 'resolved' and t.last_reply_at is null
                 and t.subject = 'Plan request: PL Pro'
          from public.support_tickets t where t.id = t1) then
    raise exception 'FAIL 6f: request is not waiting for SOFTRAXA';
  end if;
  raise notice 'PASS 6 (owner asks once; SOFTRAXA sees it)';

  -- 7. Moving the shop to the plan closes the request, applies the plan
  --    (nothing ticked = everything on) and lifts the login limit.
  perform public.admin_renew_subscription(shop, pro, 'year', null, 2000, 'upi', 'UTRPLAN1');
  if (select status::text from public.support_tickets where id = t1) <> 'resolved'
     or not exists (select 1 from public.support_messages where ticket_id = t1 and from_softraxa) then
    raise exception 'FAIL 7a: the request did not close itself';
  end if;
  if not (select reports and excel_import from public.feature_flags where business_id = shop) then
    raise exception 'FAIL 7b: an all-features plan left features off';
  end if;
  perform pg_temp.act(owner);
  v := public.get_plans_for_app();
  if v -> 'current' -> 'plan' ->> 'name' is distinct from 'PL Pro'
     or v ->> 'requested_plan_id' is not null
     or v -> 'current' -> 'usage' ->> 'user_limit' is not null
     or not exists (select 1 from jsonb_array_elements(v -> 'plans') p where p ->> 'name' = 'PL Basic')
     or public.support_unread_count() < 1 then
    raise exception 'FAIL 7c: %', left(v::text, 400);
  end if;
  raise notice 'PASS 7 (plan change closes the request and applies the plan)';

  -- 8. Hide and delete.
  perform pg_temp.act(admin);
  perform public.admin_set_plan_active(gold, false);
  perform pg_temp.act(owner);
  v := public.get_plans_for_app();
  if exists (select 1 from jsonb_array_elements(v -> 'plans') p where p ->> 'name' = 'PL Gold') then
    raise exception 'FAIL 8a: a hidden plan is offered';
  end if;
  perform pg_temp.act(admin);
  begin
    perform public.admin_delete_plan(basic);
    raise exception 'FAIL 8b: deleted a plan shops have used';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform public.admin_delete_plan(gold);
  if exists (select 1 from public.plans where id = gold) then
    raise exception 'FAIL 8c: unused plan not deleted';
  end if;
  raise notice 'PASS 8 (hidden plans are not offered; used plans can''t be deleted)';

  -- 9. One trial plan; a new shop starts on it for the product's trial
  --    length, with its features.
  trial := public.admin_save_plan(null, jsonb_build_object(
    'name', 'PL Trial', 'is_trial', true, 'user_limit', 1,
    'included_features', jsonb_build_array('gst_billing', 'reports')));
  if (select count(*) from public.plans p join public.software_products sp on sp.id = p.software_id
      where p.is_trial and sp.slug = 'dukania') <> 1 then
    raise exception 'FAIL 9a: more than one trial plan';
  end if;
  begin
    perform public.admin_delete_plan(trial);
    raise exception 'FAIL 9b: deleted the trial plan';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  select trial_days into days from public.software_products where slug = 'dukania';
  perform pg_temp.act(fresh);
  new_shop := public.create_business('{"name": "PL New Shop"}');
  v := public.get_plans_for_app();
  if v -> 'current' -> 'plan' ->> 'name' is distinct from 'PL Trial'
     or v -> 'current' ->> 'status' <> 'trial'
     or (v -> 'current' ->> 'expiry_date')::date <> current_date + days
     or exists (select 1 from jsonb_array_elements(v -> 'plans') p where p ->> 'name' = 'PL Trial') then
    raise exception 'FAIL 9c: new shop %', v -> 'current';
  end if;
  perform pg_temp.act(admin);
  if (select excel_import from public.feature_flags where business_id = new_shop)
     or not (select reports from public.feature_flags where business_id = new_shop) then
    raise exception 'FAIL 9d: trial plan features not applied';
  end if;
  raise notice 'PASS 9 (new shops start on the trial plan, % days)', days;

  -- 10. System health knows 0055.
  v := public.get_system_health();
  if not (v -> 'migrations' ->> '0055')::boolean or not (v ->> 'trial_plan_set')::boolean then
    raise exception 'FAIL 10: %', v;
  end if;
  raise notice 'PASS 10 (health: 0055 applied, trial plan set)';
end $$;

reset role;
do $$ begin raise notice 'ALL PLAN CHECKS PASSED — rolling back test data'; end $$;
rollback;
