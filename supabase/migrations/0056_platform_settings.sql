-- ============================================================
-- 0056_platform_settings.sql — the admin panel's Settings page
--
--   * admin_save_settings(): checked and logged. The UPI ID decides where
--     shops send their money, and the panel used to change it with a
--     direct, unlogged table update.
--   * SOFTRAXA's own details for payment receipts (name, address, phone,
--     email, GSTIN, a footer line) — receipts had only the word SOFTRAXA.
--   * The support WhatsApp number reaches the whole app through
--     get_my_context(). Only the renewal and plan screens used it; the
--     dashboard, Support and More screens used a number fixed in the app
--     build, so changing the number in Settings did not change them.
--
-- Run AFTER 0055.
-- ============================================================

-- ============================================================
-- A. SOFTRAXA's details for receipts
-- ============================================================
alter table public.platform_settings add column if not exists business_name text not null default 'SOFTRAXA';
alter table public.platform_settings add column if not exists business_address text not null default '';
alter table public.platform_settings add column if not exists business_phone text not null default '';
alter table public.platform_settings add column if not exists business_email text not null default '';
alter table public.platform_settings add column if not exists business_gstin text not null default '';
alter table public.platform_settings add column if not exists receipt_footer text not null default '';
alter table public.platform_settings add column if not exists updated_by uuid references public.profiles(id) on delete set null;

-- ============================================================
-- B. Saving settings (logged)
-- ============================================================
-- p: payment_upi_id, payment_payee_name, support_whatsapp, business_name,
-- business_address, business_phone, business_email, business_gstin,
-- receipt_footer. A 10-digit WhatsApp number gets India's 91 in front.
create or replace function public.admin_save_settings(p jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_old   public.platform_settings;
  v_new   public.platform_settings;
  v_upi   text := btrim(coalesce(p ->> 'payment_upi_id', ''));
  v_wa    text := regexp_replace(coalesce(p ->> 'support_whatsapp', ''), '[^0-9]', '', 'g');
  v_gstin text := upper(btrim(coalesce(p ->> 'business_gstin', '')));
  v_email text := lower(btrim(coalesce(p ->> 'business_email', '')));
begin
  perform public.assert_platform_admin();
  if v_upi <> '' and v_upi !~ '^[A-Za-z0-9._-]{2,255}@[A-Za-z][A-Za-z0-9]{1,63}$' then
    raise exception 'That doesn''t look like a UPI ID — it should be like softraxa@okaxis';
  end if;
  if length(v_wa) = 10 then v_wa := '91' || v_wa; end if;
  if v_wa <> '' and length(v_wa) not between 11 and 15 then
    raise exception 'The WhatsApp number should be 10 digits, or the country code and the number';
  end if;
  if v_gstin <> '' and v_gstin !~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][0-9A-Z]Z[0-9A-Z]$' then
    raise exception 'That doesn''t look like a GSTIN (15 characters, like 27ABCDE1234F1Z5)';
  end if;
  if v_email <> '' and v_email !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' then
    raise exception 'That doesn''t look like an email address';
  end if;
  if char_length(coalesce(p ->> 'receipt_footer', '')) > 200 then
    raise exception 'Keep the receipt footer under 200 characters';
  end if;

  select * into v_old from public.platform_settings where id = 1 for update;
  update public.platform_settings set
    payment_upi_id     = v_upi,
    payment_payee_name = coalesce(nullif(btrim(p ->> 'payment_payee_name'), ''), 'SOFTRAXA'),
    support_whatsapp   = v_wa,
    business_name      = coalesce(nullif(btrim(p ->> 'business_name'), ''), 'SOFTRAXA'),
    business_address   = btrim(coalesce(p ->> 'business_address', '')),
    business_phone     = btrim(coalesce(p ->> 'business_phone', '')),
    business_email     = v_email,
    business_gstin     = v_gstin,
    receipt_footer     = btrim(coalesce(p ->> 'receipt_footer', '')),
    updated_at         = now(),
    updated_by         = auth.uid()
  where id = 1
  returning * into v_new;

  perform public.admin_log(null, 'settings.updated', 'platform_settings', '1',
    jsonb_build_object(
      'before', to_jsonb(v_old) - 'confirmed_checks' - 'updated_at' - 'updated_by',
      'after',  to_jsonb(v_new) - 'confirmed_checks' - 'updated_at' - 'updated_by'));
end $$;

-- ============================================================
-- C. The support number reaches every screen of the app
-- ============================================================
-- 0055's session bootstrap plus 'support'.
create or replace function public.get_my_context()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
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
      '0056', to_regproc('public.admin_save_settings') is not null),
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
    'payment_upi_set', (select payment_upi_id <> '' from public.platform_settings where id = 1),
    'support_whatsapp_set', (select support_whatsapp <> '' from public.platform_settings where id = 1),
    'confirmed_checks', (select confirmed_checks from public.platform_settings where id = 1)
  );
end $$;

-- ============================================================
-- Grants
-- ============================================================
revoke execute on function public.admin_save_settings(jsonb) from public, anon;
grant execute on function public.admin_save_settings(jsonb) to authenticated, service_role;
