-- ============================================================
-- 0053_admin_operations.sql — admin panel, phase 1
--
-- SOFTRAXA runs Dukania alone and takes subscription payments by hand
-- (UPI, cash, bank transfer; no payment gateway). This migration gives the
-- admin panel safe, logged, one-step operations:
--
--   * admin_renew_subscription(): record a payment AND extend the expiry
--     (from today or the current expiry, whichever is later), set the plan
--     and its features, mark the subscription active, number a receipt
--     and log it — one transaction, so money is never taken without the
--     shop being extended.
--   * admin_update_subscription() / admin_set_feature(): corrections,
--     each with a reason in the audit log (the panel used to write the
--     tables directly, unlogged and without error checks).
--   * Payment claims: a blocked (expired) shop sees SOFTRAXA's UPI details
--     in the app, pays, and sends "I've paid" with the UPI reference
--     (submit_renewal_claim). The admin verifies it in their UPI app and
--     renews from the claim, or rejects it with a reason.
--   * platform_settings: SOFTRAXA's UPI ID, payee name and support
--     WhatsApp, editable in the panel, shown to shops.
--   * get_admin_today(): everything that needs the admin today.
--   * get_admin_dashboard(): counts one subscription per shop (the latest)
--     — it used to count every subscription row ever created.
--   * get_system_health(): checks the setup the admin can't see from the
--     app (migrations, nightly job, ImageKit key, devices, activity).
--
-- Run AFTER 0052.
-- ============================================================

-- ============================================================
-- A. Settings
-- ============================================================
create table if not exists public.platform_settings (
  id                   integer primary key default 1 check (id = 1),
  payment_upi_id       text not null default '',
  payment_payee_name   text not null default 'SOFTRAXA',
  support_whatsapp     text not null default '',
  -- Setup steps the panel can't verify itself (e.g. Supabase email
  -- templates): the admin ticks them off. {key: "2026-09-27"}.
  confirmed_checks     jsonb not null default '{}'::jsonb,
  updated_at           timestamptz not null default now()
);
insert into public.platform_settings (id) values (1) on conflict (id) do nothing;

alter table public.platform_settings drop constraint if exists platform_settings_upi_check;
alter table public.platform_settings add constraint platform_settings_upi_check
  check (payment_upi_id = '' or payment_upi_id ~ '^[A-Za-z0-9._-]{2,255}@[A-Za-z][A-Za-z0-9]{1,63}$');

alter table public.platform_settings enable row level security;
drop policy if exists "admin all" on public.platform_settings;
create policy "admin all" on public.platform_settings for all
  using (public.is_admin()) with check (public.is_admin());

-- ============================================================
-- B. Payments: reference, period, plan, receipt number
-- ============================================================
create sequence if not exists public.subscription_receipt_seq;

alter table public.subscription_payments add column if not exists reference text not null default '';
alter table public.subscription_payments add column if not exists period_start date;
alter table public.subscription_payments add column if not exists period_end date;
alter table public.subscription_payments add column if not exists plan_id uuid
  references public.plans(id) on delete set null;
alter table public.subscription_payments add column if not exists receipt_no text;
create unique index if not exists uq_subscription_payments_receipt
  on public.subscription_payments(receipt_no) where receipt_no is not null;

-- ============================================================
-- C. Payment claims from shops
-- ============================================================
create table if not exists public.renewal_claims (
  id           uuid primary key default gen_random_uuid(),
  business_id  uuid not null references public.businesses(id) on delete cascade,
  amount       numeric(12,2) not null check (amount > 0),
  reference    text not null default '',
  note         text not null default '',
  status       text not null default 'pending' check (status in ('pending', 'verified', 'rejected')),
  payment_id   uuid references public.subscription_payments(id) on delete set null,
  decision_note text not null default '',
  created_by   uuid references public.profiles(id),
  created_at   timestamptz not null default now(),
  decided_at   timestamptz
);
create index if not exists idx_renewal_claims_status on public.renewal_claims(status, created_at);

alter table public.renewal_claims enable row level security;
drop policy if exists "own read" on public.renewal_claims;
create policy "own read" on public.renewal_claims for select
  using (business_id = public.current_business_id() or public.is_admin());

