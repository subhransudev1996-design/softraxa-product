-- ============================================================
-- Asking for more staff logins; the plan screen's add-ons (0097).
--
-- HOW TO RUN — on a STAGING copy, after 0097:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the last line shows "staff_requests tests passed".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('97979797-0000-0000-0000-0000000000ad', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'req-admin@test.invalid'),
  ('97979797-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'req-owner@test.invalid'),
  ('97979797-0000-0000-0000-00000000000c', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'req-staff@test.invalid');
insert into public.businesses (id, name, state_code, phone) values
  ('97979797-1111-0000-0000-00000000000a', 'Request Test Shop', '21', '9000097097');
update public.profiles set role = 'admin' where id = '97979797-0000-0000-0000-0000000000ad';
update public.profiles set business_id = '97979797-1111-0000-0000-00000000000a', role = 'owner'
  where id = '97979797-0000-0000-0000-00000000000a';
update public.profiles set business_id = '97979797-1111-0000-0000-00000000000a', role = 'staff'
  where id = '97979797-0000-0000-0000-00000000000c';
insert into public.feature_flags (business_id) values ('97979797-1111-0000-0000-00000000000a')
  on conflict (business_id) do nothing;
-- On Standard (0096), so its staff member has a login.
insert into public.subscriptions (business_id, plan_id, status, expiry_date)
select '97979797-1111-0000-0000-00000000000a', id, 'active', current_date + 300
from public.plans where name = 'Standard';

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

do $$
declare
  admin constant uuid := '97979797-0000-0000-0000-0000000000ad';
  owner constant uuid := '97979797-0000-0000-0000-00000000000a';
  staff constant uuid := '97979797-0000-0000-0000-00000000000c';
  shop  constant uuid := '97979797-1111-0000-0000-00000000000a';
  t1 uuid; t2 uuid; v jsonb; std uuid; r jsonb;
begin
  -- 1. The owner asks; asking again updates the same request.
  perform pg_temp.act(owner);
  t1 := public.request_staff_login(1);
  t2 := public.request_staff_login(2);
  if t1 is distinct from t2 then raise exception 'FAIL 1a: a second request instead of one'; end if;
  if (select requested_staff from public.support_tickets where id = t1) <> 2 then
    raise exception 'FAIL 1b: count not updated';
  end if;
  v := public.get_plans_for_app();
  if not (v ->> 'staff_request_open')::boolean then raise exception 'FAIL 1c: request not shown in the app'; end if;
  if v::text like '%price%' then raise exception 'FAIL 1d: a price reached the app: %', v; end if;
  perform pg_temp.act(staff);
  begin
    perform public.request_staff_login(1);
    raise exception 'FAIL 1e: staff asked for logins';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 1 (one request per shop, owner only)';

  -- 2. Adding the logins answers and closes it; the app sees the add-on.
  perform pg_temp.act(admin);
  perform public.admin_add_addon(shop, jsonb_build_object('kind', 'staff', 'quantity', 2, 'amount', 2000,
    'mode', 'upi', 'reference', 'UTR97'));
  if (select status::text from public.support_tickets where id = t1) <> 'resolved' then
    raise exception 'FAIL 2a: request still open';
  end if;
  if not exists (select 1 from public.support_messages where ticket_id = t1 and from_softraxa) then
    raise exception 'FAIL 2b: no answer in the request';
  end if;
  perform pg_temp.act(owner);
  v := public.get_plans_for_app();
  if (v ->> 'staff_request_open')::boolean then raise exception 'FAIL 2c: request still shown'; end if;
  if jsonb_array_length(v -> 'addons') <> 1 or (v -> 'addons' -> 0 ->> 'quantity')::int <> 2 then
    raise exception 'FAIL 2d: add-ons in the app: %', v -> 'addons';
  end if;
  if (v -> 'current' -> 'usage' ->> 'user_limit')::int <> 5 then
    raise exception 'FAIL 2e: login limit %', v -> 'current' -> 'usage' ->> 'user_limit';
  end if;
  raise notice 'PASS 2 (request closes itself; add-ons in the app)';

  -- 3. The receipt's website total: discount on the plan, add-ons in full.
  perform pg_temp.act(admin);
  select id into std from public.plans where name = 'Standard';
  r := public.admin_record_sale(shop, jsonb_build_object('plan_id', std, 'extra_staff', 1,
    'amount', 3800, 'mode', 'upi', 'reference', 'UTR98'));
  if (r ->> 'website_total')::numeric
     <> round(3499 * (1 - (select website_discount_pct from public.platform_settings where id = 1) / 100)) + 1000 then
    raise exception 'FAIL 3: website total %', r ->> 'website_total';
  end if;
  raise notice 'PASS 3 (website total)';
end $$;

reset role;
select 'staff_requests tests passed' as result;
rollback;
