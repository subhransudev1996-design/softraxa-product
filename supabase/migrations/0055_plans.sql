-- ============================================================
-- 0055_plans.sql — plans, managed in the admin panel, shown in the app
-- without prices
--
-- SOFTRAXA agrees the price with each shop (WhatsApp, phone); the app
-- shows what a plan includes, never what it costs.
--
--   * Plans get what the app shows: a one-line description, highlight
--     lines, a display order and a "recommended" mark. `notes` stays
--     private to SOFTRAXA (the app used to show it).
--   * Prices are private: shops can no longer read the plans table. The
--     app gets plans from get_plans_for_app() — name, details, limits,
--     features, the shop's own usage — and get_my_context() /
--     get_payment_info() no longer carry prices.
--   * One plan is marked as the trial plan (it was found by the name
--     'Free Trial', so renaming it broke new signups). New shops get it
--     for the product's trial length.
--   * request_plan_change(): the owner asks for a plan from the app. It
--     arrives as a support request; it closes itself when SOFTRAXA moves
--     the shop to that plan.
--   * admin_save_plan() / admin_set_plan_active() / admin_delete_plan():
--     checked and logged (the panel used to write the table directly,
--     without error checks).
--   * Fixes: a plan with no features ticked now really means "everything
--     on" (flags switched off by an earlier plan used to stay off), and
--     editing a plan only updates shops whose CURRENT subscription is on
--     it (it used to touch shops that had left the plan).
--
-- Run AFTER 0054.
-- ============================================================

-- ============================================================
-- A. What the app shows about a plan
-- ============================================================
alter table public.plans add column if not exists description text not null default '';
alter table public.plans add column if not exists highlights jsonb not null default '[]'::jsonb;
alter table public.plans add column if not exists sort_order integer not null default 0;
alter table public.plans add column if not exists is_trial boolean not null default false;
alter table public.plans add column if not exists is_recommended boolean not null default false;

alter table public.plans drop constraint if exists plans_highlights_check;
alter table public.plans add constraint plans_highlights_check
  check (jsonb_typeof(highlights) = 'array');
alter table public.plans drop constraint if exists plans_features_check;
alter table public.plans add constraint plans_features_check
  check (jsonb_typeof(included_features) = 'array');

-- The seeded trial plan becomes THE trial plan.
update public.plans set is_trial = true
 where id = (select id from public.plans where name = 'Free Trial' order by created_at limit 1)
   and not exists (select 1 from public.plans where is_trial);

-- One trial plan per software product.
create unique index if not exists uq_plans_trial on public.plans
  ((coalesce(software_id, '00000000-0000-0000-0000-000000000000'::uuid))) where is_trial;

-- A shop's request for a plan (request_plan_change).
alter table public.support_tickets add column if not exists requested_plan_id uuid
  references public.plans(id) on delete set null;

-- ============================================================
-- B. Prices are private
-- ============================================================
-- Shops read plans only through the functions below. "admin manage plans"
-- (0010) still lets SOFTRAXA read and write everything.
drop policy if exists "plans read" on public.plans;

-- A plan as a shop may see it: no prices, no private notes. Every feature
-- of the product is listed, marked included or not (nothing ticked on the
-- plan = everything included).
create or replace function public.plan_public(p public.plans)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', p.id,
    'name', p.name,
    'description', p.description,
    'highlights', p.highlights,
    'is_trial', p.is_trial,
    'is_recommended', p.is_recommended,
    'is_custom', p.is_custom,
    'user_limit', p.user_limit,
    'product_limit', p.product_limit,
    'invoice_limit', p.invoice_limit,
    'features', coalesce((
      select jsonb_agg(jsonb_build_object(
               'key', x.f ->> 'key',
               'label', x.f ->> 'label',
               'included', jsonb_array_length(p.included_features) = 0
                           or p.included_features ? (x.f ->> 'key'))
             order by x.ord)
      from public.software_products sp,
           jsonb_array_elements(sp.features) with ordinality as x(f, ord)
      where sp.id = coalesce(p.software_id,
                             (select id from public.software_products where slug = 'dukania'))
    ), '[]'::jsonb));
$$;

