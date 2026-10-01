-- ============================================================
-- 0058_launch_fixes.sql — subscription gaps found before launch
--
--   * A shop on the trial plan is always "trial". A client created in the
--     admin panel on the Free Trial plan was saved as "active", and so was
--     a trial shop that was suspended and activated again. A trial client
--     created without a plan now gets the trial plan (its limits and
--     features), like a shop that signs up in the app.
--   * Staff over the plan's user limit lose access. Lowering a shop's
--     plan used to leave every staff login working. The owner and the
--     earliest staff up to the limit keep working; the rest are told to
--     ask the owner (get_my_context 'over_user_limit').
--   * request_account_deletion(): the owner asks SOFTRAXA to delete the
--     shop's account from inside the app (an app-store requirement). It
--     arrives in the admin panel as a support request.
--
-- Run AFTER 0057.
-- ============================================================

-- ============================================================
-- A. Trial plan = trial status
-- ============================================================
create or replace function public.subscription_trial_rules()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- No plan on a new trial: the trial plan, so trial limits apply.
  if tg_op = 'INSERT' and new.plan_id is null and new.status = 'trial' then
    select id into new.plan_id from public.plans
      where is_trial and (software_id is null or software_id is not distinct from new.software_id
                          or new.software_id is null)
      order by (software_id is null) limit 1;
  end if;
  -- On the trial plan you are on trial, whatever the caller said.
  if new.status = 'active' and new.plan_id is not null
     and exists (select 1 from public.plans where id = new.plan_id and is_trial) then
    new.status := 'trial';
  end if;
  return new;
end $$;

drop trigger if exists trg_subscriptions_trial_rules on public.subscriptions;
create trigger trg_subscriptions_trial_rules
  before insert or update of plan_id, status on public.subscriptions
  for each row execute function public.subscription_trial_rules();

-- A plan the trigger filled in brings its features with it.
create or replace function public.subscription_trial_features()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.plan_id is not null then
    perform public.set_plan_features(new.business_id, new.plan_id);
  end if;
  return new;
end $$;

drop trigger if exists trg_subscriptions_trial_features on public.subscriptions;
create trigger trg_subscriptions_trial_features
  after insert on public.subscriptions
  for each row execute function public.subscription_trial_features();

-- Existing rows: trials without a plan get the trial plan; trial-plan
-- shops marked active become trial.
update public.subscriptions s set plan_id = p.id
  from public.plans p
  where s.plan_id is null and s.status = 'trial' and p.is_trial
    and p.id = (select id from public.plans where is_trial order by (software_id is null) limit 1);
update public.subscriptions s set status = 'trial'
  from public.plans p
  where p.id = s.plan_id and p.is_trial and s.status = 'active';

-- ============================================================
-- B. Staff over the plan's user limit
-- ============================================================
-- Is this login inside the shop's user limit? The owner always is; staff
-- count in the order they were added (the owner takes one place).
create or replace function public.profile_within_user_limit(p_profile uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
  v_role     text;
  v_business uuid;
  v_limit    integer;
  v_rank     integer;
begin
  select role::text, business_id into v_role, v_business from public.profiles where id = p_profile;
  if v_role is distinct from 'staff' or v_business is null then return true; end if;
  v_limit := public.business_user_limit(v_business);
  if v_limit is null then return true; end if;
  select r.rank into v_rank from (
    select id, 1 + row_number() over (order by created_at, id) as rank
    from public.profiles
    where business_id = v_business and role = 'staff') r
  where r.id = p_profile;
  return coalesce(v_rank, 1) <= v_limit;
end $$;

-- The shop a login belongs to — none for staff over the user limit. Every
-- table's row-level security starts from this, so such a login can read
-- and write nothing (has_permission alone didn't cover tables any member
-- may read).
create or replace function public.current_business_id()
returns uuid language sql stable security definer set search_path = public as $$
  select p.business_id from public.profiles p
  where p.id = auth.uid()
    and (p.role <> 'staff' or public.profile_within_user_limit(p.id))
$$;

-- 0037's permission check, with staff over the user limit refused.
create or replace function public.has_permission(p_perm text)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
  v_role     text;
  v_business uuid;
  v_perms    jsonb;
begin
  if auth.uid() is null then
    return coalesce(public.request_role(), '') not in ('anon', 'authenticated');
  end if;

  select role::text, business_id into v_role, v_business
    from public.profiles where id = auth.uid();
  if v_role is null then return false; end if;
  if v_role = 'admin' then return true; end if;
  if v_business is null then return false; end if;
  if v_role = 'staff' and not public.profile_within_user_limit(auth.uid()) then return false; end if;
  if coalesce(p_perm, '') = '' then return true; end if;
  if v_role = 'owner' then return true; end if;
  if p_perm = 'owner' then return false; end if;

  select to_jsonb(sp) into v_perms from public.staff_permissions sp where sp.profile_id = auth.uid();
  if v_perms is not null and v_perms ? p_perm then
    return coalesce((v_perms ->> p_perm)::boolean, false);
  end if;
  return coalesce((public.staff_permission_defaults() ->> p_perm)::boolean, false);
end $$;

-- 0056's session bootstrap plus 'over_user_limit' (the app shows a
-- "ask the owner" screen for it). The shop comes from the profile itself:
-- current_business_id() is empty for a paused staff login, and the app
-- would take that for "no shop yet" and open the setup wizard.
create or replace function public.get_my_context()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := (select business_id from public.profiles where id = auth.uid());
  v_profile  record;
  v_limit    integer;
  v_count    integer;
  v_perms    jsonb := '{}'::jsonb;
  v_key      text;
