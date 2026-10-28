-- ============================================================
-- Admin team and access (0098).
--
-- HOW TO RUN — on a STAGING copy, after 0098:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the last line shows "admin_team tests passed".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('98989898-0000-0000-0000-0000000000ad', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'team-owner@test.invalid'),
  ('98989898-0000-0000-0000-00000000005a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'team-sales@test.invalid'),
  ('98989898-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'team-shop@test.invalid');
insert into public.businesses (id, name, state_code, phone) values
  ('98989898-1111-0000-0000-00000000000a', 'Team Test Shop', '21', '9000098098');
update public.profiles set role = 'admin' where id = '98989898-0000-0000-0000-0000000000ad';
insert into public.admin_team (user_id, team_role) values ('98989898-0000-0000-0000-0000000000ad', 'owner');
update public.profiles set business_id = '98989898-1111-0000-0000-00000000000a', role = 'owner'
  where id = '98989898-0000-0000-0000-00000000000a';
insert into public.support_tickets (business_id, subject, message) values
  ('98989898-1111-0000-0000-00000000000a', 'Team test ticket', 'hello');

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

do $$
declare
  owner constant uuid := '98989898-0000-0000-0000-0000000000ad';
  sales constant uuid := '98989898-0000-0000-0000-00000000005a';
  shop_owner constant uuid := '98989898-0000-0000-0000-00000000000a';
  me jsonb; v jsonb; lead uuid; ticket uuid; n int;
begin
  -- 1. The owner adds a Sales member; unknown areas are dropped.
  perform pg_temp.act(owner);
  if not public.admin_is_owner() then raise exception 'FAIL 1a: owner is not owner'; end if;
  perform public.admin_team_save(sales, 'Sales Person', 'sales', array['leads', 'clients', 'bogus']);
  select id into ticket from public.support_tickets where subject = 'Team test ticket';
  if ticket is null then raise exception 'FAIL 1b: owner cannot see tickets'; end if;
  begin
    perform public.admin_team_save(shop_owner, 'Shop', 'sales', array['leads']);
    raise exception 'FAIL 1c: a shop login joined the team';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    perform public.admin_team_save(owner, 'Me', 'sales', array['leads']);
    raise exception 'FAIL 1d: the owner demoted themselves';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 1 (owner adds a member)';

  -- 2. Sales sees and does only its areas.
  perform pg_temp.act(sales);
  me := public.admin_me();
  if me is null or me ->> 'team_role' <> 'sales' or me -> 'areas' <> '["clients", "leads"]'::jsonb then
    raise exception 'FAIL 2a: admin_me %', me;
  end if;
  if not public.is_admin() or public.admin_can('payments') or not public.admin_can('leads') then
    raise exception 'FAIL 2b: areas wrong';
  end if;
  select count(*) into n from public.support_tickets where id = ticket;
  if n <> 0 then raise exception 'FAIL 2c: sales sees support requests'; end if;
  begin
    perform public.admin_set_website_discount(10);
    raise exception 'FAIL 2d: sales changed the website discount';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    perform public.admin_team_save(sales, 'Me', 'owner', null);
    raise exception 'FAIL 2e: sales made itself owner';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    update public.profiles set role = 'admin' where id = shop_owner;
  exception when others then null;
  end;
  if public.admin_can('clients', shop_owner) then raise exception 'FAIL 2f: a shop login became an admin'; end if;
  v := public.get_admin_today();
  if jsonb_array_length(v -> 'tickets') <> 0 or jsonb_array_length(v -> 'claims') <> 0 then
    raise exception 'FAIL 2g: Today shows other areas';
  end if;
  raise notice 'PASS 2 (sales limited to its areas)';

  -- 3. Assigned to.
  insert into public.leads (shop_name, phone) values ('Team Lead Shop', '9000098099') returning id into lead;
  if (select assigned_to from public.leads where id = lead) is distinct from sales then
    raise exception 'FAIL 3a: a new lead is not its creator''s';
  end if;
  perform pg_temp.act(owner);
  begin
    perform public.admin_assign('ticket', ticket, sales);
    raise exception 'FAIL 3b: ticket given to someone without support';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform public.admin_assign('ticket', ticket, owner);
  if (select assigned_to from public.support_tickets where id = ticket) is distinct from owner then
    raise exception 'FAIL 3c: ticket not assigned';
  end if;
  raise notice 'PASS 3 (assigned to)';

  -- 4. Removing a member ends access at once and frees their leads.
  perform public.admin_team_save(sales, 'Sales Person', 'sales', array['leads'], false);
  if (select assigned_to from public.leads where id = lead) is not null then
    raise exception 'FAIL 4a: lead still assigned to a removed member';
  end if;
  v := public.admin_team_list();
  if not exists (select 1 from jsonb_array_elements(v) e where e ->> 'id' = sales::text and not (e ->> 'active')::boolean) then
    raise exception 'FAIL 4b: removed member not listed';
  end if;
  perform pg_temp.act(sales);
  if public.is_admin() or public.admin_me() is not null then raise exception 'FAIL 4c: removed member still admin'; end if;
  select count(*) into n from public.leads where id = lead;
  if n <> 0 then raise exception 'FAIL 4d: removed member sees leads'; end if;
  raise notice 'PASS 4 (remove)';

  -- 5. A shop owner is not on the team and can't ask about others.
  perform pg_temp.act(shop_owner);
  if public.is_admin() or public.admin_can('leads', owner) then raise exception 'FAIL 5: shop sees team'; end if;
  raise notice 'PASS 5 (shops unaffected)';
end $$;

reset role;
select 'admin_team tests passed' as result;
rollback;