-- The shop owner (even with an expired or suspended subscription) tells
-- SOFTRAXA they have paid. At most 3 claims can wait at once.
create or replace function public.submit_renewal_claim(
  p_amount numeric, p_reference text, p_note text default '')
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_id       uuid;
begin
  if v_business is null then raise exception 'No shop selected'; end if;
  if not public.has_permission('owner') then
    raise exception 'Only the owner can report a subscription payment' using errcode = '42501';
  end if;
  if coalesce(p_amount, 0) <= 0 then raise exception 'Enter the amount you paid'; end if;
  if btrim(coalesce(p_reference, '')) = '' then
    raise exception 'Enter the UPI reference (UTR) number from your payment app';
  end if;
  if (select count(*) from public.renewal_claims
      where business_id = v_business and status = 'pending') >= 3 then
    raise exception 'Your earlier payments are still being checked — SOFTRAXA will confirm soon';
  end if;
  insert into public.renewal_claims (business_id, amount, reference, note, created_by)
    values (v_business, p_amount, btrim(p_reference), coalesce(p_note, ''), auth.uid())
    returning id into v_id;
  insert into public.audit_logs (business_id, user_id, action, entity, entity_id, details)
    values (v_business, auth.uid(), 'subscription.payment_claimed', 'renewal_claim', v_id::text,
            jsonb_build_object('amount', p_amount, 'reference', btrim(p_reference)));
  return v_id;
end $$;

-- What a shop needs to pay: SOFTRAXA's UPI details, its plan and prices,
-- its expiry and any claim still being checked. Works while blocked.
create or replace function public.get_payment_info()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'upi_id', s.payment_upi_id,
    'payee_name', s.payment_payee_name,
    'support_whatsapp', s.support_whatsapp,
    'plan', (select jsonb_build_object('name', p.name, 'monthly_price', p.monthly_price,
                                       'yearly_price', p.yearly_price)
             from public.subscriptions sub join public.plans p on p.id = sub.plan_id
             where sub.business_id = public.current_business_id()
             order by sub.created_at desc limit 1),
    'expiry_date', (select sub.expiry_date from public.subscriptions sub
                    where sub.business_id = public.current_business_id()
                    order by sub.created_at desc limit 1),
    'pending_claim', (select jsonb_build_object('amount', c.amount, 'reference', c.reference,
                                                'created_at', c.created_at)
                      from public.renewal_claims c
                      where c.business_id = public.current_business_id() and c.status = 'pending'
                      order by c.created_at desc limit 1),
    'last_rejected', (select jsonb_build_object('reference', c.reference, 'reason', c.decision_note,
                                                'decided_at', c.decided_at)
                      from public.renewal_claims c
                      where c.business_id = public.current_business_id() and c.status = 'rejected'
                        and c.decided_at > now() - interval '7 days'
                      order by c.decided_at desc limit 1))
  from public.platform_settings s where s.id = 1
$$;

-- ============================================================
-- D. Admin operations (logged)
-- ============================================================
create or replace function public.admin_log(
  p_business uuid, p_action text, p_entity text, p_entity_id text, p_details jsonb)
returns void language sql security definer set search_path = public as $$
  insert into public.audit_logs (business_id, user_id, action, entity, entity_id, details)
  values (p_business, auth.uid(), p_action, p_entity, p_entity_id, p_details);
$$;

