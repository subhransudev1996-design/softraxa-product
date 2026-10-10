-- ============================================================
-- Bill settings: terms & conditions, footer, stock no. (migration 0076).
--
-- HOW TO RUN — on a STAGING copy, after 0076:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('76767676-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'bs-owner-a@test.invalid'),
  ('76767676-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'bs-staff-a@test.invalid'),
  ('76767676-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'bs-owner-b@test.invalid');
insert into public.businesses (id, name, state_code) values
  ('76767676-1111-0000-0000-00000000000a', 'BSSHOPALPHA', '21'),
  ('76767676-1111-0000-0000-00000000000b', 'BSSHOPBETA', '21');
update public.profiles set business_id = '76767676-1111-0000-0000-00000000000a', role = 'owner'
  where id = '76767676-0000-0000-0000-00000000000a';
update public.profiles set business_id = '76767676-1111-0000-0000-00000000000a', role = 'staff'
  where id = '76767676-0000-0000-0000-0000000000a1';
update public.profiles set business_id = '76767676-1111-0000-0000-00000000000b', role = 'owner'
  where id = '76767676-0000-0000-0000-00000000000b';
-- A 2-user plan, so the staff login counts (user limit, 0058) and check 4
-- tests the owner-only rule, not a login with no shop.
insert into public.plans (id, name, software_id, user_limit, included_features)
select '76767676-9999-0000-0000-00000000000a', 'BS Two Users', id, 2, '[]'
from public.software_products where slug = 'dukania';
insert into public.subscriptions (business_id, plan_id, status, expiry_date) values
  ('76767676-1111-0000-0000-00000000000a', '76767676-9999-0000-0000-00000000000a',
   'active', current_date + 30);

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

do $$
declare
  shop_a constant uuid := '76767676-1111-0000-0000-00000000000a';
  shop_b constant uuid := '76767676-1111-0000-0000-00000000000b';
  b record; bad boolean; n integer;
begin
  -- 1. New and existing shops start with no terms, the usual footer and no
  --    stock no.; get_my_context hands them to the app.
  perform pg_temp.act('76767676-0000-0000-0000-00000000000a');
  select bill_terms, bill_footer, bill_show_sku into b from public.businesses where id = shop_a;
  if b.bill_terms <> '' or b.bill_footer <> 'Thank you! Visit again.' or b.bill_show_sku then
    raise exception 'FAIL 1a: defaults %', b;
  end if;
  if (public.get_my_context() -> 'business' ->> 'bill_footer') is distinct from 'Thank you! Visit again.' then
    raise exception 'FAIL 1b: get_my_context does not carry the bill settings';
  end if;
  raise notice 'PASS 1 (defaults, and the app receives them)';

  -- 2. The owner saves them.
  update public.businesses
     set bill_terms = E'Exchange within 7 days with packing\nNo cash refund after goods sold',
         bill_footer = 'Visit again!', bill_show_sku = true
   where id = shop_a;
  select bill_terms, bill_footer, bill_show_sku into b from public.businesses where id = shop_a;
  if b.bill_footer <> 'Visit again!' or not b.bill_show_sku or b.bill_terms not like 'Exchange%refund%' then
    raise exception 'FAIL 2: owner save %', b;
  end if;
  raise notice 'PASS 2 (owner saves)';

  -- 3. Too long is refused.
  bad := false;
  begin update public.businesses set bill_footer = repeat('x', 201) where id = shop_a;
  exception when check_violation then bad := true; end;
  if not bad then raise exception 'FAIL 3a: a 201-character footer was saved'; end if;
  bad := false;
  begin update public.businesses set bill_terms = repeat('x', 1501) where id = shop_a;
  exception when check_violation then bad := true; end;
  if not bad then raise exception 'FAIL 3b: 1501 characters of terms were saved'; end if;
  raise notice 'PASS 3 (length limits)';

  -- 4. Staff, and other shops, can't change them.
  perform pg_temp.act('76767676-0000-0000-0000-0000000000a1');
  update public.businesses set bill_footer = 'staff was here' where id = shop_a;
  perform pg_temp.act('76767676-0000-0000-0000-00000000000b');
  update public.businesses set bill_footer = 'beta was here' where id = shop_a;
  get diagnostics n = row_count;
  perform pg_temp.act('76767676-0000-0000-0000-00000000000a');
  if (select bill_footer from public.businesses where id = shop_a) <> 'Visit again!' or n <> 0 then
    raise exception 'FAIL 4: changed by staff or another shop';
  end if;
  raise notice 'PASS 4 (owner only)';
end $$;

rollback;
