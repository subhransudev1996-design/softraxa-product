-- ============================================================
-- Two-step login enforced by the database (0111).
--
-- HOW TO RUN — on a STAGING copy, after 0111:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the last line shows "admin two step tests passed".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('11111111-0111-0000-0000-0000000000ad', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'mfa-owner@test.invalid'),
  ('11111111-0111-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'mfa-team@test.invalid');
update public.profiles set role = 'admin' where id in
  ('11111111-0111-0000-0000-0000000000ad', '11111111-0111-0000-0000-0000000000a1');
insert into public.admin_team (user_id, team_role, areas) values
  ('11111111-0111-0000-0000-0000000000ad', 'owner', '{}'),
  ('11111111-0111-0000-0000-0000000000a1', 'custom', '{marketing}');

-- The owner has two-step on; the team member has only an unfinished setup.
insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at) values
  (gen_random_uuid(), '11111111-0111-0000-0000-0000000000ad', 'test owner', 'totp', 'verified', now(), now()),
  (gen_random_uuid(), '11111111-0111-0000-0000-0000000000a1', 'test team', 'totp', 'unverified', now(), now());

create or replace function pg_temp.act(p_user uuid, p_aal text) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated', 'aal', p_aal)::text, true);
$$;
create or replace function pg_temp.server() returns void language sql as $$
  select set_config('role', 'service_role', true),
         set_config('request.jwt.claims', '{"role":"service_role"}', true);
$$;

set local role authenticated;

do $$
declare
  owner constant uuid := '11111111-0111-0000-0000-0000000000ad';
  team constant uuid := '11111111-0111-0000-0000-0000000000a1';
  pid uuid;
begin
  -- 1. Two-step on, password only: nothing an admin can do works.
  perform pg_temp.act(owner, 'aal1');
  if public.is_admin() then raise exception 'FAIL 1a: is_admin at aal1'; end if;
  if public.admin_can('marketing') then raise exception 'FAIL 1b: admin_can at aal1'; end if;
  if public.admin_is_owner() then raise exception 'FAIL 1c: admin_is_owner at aal1'; end if;
  if (select count(*) from public.businesses) <> 0 then raise exception 'FAIL 1d: read shops at aal1'; end if;
  begin
    perform public.admin_partners();
    raise exception 'FAIL 1e: admin_partners at aal1';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    perform public.admin_save_partner(jsonb_build_object('name', 'Nope', 'code', 'MFANOPE'));
    raise exception 'FAIL 1f: wrote at aal1';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 1 (password only is refused)';

  -- 2. After the code: everything works.
  perform pg_temp.act(owner, 'aal2');
  if not public.is_admin() or not public.admin_can('marketing') or not public.admin_is_owner() then
    raise exception 'FAIL 2a: refused at aal2';
  end if;
  pid := (public.admin_save_partner(jsonb_build_object('name', 'Mfa Ok', 'code', 'MFAOK')) ->> 'id')::uuid;
  if pid is null then raise exception 'FAIL 2b: no partner'; end if;
  raise notice 'PASS 2 (after the code)';

  -- 3. No finished two-step: works as before, with its own areas only.
  perform pg_temp.act(team, 'aal1');
  if not public.is_admin() or not public.admin_can('marketing') then raise exception 'FAIL 3a: refused without two-step'; end if;
  if public.admin_can('payments') or public.admin_is_owner() then raise exception 'FAIL 3b: more than its areas'; end if;
  raise notice 'PASS 3 (no two-step yet)';

  -- 4. A missing aal claim is not aal2.
  perform set_config('request.jwt.claims', json_build_object('sub', owner, 'role', 'authenticated')::text, true);
  if public.is_admin() then raise exception 'FAIL 4: no aal claim passed'; end if;
  raise notice 'PASS 4 (no claim)';

  -- 5. Server jobs are unchanged; the helper is not open to callers.
  perform pg_temp.server();
  perform public.assert_admin_area('payments');
  perform pg_temp.act(team, 'aal1');
  begin
    perform public.admin_mfa_ok();
    raise exception 'FAIL 5: helper is open';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 5 (server jobs)';
end $$;

reset role;
select 'admin two step tests passed' as result;
rollback;
