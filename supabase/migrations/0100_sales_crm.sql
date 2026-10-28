-- ============================================================
-- 0100 — Sales CRM.
--
--   * Two more stages: New → Contacted → Demo → Trial → Negotiation →
--     Won (converted) / Lost;
--   * hot / warm / cold, a campaign tag, when the stage last changed;
--   * every stage change is written to the lead's activity log by the
--     database (who and when), whoever makes it;
--   * a shop that signs up in the app becomes a lead on "Trial" (or an
--     open lead with the same phone number moves to Trial), and it is
--     Won when its first payment is recorded;
--   * duplicate check by phone across leads and clients
--     (admin_find_duplicates) and a spreadsheet import that skips
--     duplicates (admin_import_leads);
--   * Today's follow-ups and removing a team member count the new open stages.
-- Leads area (0098).
-- ============================================================

-- ============================================================
-- A. Stages
-- ============================================================
alter type public.lead_status add value if not exists 'trial' before 'converted';
alter type public.lead_status add value if not exists 'negotiation' before 'converted';

-- ============================================================
-- B. Phone numbers compared on their last 10 digits
-- ============================================================
create or replace function public.phone_key(p text)
returns text language sql immutable as $$
  select right(regexp_replace(coalesce(p, ''), '\D', '', 'g'), 10)
$$;

alter table public.leads
  add column if not exists temperature text not null default 'warm',
  add column if not exists campaign text not null default '',
  add column if not exists stage_changed_at timestamptz not null default now(),
  add column if not exists lost_at timestamptz,
  add column if not exists phone_key text generated always as (public.phone_key(phone)) stored;
alter table public.leads drop constraint if exists leads_temperature_check;
alter table public.leads add constraint leads_temperature_check check (temperature in ('hot', 'warm', 'cold'));
create index if not exists idx_leads_phone_key on public.leads(phone_key) where phone_key <> '';
create index if not exists idx_businesses_phone_key on public.businesses(public.phone_key(phone));

update public.leads set stage_changed_at = updated_at;
update public.leads set lost_at = updated_at where status = 'lost' and lost_at is null;

-- ============================================================
-- C. Stage changes: dates, and a line in the activity log
-- ============================================================
create or replace function public.leads_stage_dates()
returns trigger language plpgsql as $$
begin
  if new.status is distinct from old.status then
    new.stage_changed_at := now();
    if new.status = 'converted' and new.converted_at is null then new.converted_at := now(); end if;
    new.lost_at := case when new.status = 'lost' then now() end;
  end if;
  return new;
end $$;
drop trigger if exists trg_leads_stage_dates on public.leads;
create trigger trg_leads_stage_dates before update on public.leads
  for each row execute function public.leads_stage_dates();

create or replace function public.leads_stage_log()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status then
    insert into public.lead_activities (lead_id, activity_type, note, created_by)
    values (new.id, 'status_change',
            old.status::text || ' → ' || new.status::text
              || case when new.status = 'lost' and new.lost_reason <> '' then ' (' || new.lost_reason || ')' else '' end,
            auth.uid());
  end if;
  return null;
end $$;
drop trigger if exists trg_leads_stage_log on public.leads;
create trigger trg_leads_stage_log after update on public.leads
  for each row execute function public.leads_stage_log();

-- ============================================================
-- D. App signups become leads; the first payment wins them
-- ============================================================
create or replace function public.lead_from_signup()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_key text := public.phone_key(new.phone);
  v_lead uuid;
begin
  -- Only a shop signing up itself; the panel links its own leads.
  if auth.uid() is null or public.is_admin() then return new; end if;
  if v_key <> '' then
    select id into v_lead from public.leads
     where phone_key = v_key and converted_business_id is null and status <> 'converted'
     order by created_at desc limit 1;
  end if;
  if v_lead is not null then
    update public.leads set status = 'trial', converted_business_id = new.id where id = v_lead;
  else
    insert into public.leads (shop_name, contact_name, phone, email, business_type, source, status,
                              converted_business_id, temperature, notes)
    values (new.name, coalesce(new.owner_name, ''), coalesce(new.phone, ''), coalesce(new.email, ''),
            new.business_type, 'app_signup', 'trial', new.id, 'hot', 'Signed up in the app.');
  end if;
  return new;
