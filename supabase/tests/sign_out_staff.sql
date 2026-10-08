-- ============================================================
-- Sign a staff member out of every device (migration 0073).
--
-- HOW TO RUN — on a STAGING copy, after 0073:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('e9e9e9e9-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'so-owner-a@test.invalid'),
  ('e9e9e9e9-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'so-staff-a@test.invalid'),
  ('e9e9e9e9-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'so-staff-a2@test.invalid'),
  ('e9e9e9e9-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'so-owner-b@test.invalid');

insert into public.businesses (id, name, state_code, phone, business_type) values
  ('e9e9e9e9-1111-0000-0000-00000000000a', 'SOSHOPALPHA', '27', '9000077771', 'grocery'),
  ('e9e9e9e9-1111-0000-0000-00000000000b', 'SOSHOPBETA', '27', '9000077772', 'grocery');
update public.profiles set business_id = 'e9e9e9e9-1111-0000-0000-00000000000a', role = 'owner'
  where id = 'e9e9e9e9-0000-0000-0000-00000000000a';
update public.profiles set business_id = 'e9e9e9e9-1111-0000-0000-00000000000a', role = 'staff'
  where id in ('e9e9e9e9-0000-0000-0000-0000000000a1', 'e9e9e9e9-0000-0000-0000-0000000000a2');
update public.profiles set business_id = 'e9e9e9e9-1111-0000-0000-00000000000b', role = 'owner'
  where id = 'e9e9e9e9-0000-0000-0000-00000000000b';

-- The staff member is logged in on two devices; the second staff member on one.
insert into auth.sessions (id, user_id) values
  ('e9e9e9e9-5555-0000-0000-0000000000a1', 'e9e9e9e9-0000-0000-0000-0000000000a1'),
  ('e9e9e9e9-5555-0000-0000-0000000000a3', 'e9e9e9e9-0000-0000-0000-0000000000a1'),
  ('e9e9e9e9-5555-0000-0000-0000000000a2', 'e9e9e9e9-0000-0000-0000-0000000000a2');
insert into auth.refresh_tokens (token, user_id, session_id) values
  ('so-test-token-1', 'e9e9e9e9-0000-0000-0000-0000000000a1', 'e9e9e9e9-5555-0000-0000-0000000000a1'),
  ('so-test-token-2', 'e9e9e9e9-0000-0000-0000-0000000000a1', 'e9e9e9e9-5555-0000-0000-0000000000a3'),
  ('so-test-token-3', 'e9e9e9e9-0000-0000-0000-0000000000a2', 'e9e9e9e9-5555-0000-0000-0000000000a2');

-- Act as a user, optionally on a given session.
create or replace function pg_temp.act(p_user uuid, p_session uuid default null)
returns void language sql as $$
  select set_config('request.jwt.claims',
    (jsonb_build_object('sub', p_user, 'role', 'authenticated')
     || case when p_session is null then '{}'::jsonb
             else jsonb_build_object('session_id', p_session) end)::text, true);
$$;

set local role authenticated;

do $$
declare
  owner_a  constant uuid := 'e9e9e9e9-0000-0000-0000-00000000000a';
  staff_a  constant uuid := 'e9e9e9e9-0000-0000-0000-0000000000a1';
  staff_a2 constant uuid := 'e9e9e9e9-0000-0000-0000-0000000000a2';
  owner_b  constant uuid := 'e9e9e9e9-0000-0000-0000-00000000000b';
  sess_1   constant uuid := 'e9e9e9e9-5555-0000-0000-0000000000a1';
  sess_2   constant uuid := 'e9e9e9e9-5555-0000-0000-0000000000a2';
  n integer; bad boolean;
begin
  -- 1. Before: the staff member's session is active.
  perform pg_temp.act(staff_a, sess_1);
  if not public.my_session_active() then raise exception 'FAIL 1a: session should be active'; end if;
  perform pg_temp.act(staff_a);
  if not public.my_session_active() then raise exception 'FAIL 1b: no session id should count as active'; end if;
  raise notice 'PASS 1 (active sessions are reported active)';

  -- 2. Only the owner of the same shop can do it, and not to an owner.
  perform pg_temp.act(staff_a2, sess_2);
  bad := false;
  begin perform public.sign_out_staff_user(staff_a);
  exception when others then bad := sqlerrm like '%Only the store owner%'; end;
  if not bad then raise exception 'FAIL 2a: staff signed another staff member out'; end if;
  perform pg_temp.act(owner_b);
  bad := false;
  begin perform public.sign_out_staff_user(staff_a);
  exception when others then bad := sqlerrm like '%not found in your store%'; end;
  if not bad then raise exception 'FAIL 2b: another shop''s owner signed staff out'; end if;
  perform pg_temp.act(owner_a);
  bad := false;
  begin perform public.sign_out_staff_user(owner_a);
  exception when others then bad := sqlerrm like '%not found in your store%'; end;
  if not bad then raise exception 'FAIL 2c: the owner was treated as staff'; end if;
  raise notice 'PASS 2 (only the shop''s owner, only staff)';

  -- 3. The owner signs the staff member out: both devices, nobody else.
  n := public.sign_out_staff_user(staff_a);
  if n <> 2 then raise exception 'FAIL 3a: % sessions ended, expected 2', n; end if;
  reset role;
  if exists (select 1 from auth.sessions where user_id = staff_a)
     or exists (select 1 from auth.refresh_tokens where user_id = staff_a::text) then
    raise exception 'FAIL 3b: sessions or refresh tokens left behind';
  end if;
  if not exists (select 1 from auth.sessions where user_id = staff_a2)
     or not exists (select 1 from auth.refresh_tokens where user_id = staff_a2::text) then
    raise exception 'FAIL 3c: another staff member was signed out too';
  end if;
  if not exists (select 1 from public.profiles where id = staff_a and role = 'staff'
                   and business_id = 'e9e9e9e9-1111-0000-0000-00000000000a') then
    raise exception 'FAIL 3d: the staff account was changed';
  end if;
  if not exists (select 1 from public.audit_logs where action = 'staff.signed_out'
                   and entity_id = staff_a::text) then
    raise exception 'FAIL 3e: not in the audit log';
  end if;
  set local role authenticated;
  raise notice 'PASS 3 (all devices signed out; account, other staff untouched; logged)';

  -- 4. The signed-out device now learns its session is gone.
  perform pg_temp.act(staff_a, sess_1);
  if public.my_session_active() then raise exception 'FAIL 4a: ended session still active'; end if;
  perform pg_temp.act(staff_a2, sess_2);
  if not public.my_session_active() then raise exception 'FAIL 4b: other staff session ended'; end if;
  raise notice 'PASS 4 (the app sees the ended session)';
end $$;

rollback;