-- 0037's session bootstrap, with the plan as the shop may see it.
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
    'subscription', (
      select to_jsonb(s) || jsonb_build_object(
        'plan', case when pl.id is null then null else public.plan_public(pl) end,
        'user_limit', v_limit, 'staff_count', v_count)
      from public.subscriptions s left join public.plans pl on pl.id = s.plan_id
      where s.business_id = v_business
      order by s.created_at desc limit 1));
end $$;

-- 0053's payment details, without prices: the shop pays the amount
-- SOFTRAXA told it and reports what it paid.
create or replace function public.get_payment_info()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'upi_id', s.payment_upi_id,
    'payee_name', s.payment_payee_name,
    'support_whatsapp', s.support_whatsapp,
    'plan', (select jsonb_build_object('name', p.name)
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
-- C. Plans in the app
-- ============================================================
-- The shop's plan with its usage, and the plans it can ask for. Custom
-- plans (made for one client), the trial plan and hidden plans are not
-- offered. Counts follow the same rules as the limits themselves.
create or replace function public.get_plans_for_app()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_sub      public.subscriptions;
  v_plan     public.plans;
  v_software uuid;
begin
  if v_business is null then raise exception 'No shop selected'; end if;
  select * into v_sub from public.subscriptions
    where business_id = v_business order by created_at desc limit 1;
  select * into v_plan from public.plans where id = v_sub.plan_id;
  v_software := coalesce(v_plan.software_id, v_sub.software_id,
                         (select id from public.software_products where slug = 'dukania'));

  return jsonb_build_object(
    'current', jsonb_build_object(
      'plan', case when v_plan.id is null then null else public.plan_public(v_plan) end,
      'status', v_sub.status,
      'expiry_date', v_sub.expiry_date,
      'usage', jsonb_build_object(
        'users', (select count(*) from public.profiles where business_id = v_business),
        'user_limit', public.business_user_limit(v_business),
        'products', (select count(*) from public.products where business_id = v_business),
        'product_limit', v_plan.product_limit,
        'bills_this_month', (select count(*) from public.invoices
                             where business_id = v_business and invoice_type <> 'estimate'
                               and invoice_date >= date_trunc('month', now())),
        'invoice_limit', v_plan.invoice_limit)),
    'plans', coalesce((
      select jsonb_agg(public.plan_public(p) order by p.sort_order, p.name)
      from public.plans p
      where p.is_active and not p.is_trial and not p.is_custom
        and p.id is distinct from v_plan.id
        and (p.software_id is null or p.software_id = v_software)), '[]'::jsonb),
    'requested_plan_id', (
      select t.requested_plan_id from public.support_tickets t
      where t.business_id = v_business and t.requested_plan_id is not null
        and t.status <> 'resolved'
      order by t.created_at desc limit 1),
    'support_whatsapp', (select support_whatsapp from public.platform_settings where id = 1));
end $$;

-- The owner asks for a plan. It becomes a support request, so it shows
-- under "needs reply" in the admin panel. Works while expired. Asking
-- twice for the same plan returns the request already waiting.
create or replace function public.request_plan_change(p_plan uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_plan     public.plans;
  v_current  uuid;
  v_current_name text;
  v_id       uuid;
begin
  if v_business is null then raise exception 'No shop selected'; end if;
  if not public.has_permission('owner') then
    raise exception 'Only the owner can ask for a plan change' using errcode = '42501';
  end if;
  select * into v_plan from public.plans where id = p_plan and is_active and not is_trial;
  if v_plan.id is null then raise exception 'This plan is not available'; end if;

  select s.plan_id, pl.name into v_current, v_current_name
    from public.subscriptions s left join public.plans pl on pl.id = s.plan_id
    where s.business_id = v_business order by s.created_at desc limit 1;
  if v_current = p_plan then raise exception 'Your shop is already on this plan'; end if;

  select id into v_id from public.support_tickets
    where business_id = v_business and requested_plan_id = p_plan and status <> 'resolved'
    order by created_at desc limit 1;
  if v_id is not null then return v_id; end if;

  insert into public.support_tickets (business_id, subject, message, created_by, requested_plan_id)
    values (v_business, 'Plan request: ' || v_plan.name,
            'Please move my shop'
              || case when v_current_name is null then '' else ' from ' || v_current_name end
              || ' to the ' || v_plan.name || ' plan.',
            auth.uid(), p_plan)
    returning id into v_id;
  insert into public.audit_logs (business_id, user_id, action, entity, entity_id, details)
    values (v_business, auth.uid(), 'subscription.plan_requested', 'plan', p_plan::text,
            jsonb_build_object('plan', v_plan.name, 'ticket', v_id));
  return v_id;
end $$;

-- When SOFTRAXA moves a shop to the plan it asked for, the request
-- answers and closes itself.
create or replace function public.resolve_plan_requests()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  t record;
begin
  if new.plan_id is null then return new; end if;
  for t in
    select id, business_id from public.support_tickets
    where business_id = new.business_id and requested_plan_id = new.plan_id
      and status <> 'resolved'
    for update
  loop
    insert into public.support_messages (ticket_id, business_id, from_softraxa, body, created_by)
      values (t.id, t.business_id, true,
              'Your shop is now on the '
                || (select name from public.plans where id = new.plan_id) || ' plan.',
              auth.uid());
    update public.support_tickets
       set last_reply_at = clock_timestamp(), status = 'resolved', reply_notified_at = null
     where id = t.id;
  end loop;
  return new;
end $$;
drop trigger if exists trg_subscriptions_plan_requests on public.subscriptions;
create trigger trg_subscriptions_plan_requests
  after insert or update of plan_id on public.subscriptions
  for each row execute function public.resolve_plan_requests();

-- ============================================================
-- D. Plan features on a shop
-- ============================================================
-- Write a plan's features into a shop's feature_flags: ticked = on, the
-- rest off; a plan with nothing ticked = everything on. Internal (no
-- caller check): used by signup and by apply_plan_features.
create or replace function public.set_plan_features(p_business uuid, p_plan uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_included text[];
  v_key text;
begin
  insert into public.feature_flags (business_id) values (p_business)
    on conflict (business_id) do nothing;
  if p_plan is null then return; end if;
  select coalesce(array(select jsonb_array_elements_text(included_features)), '{}')
    into v_included from public.plans where id = p_plan;
  if not found then return; end if;
  foreach v_key in array public.app_feature_keys() loop
    execute format(
      'update public.feature_flags set %I = $1, updated_at = now() where business_id = $2', v_key)
      using (array_length(v_included, 1) is null or v_key = any(v_included)), p_business;
  end loop;
end $$;

create or replace function public.apply_plan_features(p_business uuid, p_plan uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_platform_admin();
  perform public.set_plan_features(p_business, p_plan);
end $$;

-- Re-apply a plan to the shops that are on it NOW.
create or replace function public.resync_plan_features(p_plan uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  r record;
begin
  perform public.assert_platform_admin();
  for r in
    select business_id from (
      select distinct on (s.business_id) s.business_id, s.plan_id
      from public.subscriptions s
      order by s.business_id, s.created_at desc) latest
    where plan_id = p_plan
  loop
    perform public.set_plan_features(r.business_id, p_plan);
  end loop;
end $$;

-- ============================================================
-- E. Signup: the trial plan by its mark, not by its name
-- ============================================================
-- 0008's create_business with the trial plan found by is_trial, the
-- product's trial length, and the trial plan's features applied.
create or replace function public.create_business(payload jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_business uuid;
  v_trial_plan uuid;
  v_software uuid;
  v_days integer;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if (select business_id from public.profiles where id = auth.uid()) is not null then
    raise exception 'Profile already has a business';
  end if;

  insert into public.businesses
    (name, owner_name, business_type, phone, email, address, gst_number,
     invoice_prefix, tax_preference, logo_url, setup_complete)
  values (
    payload ->> 'name',
    coalesce(payload ->> 'owner_name', ''),
    coalesce((payload ->> 'business_type')::public.business_type, 'other'),
    coalesce(payload ->> 'phone', ''),
    coalesce(payload ->> 'email', ''),
    coalesce(payload ->> 'address', ''),
    coalesce(payload ->> 'gst_number', ''),
    coalesce(nullif(payload ->> 'invoice_prefix', ''), 'INV'),
    coalesce((payload ->> 'tax_preference')::public.tax_preference, 'gst'),
    payload ->> 'logo_url',
    true
  ) returning id into v_business;

  update public.profiles set business_id = v_business,
    full_name = coalesce(nullif(payload ->> 'owner_name', ''), full_name)
    where id = auth.uid();

  insert into public.feature_flags (business_id) values (v_business);

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

  select id, trial_days into v_software, v_days
    from public.software_products where slug = 'dukania';
  select id into v_trial_plan from public.plans
    where is_trial and (software_id is null or software_id = v_software)
    order by (software_id is null) limit 1;
  insert into public.subscriptions (business_id, plan_id, software_id, status, start_date, expiry_date)
  values (v_business, v_trial_plan, v_software, 'trial', current_date,
          current_date + coalesce(v_days, 14));
  perform public.set_plan_features(v_business, v_trial_plan);

  perform public.log_audit('business.created', 'business', v_business::text, '{}'::jsonb);
  return v_business;
end $$;

-- ============================================================
-- F. Managing plans (admin panel, logged)
-- ============================================================
-- Create (p_id null) or change a plan. p: name, description, highlights
-- [text], software_id, monthly_price, yearly_price, user_limit,
-- product_limit, invoice_limit (null = unlimited), included_features
-- [key], sort_order, is_custom, is_trial, is_recommended, notes.
-- Changed features reach the shops on the plan straight away.
create or replace function public.admin_save_plan(p_id uuid, p jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_old      public.plans;
  v_new      public.plans;
  v_name     text := btrim(coalesce(p ->> 'name', ''));
  v_software uuid := coalesce(nullif(p ->> 'software_id', '')::uuid,
                              (select id from public.software_products where slug = 'dukania'));
  v_monthly  numeric := coalesce((p ->> 'monthly_price')::numeric, 0);
  v_yearly   numeric := coalesce((p ->> 'yearly_price')::numeric, 0);
  v_users    integer := (p ->> 'user_limit')::integer;
  v_products integer := (p ->> 'product_limit')::integer;
  v_bills    integer := (p ->> 'invoice_limit')::integer;
  v_features jsonb := coalesce(p -> 'included_features', '[]'::jsonb);
  v_lines    jsonb := coalesce(p -> 'highlights', '[]'::jsonb);
  v_trial    boolean := coalesce((p ->> 'is_trial')::boolean, false);
  v_unknown  text;
begin
  perform public.assert_platform_admin();
  if v_name = '' then raise exception 'Give the plan a name'; end if;
  if char_length(v_name) > 40 then raise exception 'Keep the plan name under 40 characters'; end if;
  if exists (select 1 from public.plans
             where lower(name) = lower(v_name) and id is distinct from p_id
               and software_id is not distinct from v_software) then
    raise exception 'Another plan is already called %', v_name;
  end if;
  if v_monthly < 0 or v_yearly < 0 then raise exception 'A price can''t be negative'; end if;
  if v_users < 1 or v_products < 1 or v_bills < 1 then
    raise exception 'A limit must be 1 or more — leave it empty for unlimited';
  end if;
  if jsonb_typeof(v_features) <> 'array' or jsonb_typeof(v_lines) <> 'array' then
    raise exception 'Features and highlights must be lists';
  end if;

  select string_agg(k, ', ') into v_unknown
    from jsonb_array_elements_text(v_features) k
    where not exists (
      select 1 from public.software_products sp, jsonb_array_elements(sp.features) f
      where sp.id = v_software and f ->> 'key' = k);
  if v_unknown is not null then raise exception 'Unknown feature: %', v_unknown; end if;

  select coalesce(jsonb_agg(btrim(x.h) order by x.ord), '[]'::jsonb) into v_lines
    from jsonb_array_elements_text(v_lines) with ordinality as x(h, ord)
    where btrim(x.h) <> '';
  if jsonb_array_length(v_lines) > 8 then raise exception 'At most 8 highlight lines'; end if;
  if exists (select 1 from jsonb_array_elements_text(v_lines) h where char_length(h) > 80) then
    raise exception 'Keep each highlight line under 80 characters';
  end if;

  -- Only one trial plan: marking this one moves the mark.
  if v_trial then
    update public.plans set is_trial = false
     where is_trial and id is distinct from p_id and software_id is not distinct from v_software;
  end if;

  if p_id is null then
    insert into public.plans
      (name, description, highlights, software_id, monthly_price, yearly_price,
       user_limit, product_limit, invoice_limit, included_features, sort_order,
       is_custom, is_trial, is_recommended, notes)
    values
      (v_name, btrim(coalesce(p ->> 'description', '')), v_lines, v_software, v_monthly, v_yearly,
       v_users, v_products, v_bills, v_features, coalesce((p ->> 'sort_order')::integer, 0),
       coalesce((p ->> 'is_custom')::boolean, false), v_trial,
       coalesce((p ->> 'is_recommended')::boolean, false), coalesce(p ->> 'notes', ''))
    returning * into v_new;
  else
    select * into v_old from public.plans where id = p_id for update;
    if v_old.id is null then raise exception 'Plan not found'; end if;
    update public.plans set
      name = v_name,
      description = btrim(coalesce(p ->> 'description', '')),
      highlights = v_lines,
      software_id = v_software,
      monthly_price = v_monthly,
      yearly_price = v_yearly,
      user_limit = v_users,
      product_limit = v_products,
      invoice_limit = v_bills,
      included_features = v_features,
      sort_order = coalesce((p ->> 'sort_order')::integer, 0),
      is_custom = coalesce((p ->> 'is_custom')::boolean, false),
      is_trial = v_trial,
      is_recommended = coalesce((p ->> 'is_recommended')::boolean, false),
      notes = coalesce(p ->> 'notes', '')
    where id = p_id
    returning * into v_new;
    if v_old.included_features is distinct from v_new.included_features then
      perform public.resync_plan_features(p_id);
    end if;
  end if;

  perform public.admin_log(null, case when p_id is null then 'plan.created' else 'plan.updated' end,
    'plan', v_new.id::text,
    jsonb_build_object('name', v_new.name,
                       'before', case when p_id is null then null else to_jsonb(v_old) end,
                       'after', to_jsonb(v_new)));
  return v_new.id;
end $$;

-- Hide a plan (no longer offered in the app or for new clients; shops on
-- it keep it) or show it again.
create or replace function public.admin_set_plan_active(p_id uuid, p_active boolean)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_name text;
begin
  perform public.assert_platform_admin();
  update public.plans set is_active = p_active where id = p_id returning name into v_name;
  if v_name is null then raise exception 'Plan not found'; end if;
  perform public.admin_log(null, case when p_active then 'plan.shown' else 'plan.hidden' end,
    'plan', p_id::text, jsonb_build_object('name', v_name));
end $$;

-- Delete a plan nobody has ever been on. Anything else is hidden instead,
-- so old subscriptions and receipts keep their plan name.
create or replace function public.admin_delete_plan(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v public.plans;
begin
  perform public.assert_platform_admin();
  select * into v from public.plans where id = p_id for update;
  if v.id is null then raise exception 'Plan not found'; end if;
  if v.is_trial then raise exception 'New shops start on this plan — mark another plan as the trial plan first'; end if;
  if exists (select 1 from public.subscriptions where plan_id = p_id)
     or exists (select 1 from public.subscription_payments where plan_id = p_id) then
    raise exception 'Shops have used this plan — hide it instead of deleting it';
  end if;
  delete from public.plans where id = p_id;
  perform public.admin_log(null, 'plan.deleted', 'plan', p_id::text, to_jsonb(v));
end $$;

-- ============================================================
-- G. System health knows about this migration
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
      '0055', to_regproc('public.admin_save_plan') is not null),
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
    'confirmed_checks', (select confirmed_checks from public.platform_settings where id = 1)
  );
end $$;

-- ============================================================
-- Grants
-- ============================================================
revoke execute on function public.plan_public(public.plans) from public, anon, authenticated;
revoke execute on function public.set_plan_features(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.resolve_plan_requests() from public, anon, authenticated;
revoke execute on function public.get_plans_for_app() from public, anon;
revoke execute on function public.request_plan_change(uuid) from public, anon;
revoke execute on function public.admin_save_plan(uuid, jsonb) from public, anon;
revoke execute on function public.admin_set_plan_active(uuid, boolean) from public, anon;
revoke execute on function public.admin_delete_plan(uuid) from public, anon;
grant execute on function public.get_plans_for_app() to authenticated;
grant execute on function public.request_plan_change(uuid) to authenticated;
grant execute on function public.admin_save_plan(uuid, jsonb) to authenticated, service_role;
grant execute on function public.admin_set_plan_active(uuid, boolean) to authenticated, service_role;
grant execute on function public.admin_delete_plan(uuid) to authenticated, service_role;
