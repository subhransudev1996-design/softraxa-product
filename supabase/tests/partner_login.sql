-- ============================================================
-- Partner login (0107): a login linked by the server, the partner's own
-- numbers, their UPI ID, switching off the private link, who can do what.
--
-- HOW TO RUN — on a STAGING copy, after 0107:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the last line shows "partner login tests passed".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('10710710-0000-0000-0000-0000000000ad', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'plog-owner@test.invalid'),
  ('10710710-0000-0000-0000-0000000000ac', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'plog-accounts@test.invalid'),
  ('10710710-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'plog-partner@test.invalid'),
  ('10710710-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'plog-other@test.invalid');
update public.profiles set role = 'admin'
  where id in ('10710710-0000-0000-0000-0000000000ad', '10710710-0000-0000-0000-0000000000ac');
insert into public.admin_team (user_id, team_role, areas) values
  ('10710710-0000-0000-0000-0000000000ad', 'owner', '{}'),
  ('10710710-0000-0000-0000-0000000000ac', 'accounts', '{payments}');

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
  owner constant uuid := '10710710-0000-0000-0000-0000000000ad';
  accounts constant uuid := '10710710-0000-0000-0000-0000000000ac';
  partner constant uuid := '10710710-0000-0000-0000-00000000000a';
  other constant uuid := '10710710-0000-0000-0000-00000000000b';
  ptn jsonb; pid uuid; tok text; v jsonb;
begin
  perform pg_temp.act(owner);
  ptn := public.admin_save_partner(jsonb_build_object('name', 'Plog Priya', 'code', 'PLOGTEST', 'upi_id', 'old@upi'));
  pid := (ptn ->> 'id')::uuid;
  tok := ptn ->> 'stats_token';

  -- 1. Nobody links a login by themselves; the server can.
  perform pg_temp.act(partner);
  begin
    perform public.admin_link_partner_login(pid, partner, 'plog-partner@test.invalid');
    raise exception 'FAIL 1a: a user linked itself to a partner';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  if public.my_partner() is not null then raise exception 'FAIL 1b: numbers before the link'; end if;
  perform pg_temp.act(owner);
  begin
    perform public.admin_link_partner_login(pid, owner, 'x@test.invalid');
    raise exception 'FAIL 1c: linked outside the server';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform pg_temp.server();
  perform public.admin_link_partner_login(pid, partner, 'plog-partner@test.invalid');
  raise notice 'PASS 1 (link)';

  -- 2. The partner sees their own numbers; anyone else sees nothing.
  perform pg_temp.act(partner);
  v := public.my_partner();
  if v ->> 'name' <> 'Plog Priya' or v ->> 'upi_id' <> 'old@upi' or v ->> 'email' <> 'plog-partner@test.invalid'
     or jsonb_array_length(v -> 'months') <> 6 then
    raise exception 'FAIL 2a: my_partner %', v;
  end if;
  if (select count(*) from public.partners) <> 0 then raise exception 'FAIL 2b: a partner reads the partners table'; end if;
  perform pg_temp.act(other);
  if public.my_partner() is not null then raise exception 'FAIL 2c: another user got the numbers'; end if;
  begin
    perform public.my_partner_set_upi('hack@upi');
    raise exception 'FAIL 2d: another user changed the UPI ID';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 2 (own numbers)';

  -- 3. Their own UPI ID: checked, saved.
  perform pg_temp.act(partner);
  begin
    perform public.my_partner_set_upi('not a upi');
    raise exception 'FAIL 3a: a bad UPI ID accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform public.my_partner_set_upi('new@okaxis');
  if public.my_partner() ->> 'upi_id' <> 'new@okaxis' then raise exception 'FAIL 3b: UPI ID not saved'; end if;
  raise notice 'PASS 3 (UPI ID)';

  -- 4. The private link can be switched off, by marketing only.
  if public.partner_stats(tok) is null then raise exception 'FAIL 4a: link should work'; end if;
  perform pg_temp.act(accounts);
  begin
    perform public.admin_set_partner_link(pid, false);
    raise exception 'FAIL 4b: accounts switched the link';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform pg_temp.act(owner);
  perform public.admin_set_partner_link(pid, false);
  if public.partner_stats(tok) is not null then raise exception 'FAIL 4c: link still works'; end if;
  perform pg_temp.act(partner);
  if public.my_partner() is null then raise exception 'FAIL 4d: login stopped with the link'; end if;
  raise notice 'PASS 4 (private link)';

  -- 5. Removing the login ends it.
  perform pg_temp.server();
  perform public.admin_link_partner_login(pid, null, '');
  perform pg_temp.act(partner);
  if public.my_partner() is not null then raise exception 'FAIL 5: login still works'; end if;
  raise notice 'PASS 5 (remove)';
end $$;

reset role;
select 'partner login tests passed' as result;
rollback;