-- Record a payment and extend in one step. p_period: 'month', 'year' or
-- 'custom' (then p_until). p_amount 0 = free extension (no payment row).
create or replace function public.admin_renew_subscription(
  p_business uuid, p_plan uuid, p_period text, p_until date, p_amount numeric,
  p_mode public.payment_mode default 'upi', p_reference text default '',
  p_payment_date date default null, p_note text default '', p_claim uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_today    date := public.ist_date(now());
  v_biz      record;
  v_sub      record;
  v_base     date;
  v_expiry   date;
  v_plan     uuid;
  v_pay      uuid;
  v_receipt  text;
  v_claim_ref text;
  v_old_plan uuid;
  v_old_expiry date;
  v_claim_status text;
begin
  perform public.assert_platform_admin();
  select * into v_biz from public.businesses where id = p_business;
  if v_biz.id is null then raise exception 'Client not found'; end if;
  if coalesce(p_amount, -1) < 0 then raise exception 'Enter the amount received (0 for a free extension)'; end if;
  if p_amount > 0 and p_mode = 'credit' then raise exception 'Choose how the money was received'; end if;

  if p_claim is not null then
    select reference, status into v_claim_ref, v_claim_status from public.renewal_claims
      where id = p_claim and business_id = p_business for update;
    if v_claim_status is null then raise exception 'Payment claim not found'; end if;
    if v_claim_status <> 'pending' then raise exception 'This claim was already handled'; end if;
  end if;

  select * into v_sub from public.subscriptions where business_id = p_business
    order by created_at desc limit 1 for update;
  v_old_plan := v_sub.plan_id;
  v_old_expiry := v_sub.expiry_date;
  v_plan := coalesce(p_plan, v_old_plan);
  v_base := greatest(coalesce(v_sub.expiry_date, v_today), v_today);
  v_expiry := case p_period
    when 'month' then (v_base + interval '1 month')::date
    when 'year' then (v_base + interval '1 year')::date
    when 'custom' then p_until
  end;
  if v_expiry is null then raise exception 'Choose 1 month, 1 year or a date'; end if;
  if v_expiry <= v_today then raise exception 'The new expiry must be after today'; end if;

  if v_sub.id is null then
    insert into public.subscriptions (business_id, plan_id, status, start_date, expiry_date)
      values (p_business, v_plan, 'active', v_today, v_expiry)
      returning * into v_sub;
  else
    update public.subscriptions
       set plan_id = v_plan, status = 'active', expiry_date = v_expiry
     where id = v_sub.id;
  end if;
  if v_plan is not null and v_plan is distinct from v_old_plan then
    perform public.apply_plan_features(p_business, v_plan);
  end if;

  if p_amount > 0 then
    v_receipt := 'SR-' || to_char(v_today, 'YYMM') || '-'
                 || lpad(nextval('public.subscription_receipt_seq')::text, 4, '0');
    insert into public.subscription_payments
      (business_id, subscription_id, amount, payment_date, payment_mode, note, recorded_by,
       reference, period_start, period_end, plan_id, receipt_no)
    values
      (p_business, v_sub.id, p_amount, coalesce(p_payment_date, v_today), p_mode,
       coalesce(p_note, ''), auth.uid(),
       btrim(coalesce(nullif(btrim(p_reference), ''), v_claim_ref, '')),
       v_base, v_expiry, v_plan, v_receipt)
    returning id into v_pay;
  end if;

  if p_claim is not null then
    update public.renewal_claims set status = 'verified', payment_id = v_pay, decided_at = now()
      where id = p_claim;
  end if;

  perform public.admin_log(p_business, 'subscription.renewed', 'subscription', v_sub.id::text,
    jsonb_build_object('from', v_old_expiry, 'to', v_expiry, 'amount', p_amount,
                       'mode', p_mode, 'reference', p_reference, 'plan', v_plan,
                       'receipt', v_receipt, 'claim', p_claim));

  return jsonb_build_object(
    'expiry_date', v_expiry, 'previous_expiry', v_old_expiry, 'payment_id', v_pay,
    'receipt_no', v_receipt, 'still_suspended', not v_biz.is_active,
    'plan_name', (select name from public.plans where id = v_plan));
end $$;

-- Reject a payment claim (e.g. no such UPI payment), with the reason the
-- shop will see.
create or replace function public.admin_reject_renewal_claim(p_claim uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v record;
begin
  perform public.assert_platform_admin();
  if btrim(coalesce(p_reason, '')) = '' then raise exception 'Give a reason the shop will see'; end if;
  update public.renewal_claims
     set status = 'rejected', decision_note = btrim(p_reason), decided_at = now()
   where id = p_claim and status = 'pending'
   returning * into v;
  if v.id is null then raise exception 'Claim not found or already handled'; end if;
  perform public.admin_log(v.business_id, 'subscription.claim_rejected', 'renewal_claim', v.id::text,
    jsonb_build_object('reason', p_reason, 'amount', v.amount, 'reference', v.reference));
end $$;

-- Corrections to a subscription (not renewals), with a reason.
create or replace function public.admin_update_subscription(
  p_business uuid, p_plan uuid, p_status text, p_expiry date, p_grace integer, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_sub record;
  v_before jsonb;
begin
  perform public.assert_platform_admin();
  if btrim(coalesce(p_reason, '')) = '' then raise exception 'Give a reason for the change'; end if;
  if p_status not in ('trial', 'active', 'expired') then
    raise exception 'Use Suspend / Activate for suspensions';
  end if;
  if p_expiry is null then raise exception 'Choose an expiry date'; end if;
  if coalesce(p_grace, 0) < 0 or coalesce(p_grace, 0) > 90 then raise exception 'Grace days: 0–90'; end if;

  select * into v_sub from public.subscriptions where business_id = p_business
    order by created_at desc limit 1 for update;
  v_before := jsonb_build_object('plan', v_sub.plan_id, 'status', v_sub.status,
                                 'expiry', v_sub.expiry_date, 'grace', v_sub.grace_days);
  if v_sub.id is null then
    insert into public.subscriptions (business_id, plan_id, status, expiry_date, grace_days)
      values (p_business, p_plan, p_status::public.subscription_status, p_expiry, coalesce(p_grace, 0))
      returning * into v_sub;
  else
    update public.subscriptions
       set plan_id = p_plan, status = p_status::public.subscription_status,
           expiry_date = p_expiry, grace_days = coalesce(p_grace, 0)
     where id = v_sub.id;
  end if;
  if p_plan is not null and p_plan::text is distinct from (v_before ->> 'plan') then
    perform public.apply_plan_features(p_business, p_plan);
  end if;
  perform public.admin_log(p_business, 'subscription.updated', 'subscription', v_sub.id::text,
    jsonb_build_object('reason', p_reason,
      'before', v_before,
      'after', jsonb_build_object('plan', p_plan, 'status', p_status, 'expiry', p_expiry,
                                  'grace', p_grace)));
end $$;

-- Turn one plan feature on or off for one shop, logged.
create or replace function public.admin_set_feature(p_business uuid, p_key text, p_on boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_platform_admin();
  if not (p_key = any(public.app_feature_keys())) then raise exception 'Unknown feature %', p_key; end if;
  insert into public.feature_flags (business_id) values (p_business) on conflict (business_id) do nothing;
  execute format('update public.feature_flags set %I = $1, updated_at = now() where business_id = $2', p_key)
    using p_on, p_business;
  perform public.admin_log(p_business, 'feature.' || case when p_on then 'enabled' else 'disabled' end,
    'feature_flags', p_key, jsonb_build_object('feature', p_key));
end $$;

-- Business status changes are logged too (0039's function logs to the
-- admin's own — empty — business; add the shop's own trail).
create or replace function public.admin_log_status_change()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.is_active is distinct from old.is_active and public.is_admin() then
    perform public.admin_log(new.id, case when new.is_active then 'business.activated'
                                          else 'business.suspended' end,
                             'business', new.id::text, '{}'::jsonb);
  end if;
  return new;
end $$;
drop trigger if exists trg_businesses_admin_log on public.businesses;
create trigger trg_businesses_admin_log after update of is_active on public.businesses
  for each row execute function public.admin_log_status_change();

-- ============================================================
-- E. Today, dashboard and health
-- ============================================================
-- The latest subscription of every shop.
create or replace view public.latest_subscriptions
with (security_invoker = true) as
  select distinct on (s.business_id) s.*
  from public.subscriptions s
  order by s.business_id, s.created_at desc;

create or replace function public.get_admin_today()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_today date := public.ist_date(now());
begin
  perform public.assert_platform_admin();
  return jsonb_build_object(
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
    -- Support tickets waiting more than a day.
    'tickets', coalesce((select jsonb_agg(t order by t.created_at) from (
        select tk.id, tk.business_id, b.name, tk.subject, tk.status, tk.created_at
        from public.support_tickets tk join public.businesses b on b.id = tk.business_id
        where tk.status <> 'resolved' and tk.created_at < now() - interval '24 hours') t), '[]'),
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
        where l.status in ('new', 'contacted', 'demo') and l.follow_up_date <= v_today) t), '[]')
  );
end $$;

-- 0009's dashboard, counting each shop once (its latest subscription).
create or replace function public.get_admin_dashboard()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_today date := public.ist_date(now());
begin
  perform public.assert_platform_admin();
  return jsonb_build_object(
    'total_clients',   (select count(*) from public.businesses),
    'active_clients',  (select count(*) from public.latest_subscriptions ls
                        join public.businesses b on b.id = ls.business_id
                        where b.is_active and ls.status = 'active'
                          and ls.expiry_date + ls.grace_days >= v_today),
    'trial_clients',   (select count(*) from public.latest_subscriptions ls
                        join public.businesses b on b.id = ls.business_id
                        where b.is_active and ls.status = 'trial'
                          and ls.expiry_date + ls.grace_days >= v_today),
    'expired_clients', (select count(*) from public.latest_subscriptions ls
                        join public.businesses b on b.id = ls.business_id
                        where b.is_active and ls.status <> 'suspended'
                          and (ls.status = 'expired' or ls.expiry_date + ls.grace_days < v_today)),
    'suspended_clients', (select count(*) from public.businesses b
                          where not b.is_active
                             or exists (select 1 from public.latest_subscriptions ls
                                        where ls.business_id = b.id and ls.status = 'suspended')),
    'monthly_revenue', coalesce((select sum(amount) from public.subscription_payments
                        where payment_date >= date_trunc('month', v_today)), 0),
    'new_clients_this_month', (select count(*) from public.businesses
                        where created_at >= date_trunc('month', now())),
    'plan_wise', coalesce((select jsonb_agg(row_to_json(p)) from (
        select coalesce(pl.name, 'No plan') as plan, count(*) as clients
        from public.latest_subscriptions ls left join public.plans pl on pl.id = ls.plan_id
        group by 1 order by 2 desc) p), '[]'::jsonb),
    'open_tickets', (select count(*) from public.support_tickets where status <> 'resolved')
  );
end $$;

-- Setup checks inside the database. (The admin panel adds the checks
-- only its server can make: email sending, website, Edge Functions.)
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
      '0054', to_regproc('public.admin_reply_ticket') is not null),
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
    'payment_upi_set', (select payment_upi_id <> '' from public.platform_settings where id = 1),
    'confirmed_checks', (select confirmed_checks from public.platform_settings where id = 1)
  );