end $$;
drop trigger if exists trg_lead_from_signup on public.businesses;
create trigger trg_lead_from_signup after insert on public.businesses
  for each row execute function public.lead_from_signup();

create or replace function public.lead_won_on_payment()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.amount > 0 then
    update public.leads set status = 'converted'
     where converted_business_id = new.business_id and status <> 'converted';
  end if;
  return new;
end $$;
drop trigger if exists trg_lead_won_on_payment on public.subscription_payments;
create trigger trg_lead_won_on_payment after insert on public.subscription_payments
  for each row execute function public.lead_won_on_payment();

-- ============================================================
-- E. Duplicates and import
-- ============================================================

-- Leads and clients with the same phone number (last 10 digits).
create or replace function public.admin_find_duplicates(p_phone text, p_exclude uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_key text := public.phone_key(p_phone);
begin
  perform public.assert_admin_area('leads');
  if length(v_key) < 10 then return jsonb_build_object('leads', '[]'::jsonb, 'clients', '[]'::jsonb); end if;
  return jsonb_build_object(
    'leads', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'shop_name', l.shop_name, 'status', l.status))
                       from public.leads l
                       where l.phone_key = v_key and l.id is distinct from p_exclude), '[]'::jsonb),
    'clients', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'name', b.name))
                         from public.businesses b where public.phone_key(b.phone) = v_key), '[]'::jsonb));
end $$;