begin
  select * into v_profile from public.profiles where id = auth.uid();
  v_limit := coalesce(public.business_user_limit(v_business), 999);
  select count(*) into v_count from public.profiles where business_id = v_business;

  for v_key in select jsonb_object_keys(public.staff_permission_defaults()) loop
    v_perms := v_perms || jsonb_build_object(v_key, public.has_permission(v_key));
  end loop;
  v_perms := v_perms || jsonb_build_object('can_manage_staff', public.has_permission('owner'));

  return jsonb_build_object(
    'profile',  to_jsonb(v_profile),
    'business', (select to_jsonb(b) from public.businesses b where b.id = v_business),
    'features', (select to_jsonb(f) from public.feature_flags f where f.business_id = v_business),
    'permissions', v_perms,
    'over_user_limit', not public.profile_within_user_limit(auth.uid()),
    'support', (select jsonb_build_object('whatsapp', s.support_whatsapp)
                from public.platform_settings s where s.id = 1),
    'subscription', (
      select to_jsonb(s) || jsonb_build_object(
        'plan', case when pl.id is null then null else public.plan_public(pl) end,
        'user_limit', v_limit, 'staff_count', v_count)
      from public.subscriptions s left join public.plans pl on pl.id = s.plan_id
      where s.business_id = v_business
      order by s.created_at desc limit 1));
end $$;

-- ============================================================
-- C. Account deletion requests
-- ============================================================
alter table public.businesses add column if not exists deletion_requested_at timestamptz;

-- The owner asks for the shop's account and data to be deleted. SOFTRAXA
-- handles it from the support request (bills may have to be kept for the
-- period GST law requires; the reply says what was deleted and when).
create or replace function public.request_account_deletion(p_reason text default '')
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_id       uuid;
begin
  if v_business is null then raise exception 'No shop selected'; end if;
  if not public.has_permission('owner') then
    raise exception 'Only the owner can ask to delete the account' using errcode = '42501';
  end if;
  select id into v_id from public.support_tickets
    where business_id = v_business and subject = 'Account deletion request' and status <> 'resolved'
    order by created_at desc limit 1;
  if v_id is not null then return v_id; end if;

  update public.businesses set deletion_requested_at = now() where id = v_business;
  insert into public.support_tickets (business_id, subject, message, created_by)
    values (v_business, 'Account deletion request',
            'Please delete my shop''s account and data.'
              || case when btrim(coalesce(p_reason, '')) = '' then ''
                      else E'\nReason: ' || btrim(p_reason) end,
            auth.uid())
    returning id into v_id;
  insert into public.audit_logs (business_id, user_id, action, entity, entity_id, details)
    values (v_business, auth.uid(), 'business.deletion_requested', 'business', v_business::text,
            jsonb_build_object('ticket', v_id));
  return v_id;
end $$;

-- ============================================================
-- D. System health knows about this migration
-- ============================================================
create or replace function public.get_system_health()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_cron     boolean := false;
  v_job      boolean := false;
  v_vault    boolean;
begin
  perform public.assert_platform_admin();
  v_cron := exists (select 1 from pg_extension where extname = 'pg_cron');
  if v_cron then
    begin
      execute 'select exists (select 1 from cron.job where jobname = ''dukania-nightly-reconciliation'')'
        into v_job;
    exception when others then v_job := false;
    end;
  end if;
  begin
    execute 'select exists (select 1 from vault.secrets where name = ''imagekit_private_key'')'
      into v_vault;
  exception when others then v_vault := null;
  end;

  return jsonb_build_object(
    'migrations', jsonb_build_object(
      '0050', to_regproc('public.run_reconciliation') is not null,
      '0051', to_regproc('public.set_opening_balance') is not null,
      '0052', to_regproc('public.claim_approval_notification') is not null,
      '0053', to_regproc('public.admin_renew_subscription') is not null,
      '0054', to_regproc('public.admin_reply_ticket') is not null,
      '0055', to_regproc('public.admin_save_plan') is not null,
      '0056', to_regproc('public.admin_save_settings') is not null,
      '0057', to_regproc('public.search_master_products') is not null,
      '0058', to_regproc('public.request_account_deletion') is not null),
    'pg_cron', v_cron,
    'nightly_job', v_job,
    'last_reconciliation', (select jsonb_build_object('finished_at', finished_at, 'issues', issues,
                                                      'unexplained', unexplained)
                            from public.reconciliation_runs order by started_at desc limit 1),
    'imagekit_key', v_vault,
    'devices', (select count(*) from public.device_tokens),
    'last_bill_at', (select max(created_at) from public.invoices),
    'bills_today', (select count(*) from public.invoices
                    where created_at >= date_trunc('day', now() at time zone 'Asia/Kolkata')
                                        at time zone 'Asia/Kolkata'),
    'shops_active', (select count(*) from public.businesses where is_active),
    'trial_plan_set', exists (select 1 from public.plans where is_trial),
    'trial_days', (select trial_days from public.software_products where slug = 'dukania'),
    'payment_upi_set', (select payment_upi_id <> '' from public.platform_settings where id = 1),
    'support_whatsapp_set', (select support_whatsapp <> '' from public.platform_settings where id = 1),
    'master_products_pending', (select count(*) from public.master_products where status = 'pending'),
    'confirmed_checks', (select confirmed_checks from public.platform_settings where id = 1)
  );
end $$;

-- ============================================================
-- Grants
-- ============================================================
revoke execute on function public.profile_within_user_limit(uuid) from public, anon, authenticated;
revoke execute on function public.request_account_deletion(text) from public, anon;
grant execute on function public.request_account_deletion(text) to authenticated;
