-- ============================================================
-- 0039_admin_provisioning.sql — launch release R0, batch 4
-- (PROJECT_ANALYSIS.md finding 10)
--
-- Client provisioning and suspension used to be a series of unchecked
-- writes from the admin API route; a failure part-way left half-created
-- businesses or reported the wrong status. Both are now single
-- transactional, admin-only functions.
--
-- Run AFTER 0038.
-- ============================================================

-- Creates everything a new client needs for an already-created auth user.
-- Any failure rolls the whole setup back (the API route then deletes the
-- auth user). Callable only by platform admins / the service role.
create or replace function public.admin_provision_business(
  p_user_id    uuid,
  p_email      text,
  p_owner_name text,
  p_business   jsonb,
  p_plan       uuid default null,
  p_software   uuid default null,
  p_expiry     date default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_business uuid;
  v_trial    integer := 14;
  v_expiry   date := p_expiry;
begin
  perform public.assert_platform_admin();

  if coalesce(trim(p_business ->> 'name'), '') = '' then
    raise exception 'Business name is required';
  end if;
  if not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'Login for % was not created', p_email;
  end if;
  if (select business_id from public.profiles where id = p_user_id) is not null then
    raise exception 'This login already belongs to a business';
  end if;
  if p_plan is not null and not exists (select 1 from public.plans where id = p_plan) then
    raise exception 'Plan not found';
  end if;

  if v_expiry is null then
    if p_software is not null then
      select coalesce(trial_days, 14) into v_trial from public.software_products where id = p_software;
    end if;
    v_expiry := current_date + coalesce(v_trial, 14);
  end if;

  insert into public.businesses
    (name, owner_name, business_type, phone, email, address, gst_number,
     invoice_prefix, tax_preference, setup_complete)
  values (
    trim(p_business ->> 'name'),
    coalesce(p_owner_name, ''),
    coalesce(nullif(p_business ->> 'type', '')::public.business_type, 'other'),
    coalesce(p_business ->> 'phone', ''),
    lower(trim(p_email)),
    coalesce(p_business ->> 'address', ''),
    upper(coalesce(p_business ->> 'gstNumber', '')),
    coalesce(nullif(p_business ->> 'invoicePrefix', ''), 'INV'),
    coalesce(nullif(p_business ->> 'taxPreference', '')::public.tax_preference, 'gst'),
    true)
  returning id into v_business;

  update public.profiles
     set business_id = v_business, role = 'owner',
         full_name = coalesce(nullif(p_owner_name, ''), full_name),
         email = lower(trim(p_email))
   where id = p_user_id;

  insert into public.feature_flags (business_id) values (v_business)
    on conflict (business_id) do nothing;

  insert into public.expense_categories (business_id, name)
  select v_business, unnest(array[
    'Rent', 'Salary', 'Electricity', 'Transport', 'Packaging', 'Repair', 'Miscellaneous']);

  insert into public.units (business_id, name, short_name, allow_decimal)
  values
    (v_business, 'Piece',  'pcs', false),
    (v_business, 'Kg',     'kg',  true),
    (v_business, 'Gram',   'g',   true),
    (v_business, 'Metre',  'm',   true),
    (v_business, 'Litre',  'L',   true),
    (v_business, 'Box',    'box', false),
    (v_business, 'Dozen',  'dz',  false),
    (v_business, 'Set',    'set', false);

  insert into public.subscriptions (business_id, plan_id, software_id, status, start_date, expiry_date)
  values (v_business, p_plan, p_software,
          (case when p_plan is null then 'trial' else 'active' end)::public.subscription_status,
          current_date, v_expiry);

  if p_plan is not null then
    perform public.apply_plan_features(v_business, p_plan);
  end if;

  perform public.log_audit('business.provisioned', 'business', v_business::text,
    jsonb_build_object('email', lower(trim(p_email)), 'plan', p_plan, 'expiry', v_expiry));
  return v_business;
end $$;

-- Suspend or restore a client atomically; returns the resulting state.
create or replace function public.admin_set_business_status(p_business uuid, p_suspend boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_sub    record;
  v_status public.subscription_status;
begin
  perform public.assert_platform_admin();

  update public.businesses set is_active = not p_suspend where id = p_business;
  if not found then raise exception 'Business not found'; end if;

  select * into v_sub from public.subscriptions
    where business_id = p_business order by created_at desc limit 1 for update;

  if v_sub.id is not null then
    v_status := case
      when p_suspend then 'suspended'
      when current_date > v_sub.expiry_date + v_sub.grace_days then 'expired'
      when v_sub.plan_id is null then 'trial'
      else 'active' end;
    update public.subscriptions set status = v_status where id = v_sub.id;
  end if;

  perform public.log_audit(
    case when p_suspend then 'business.suspended' else 'business.restored' end,
    'business', p_business::text, jsonb_build_object('subscription_status', v_status));

  return jsonb_build_object(
    'business_id', p_business,
    'is_active', not p_suspend,
    'status', coalesce(v_status::text, case when p_suspend then 'suspended' else 'active' end));
end $$;

-- ---------- push-alerts run ledger (finding 12) ----------
-- One row per day the push-alerts Edge Function broadcast; its unique key
-- makes repeated or replayed calls on the same day a no-op. Only the
-- service role (the function) touches it.
create table if not exists public.push_alert_runs (
  run_date   date primary key,
  started_at timestamptz not null default now()
);
alter table public.push_alert_runs enable row level security;
drop policy if exists "admin read push runs" on public.push_alert_runs;
create policy "admin read push runs" on public.push_alert_runs for select using (public.is_admin());

revoke execute on function public.admin_provision_business(uuid, text, text, jsonb, uuid, uuid, date) from public, anon;
revoke execute on function public.admin_set_business_status(uuid, boolean) from public, anon;
grant execute on function public.admin_provision_business(uuid, text, text, jsonb, uuid, uuid, date) to authenticated, service_role;
grant execute on function public.admin_set_business_status(uuid, boolean) to authenticated, service_role;