-- Rows from a spreadsheet: shop_name (needed), contact_name, phone, city,
-- business_type, source, temperature, campaign, notes. A phone number
-- already a lead or a client, or twice in the file, is skipped.
create or replace function public.admin_import_leads(p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  r jsonb;
  i int := 0;
  v_key text;
  v_seen text[] := '{}';
  v_added int := 0;
  v_skipped jsonb := '[]'::jsonb;
  v_type text;
  v_temp text;
begin
  perform public.assert_admin_area('leads');
  if jsonb_typeof(p_rows) <> 'array' then raise exception 'Rows must be a list'; end if;
  if jsonb_array_length(p_rows) > 2000 then raise exception 'Import up to 2,000 rows at a time'; end if;

  for r in select * from jsonb_array_elements(p_rows) loop
    i := i + 1;
    if btrim(coalesce(r ->> 'shop_name', '')) = '' then
      v_skipped := v_skipped || jsonb_build_object('row', i, 'shop_name', '', 'reason', 'No shop name');
      continue;
    end if;
    v_key := public.phone_key(r ->> 'phone');
    if v_key <> '' and (v_key = any(v_seen)
        or exists (select 1 from public.leads where phone_key = v_key)
        or exists (select 1 from public.businesses where public.phone_key(phone) = v_key)) then
      v_skipped := v_skipped || jsonb_build_object('row', i, 'shop_name', r ->> 'shop_name',
        'reason', case when v_key = any(v_seen) then 'Same phone twice in the file' else 'Already a lead or client' end);
      continue;
    end if;
    if v_key <> '' then v_seen := v_seen || v_key; end if;

    v_type := lower(btrim(coalesce(r ->> 'business_type', '')));
    if not v_type = any(enum_range(null::public.business_type)::text[]) then v_type := 'other'; end if;
    v_temp := lower(btrim(coalesce(r ->> 'temperature', '')));
    if v_temp not in ('hot', 'warm', 'cold') then v_temp := 'warm'; end if;

    insert into public.leads (shop_name, contact_name, phone, city, business_type, source, temperature,
                              campaign, notes, created_by)
    values (btrim(r ->> 'shop_name'), btrim(coalesce(r ->> 'contact_name', '')), btrim(coalesce(r ->> 'phone', '')),
            btrim(coalesce(r ->> 'city', '')), v_type::public.business_type,
            coalesce(nullif(lower(btrim(r ->> 'source')), ''), 'import'), v_temp,
            btrim(coalesce(r ->> 'campaign', '')), btrim(coalesce(r ->> 'notes', '')), auth.uid());
    v_added := v_added + 1;
  end loop;

  perform public.admin_log(null, 'leads.imported', 'lead', 'bulk',
    jsonb_build_object('added', v_added, 'skipped', jsonb_array_length(v_skipped)));
  return jsonb_build_object('added', v_added, 'skipped', v_skipped);
end $$;

revoke execute on function public.admin_find_duplicates(text, uuid) from public, anon;
revoke execute on function public.admin_import_leads(jsonb) from public, anon;
grant execute on function public.admin_find_duplicates(text, uuid) to authenticated;
grant execute on function public.admin_import_leads(jsonb) to authenticated;

-- ============================================================
-- F. The open stages now include Trial and Negotiation. Same functions
--    as in 0098; only the list of open stages changes.
-- ============================================================

-- get_admin_today (from 0098_admin_team.sql)
create or replace function public.get_admin_today()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_today date := public.ist_date(now());
  v_out jsonb;
begin
  perform public.assert_platform_admin();
  v_out := jsonb_build_object(
    'today', v_today,
    -- Shops that say they have paid: check your UPI app, then renew.
    'claims', coalesce((select jsonb_agg(t order by t.created_at) from (
        select c.id, c.business_id, b.name, b.phone, c.amount, c.reference, c.note, c.created_at,
               ls.plan_id, ls.expiry_date
        from public.renewal_claims c
        join public.businesses b on b.id = c.business_id
        left join public.latest_subscriptions ls on ls.business_id = c.business_id
        where c.status = 'pending') t), '[]'),
    -- Active or trial, expiring within 7 days.
    'expiring', coalesce((select jsonb_agg(t order by t.expiry_date) from (
        select b.id as business_id, b.name, b.phone, b.owner_name, ls.status, ls.expiry_date,
               ls.plan_id, p.name as plan_name, p.monthly_price, p.yearly_price
        from public.latest_subscriptions ls
        join public.businesses b on b.id = ls.business_id
        left join public.plans p on p.id = ls.plan_id
        where b.is_active and ls.status in ('active', 'trial')
          and ls.expiry_date between v_today and v_today + 7) t), '[]'),
    -- Expired in the last 60 days and not renewed (older ones are churned).
    'expired', coalesce((select jsonb_agg(t order by t.expiry_date desc) from (
        select b.id as business_id, b.name, b.phone, b.owner_name, ls.status, ls.expiry_date,
               ls.plan_id, p.name as plan_name, p.monthly_price, p.yearly_price
        from public.latest_subscriptions ls
        join public.businesses b on b.id = ls.business_id
        left join public.plans p on p.id = ls.plan_id
        where b.is_active and ls.status <> 'suspended'
          and ls.expiry_date + ls.grace_days < v_today
          and ls.expiry_date >= v_today - 60) t), '[]'),
    -- Support tickets waiting for Dukania: the shop wrote last (0054).
    'tickets', coalesce((select jsonb_agg(t order by t.waiting_since) from (
        select tk.id, tk.business_id, b.name, tk.subject, tk.status, tk.created_at,
               coalesce(tk.last_shop_message_at, tk.created_at) as waiting_since
        from public.support_tickets tk join public.businesses b on b.id = tk.business_id
        where public.ticket_needs_reply(tk)) t), '[]'),
    'open_tickets', (select count(*) from public.support_tickets where status <> 'resolved'),
    -- Signed up 2+ days ago and never finished the setup wizard.
    'setup', coalesce((select jsonb_agg(t order by t.created_at) from (
        select b.id as business_id, b.name, b.phone, b.owner_name, b.created_at
        from public.businesses b
        where b.is_active and not b.onboarding_done and b.created_at < now() - interval '2 days') t), '[]'),
    -- Paying/trial shops (7+ days old) with no bill in the last 7 days.
    'inactive', coalesce((select jsonb_agg(t order by t.last_bill nulls first) from (
        select b.id as business_id, b.name, b.phone, b.owner_name,
               (select max(i.created_at) from public.invoices i where i.business_id = b.id) as last_bill
        from public.businesses b
        join public.latest_subscriptions ls on ls.business_id = b.id
        where b.is_active and b.onboarding_done and b.created_at < now() - interval '7 days'
          and ls.status in ('active', 'trial') and ls.expiry_date >= v_today
          and not exists (select 1 from public.invoices i where i.business_id = b.id
                          and i.created_at > now() - interval '7 days')) t), '[]'),
    -- The latest nightly reconciliation.
    'reconciliation', (select jsonb_build_object('run_id', r.id, 'finished_at', r.finished_at,
                                                 'issues', r.issues, 'unexplained', r.unexplained)
                       from public.reconciliation_runs r order by r.started_at desc limit 1),
    -- Lead follow-ups due.
    'followups', coalesce((select jsonb_agg(t order by t.follow_up_date) from (
        select l.id, l.shop_name, l.contact_name, l.phone, l.status, l.follow_up_date
        from public.leads l
        where l.status in ('new', 'contacted', 'demo', 'trial', 'negotiation') and l.follow_up_date <= v_today) t), '[]')
  );
  -- Each group only for the people who handle it (0098).
  if not public.admin_can('payments') then v_out := v_out || jsonb_build_object('claims', '[]'::jsonb); end if;
  if not public.admin_can('support') then
    v_out := v_out || jsonb_build_object('tickets', '[]'::jsonb, 'open_tickets', 0);
  end if;
  if not public.admin_can('leads') then v_out := v_out || jsonb_build_object('followups', '[]'::jsonb); end if;
  if not public.admin_can('system') then v_out := v_out || jsonb_build_object('reconciliation', null); end if;
  return v_out;
end $$;

-- admin_team_save (from 0098_admin_team.sql)
create or replace function public.admin_team_save(
  p_user uuid, p_name text, p_role text, p_areas text[], p_active boolean default true)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_prof public.profiles;
  v_existed boolean;
  v_areas text[];
  v_active boolean := coalesce(p_active, true);
begin
  if not public.admin_is_owner() then
    raise exception 'Only the owner can change the team' using errcode = '42501';
  end if;
  if p_role is null or p_role not in ('owner', 'sales', 'support', 'accounts', 'custom') then
    raise exception 'Unknown role %', p_role;
  end if;
  select * into v_prof from public.profiles where id = p_user for update;
  if not found then raise exception 'No such login'; end if;
  if v_prof.business_id is not null then
    raise exception '% is a shop''s login. Use a different email for the team.', v_prof.email;
  end if;
  if p_user = auth.uid() and (p_role <> 'owner' or not v_active) then
    raise exception 'You can''t remove yourself or take away your own owner role';
  end if;

  v_areas := array(select distinct a from unnest(coalesce(p_areas, '{}'::text[])) a
                   where a = any(public.admin_all_areas()) order by 1);
  if p_role = 'owner' then v_areas := '{}'; end if;
  if p_role <> 'owner' and cardinality(v_areas) = 0 then
    raise exception 'Tick at least one area for this team member';
  end if;

  v_existed := exists (select 1 from public.admin_team where user_id = p_user);
  update public.profiles
     set role = 'admin', full_name = coalesce(nullif(trim(p_name), ''), full_name)
   where id = p_user;
  insert into public.admin_team (user_id, team_role, areas, active, added_by)
  values (p_user, p_role, v_areas, v_active, auth.uid())
  on conflict (user_id) do update
    set team_role = excluded.team_role, areas = excluded.areas, active = excluded.active;

  -- A removed member's open work goes back to "nobody".
  if not v_active then
    update public.leads set assigned_to = null
     where assigned_to = p_user and status in ('new', 'contacted', 'demo', 'trial', 'negotiation');
    update public.support_tickets set assigned_to = null
     where assigned_to = p_user and status <> 'resolved';
  end if;

  perform public.admin_log(null,
    case when not v_existed then 'team.added' when not v_active then 'team.removed' else 'team.changed' end,
    'admin_team', p_user::text,
    jsonb_build_object('email', v_prof.email, 'role', p_role, 'areas', v_areas, 'active', v_active));
end $$;