end $$;

-- ============================================================
-- Grants
-- ============================================================
revoke execute on function public.admin_log(uuid, text, text, text, jsonb) from public, anon, authenticated;
revoke execute on function public.submit_renewal_claim(numeric, text, text) from public, anon;
revoke execute on function public.get_payment_info() from public, anon;
revoke execute on function public.admin_renew_subscription(uuid, uuid, text, date, numeric, public.payment_mode, text, date, text, uuid) from public, anon;
revoke execute on function public.admin_reject_renewal_claim(uuid, text) from public, anon;
revoke execute on function public.admin_update_subscription(uuid, uuid, text, date, integer, text) from public, anon;
revoke execute on function public.admin_set_feature(uuid, text, boolean) from public, anon;
revoke execute on function public.get_admin_today() from public, anon;
revoke execute on function public.get_system_health() from public, anon;
grant execute on function public.submit_renewal_claim(numeric, text, text) to authenticated;
grant execute on function public.get_payment_info() to authenticated;
grant execute on function public.admin_renew_subscription(uuid, uuid, text, date, numeric, public.payment_mode, text, date, text, uuid) to authenticated;
grant execute on function public.admin_reject_renewal_claim(uuid, text) to authenticated;
grant execute on function public.admin_update_subscription(uuid, uuid, text, date, integer, text) to authenticated;
grant execute on function public.admin_set_feature(uuid, text, boolean) to authenticated;
grant execute on function public.get_admin_today() to authenticated;
grant execute on function public.get_system_health() to authenticated;
