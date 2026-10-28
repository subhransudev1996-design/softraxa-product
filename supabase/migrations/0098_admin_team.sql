-- ============================================================
-- 0098 — Admin team and access.
--
-- The admin panel had one kind of login that could do everything.
-- Now the owner adds team members (Sales, Support, Accounts or a
-- custom mix), each with the areas they may use:
--
--   clients   add clients, block/unblock, switch features
--             (everyone can SEE clients)
--   payments  verify payments, renew, record sales, add-ons, Sales page
--   support   support requests
--   leads     leads and follow-ups
--   catalog   master products and software
--   plans     plans and prices
--   settings  panel settings and the website discount
--   website   the website CMS
--   system    reconciliation, system health, audit logs
--
-- The owner has every area and alone manages the team. Enforced in
-- the database, not just hidden in the panel:
--   * is_admin() is true only for an ACTIVE team member;
--   * every admin_* action checks its area (assert_admin_area);
--   * restrictive row policies keep each table to its area;
--   * the Today page's groups follow the areas.
-- Leads and support requests get "assigned to" (admin_assign).
-- ============================================================

-- ============================================================
-- A. The team
-- ============================================================
create table if not exists public.admin_team (
  user_id      uuid primary key references public.profiles(id) on delete cascade,
  team_role    text not null default 'owner'
               check (team_role in ('owner', 'sales', 'support', 'accounts', 'custom')),
  areas        text[] not null default '{}',
  active       boolean not null default true,
  added_by     uuid references public.profiles(id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  last_seen_at timestamptz
);
drop trigger if exists trg_admin_team_updated on public.admin_team;
create trigger trg_admin_team_updated before update on public.admin_team
  for each row execute function public.set_updated_at();
alter table public.admin_team enable row level security;
-- Read through admin_team_list(); written only by admin_team_save().

-- Everyone who is an admin today becomes an owner.
insert into public.admin_team (user_id, team_role)
select id, 'owner' from public.profiles where role = 'admin'
on conflict (user_id) do nothing;

-- ============================================================
-- B. Who is an admin, and what may they do
-- ============================================================

-- An admin is an ACTIVE team member (a removed member loses access at once).
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((
    select p.role = 'admin' and t.active
    from public.profiles p join public.admin_team t on t.user_id = p.id
    where p.id = auth.uid()), false)
$$;

create or replace function public.admin_all_areas()
returns text[] language sql immutable as $$
  select array['clients', 'payments', 'support', 'leads', 'catalog', 'plans', 'settings', 'website', 'system']
$$;

-- [p_user] (default: the signed-in user) is an active team member who may use [p_area].
create or replace function public.admin_can(p_area text, p_user uuid default null)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((
    select p.role = 'admin' and t.active and (t.team_role = 'owner' or p_area = any(t.areas))
    from public.profiles p join public.admin_team t on t.user_id = p.id
    where p.id = coalesce(p_user, auth.uid())
      -- only admins may ask about someone else
      and (p_user is null or p_user = auth.uid() or public.is_admin())), false)
$$;

create or replace function public.admin_is_owner()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((
    select p.role = 'admin' and t.active and t.team_role = 'owner'
    from public.profiles p join public.admin_team t on t.user_id = p.id
    where p.id = auth.uid()), false)
$$;

-- Like assert_platform_admin(), for one area. Server jobs (service role) pass.
create or replace function public.assert_admin_area(p_area text)
returns void language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null and coalesce(public.request_role(), '') not in ('anon', 'authenticated') then
    return;
  end if;
  if not public.is_admin() then
    raise exception 'Admin only' using errcode = '42501';
  end if;
  if not public.admin_can(p_area) then
    raise exception 'You don''t have access to %. Ask the owner to give it to you on the Team page.', p_area
      using errcode = '42501';
  end if;
end $$;

-- ============================================================
-- C. Team roles change only on the Team page
--    (a team member can't make a shop login an admin, or demote the
--    owner, by writing to profiles directly).
-- ============================================================
create or replace function public.guard_profile_columns()
returns trigger language plpgsql as $$
begin
  if public.is_direct_api_write() then
    if new.role is distinct from old.role and (old.role = 'admin' or new.role = 'admin') then
      raise exception 'Admin team members are changed on the Team page' using errcode = '42501';
    end if;
    if not public.is_admin() then
      if new.id is distinct from old.id
         or new.role is distinct from old.role
         or new.business_id is distinct from old.business_id then
        raise exception 'Your role and business can''t be changed from the app'
          using errcode = '42501';
      end if;
    end if;
  end if;
  return new;
end $$;

-- ============================================================
-- E. Every admin action checks its area. Same functions as before
--    (copied from their latest migration); only the first check
--    changes from assert_platform_admin() to assert_admin_area().
-- ============================================================

-- admin_add_addon (from 0096_pricing_and_addons.sql)
create or replace function public.admin_add_addon(p_business uuid, p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_today   date := public.ist_date(now());
  v_kind    text := p ->> 'kind';
  v_qty     integer := coalesce((p ->> 'quantity')::integer, 1);
  v_amount  numeric := coalesce((p ->> 'amount')::numeric, 0);
  v_mode    public.payment_mode := coalesce(nullif(p ->> 'mode', ''), 'upi')::public.payment_mode;
  v_sub     public.subscriptions;
  v_plan    public.plans;
  v_until   date := nullif(p ->> 'valid_until', '')::date;
  v_receipt text;
  v_pay     uuid;
  v_id      uuid;
begin
  perform public.assert_admin_area('payments');
  if v_kind not in ('staff', 'ai') then raise exception 'Choose staff login or AI'; end if;
  if v_qty < 1 or v_qty > 50 then raise exception 'Quantity: 1 to 50'; end if;
  if v_kind = 'ai' then v_qty := 1; end if;
  if v_amount < 0 then raise exception 'The amount can''t be negative'; end if;
  if v_amount > 0 and v_mode = 'credit' then raise exception 'Choose how the money was received'; end if;
  select * into v_sub from public.subscriptions where business_id = p_business
    order by created_at desc limit 1;
  if v_sub.id is null then raise exception 'This client has no plan yet — record a sale first'; end if;
  select * into v_plan from public.plans where id = v_sub.plan_id;
  if v_kind = 'ai' and public.plan_includes_ai(v_plan.id) then
    raise exception 'This plan already includes AI';
  end if;
  -- Yearly plans: the add-on runs with the plan. Lifetime: one year.
  v_until := coalesce(v_until, case when coalesce(v_plan.billing, 'yearly') = 'lifetime'
                                    then (v_today + interval '1 year')::date
                                    else greatest(v_sub.expiry_date, v_today) end);
  if v_until < v_today then raise exception 'The add-on must run until today or later'; end if;

  if v_amount > 0 then
    v_receipt := 'SR-' || to_char(v_today, 'YYMM') || '-'
                 || lpad(nextval('public.subscription_receipt_seq')::text, 4, '0');
    insert into public.subscription_payments
      (business_id, subscription_id, amount, payment_date, payment_mode, note, recorded_by,
       reference, period_start, period_end, plan_id, receipt_no, breakdown)
    values
      (p_business, v_sub.id, v_amount, coalesce(nullif(p ->> 'payment_date', '')::date, v_today), v_mode,
       btrim(coalesce(p ->> 'note', '')), auth.uid(), btrim(coalesce(p ->> 'reference', '')),
       v_today, v_until, v_sub.plan_id, v_receipt,
       jsonb_build_object('addon', v_kind, 'quantity', v_qty, 'paid', v_amount))
    returning id into v_pay;
  end if;
  insert into public.shop_addons (business_id, kind, quantity, valid_until, price, payment_id, note, created_by)
    values (p_business, v_kind, v_qty, v_until, v_amount, v_pay, btrim(coalesce(p ->> 'note', '')), auth.uid())
    returning id into v_id;
  perform public.refresh_business_ai(p_business);
  perform public.admin_log(p_business, 'addon.added', 'shop_addon', v_id::text,
    jsonb_build_object('kind', v_kind, 'quantity', v_qty, 'until', v_until, 'amount', v_amount,
                       'receipt', v_receipt));
  return jsonb_build_object('id', v_id, 'valid_until', v_until, 'receipt_no', v_receipt);
end $$;

-- admin_end_addon (from 0096_pricing_and_addons.sql)
create or replace function public.admin_end_addon(p_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_b uuid;
begin
  perform public.assert_admin_area('payments');
  if btrim(coalesce(p_reason, '')) = '' then raise exception 'Give a reason'; end if;
  update public.shop_addons set valid_until = public.ist_date(now()) - 1
    where id = p_id returning business_id into v_b;
  if v_b is null then raise exception 'Add-on not found'; end if;
  perform public.refresh_business_ai(v_b);
  perform public.admin_log(v_b, 'addon.ended', 'shop_addon', p_id::text, jsonb_build_object('reason', p_reason));
end $$;

-- admin_record_sale (from 0097_staff_requests.sql)
create or replace function public.admin_record_sale(p_business uuid, p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_today    date := public.ist_date(now());
  v_plan     public.plans;
  v_sub      public.subscriptions;
  v_staff    integer := coalesce((p ->> 'extra_staff')::integer, 0);
  v_ai       boolean := coalesce((p ->> 'ai_addon')::boolean, false);
  v_amount   numeric := coalesce((p ->> 'amount')::numeric, -1);
  v_mode     public.payment_mode := coalesce(nullif(p ->> 'mode', ''), 'upi')::public.payment_mode;
  v_disc     numeric := (select website_discount_pct from public.platform_settings where id = 1);
  v_base     date;
  v_expiry   date;
  v_addon_to date;
  v_list     numeric;
  v_web      numeric;
  v_floor    numeric;
  v_receipt  text;
  v_pay      uuid;
  v_old_plan uuid;
  v_old_exp  date;
  v_bd       jsonb;
begin
  perform public.assert_admin_area('payments');
  if not exists (select 1 from public.businesses where id = p_business) then
    raise exception 'Client not found';
  end if;
  select * into v_plan from public.plans where id = nullif(p ->> 'plan_id', '')::uuid;
  if v_plan.id is null then raise exception 'Choose the plan'; end if;
  if v_plan.list_price <= 0 then raise exception 'Set this plan''s list price on the Plans page first'; end if;
  if v_staff < 0 or v_staff > 50 then raise exception 'Extra staff: 0 to 50'; end if;
  if v_ai and public.plan_includes_ai(v_plan.id) then v_ai := false; end if;
  if v_ai and v_plan.ai_addon_price <= 0 then
    raise exception 'This plan has no AI add-on price — choose Standard + AI instead';
  end if;
  if v_amount < 0 then raise exception 'Enter the amount received'; end if;
  if v_amount > 0 and v_mode = 'credit' then raise exception 'Choose how the money was received'; end if;

  select * into v_sub from public.subscriptions where business_id = p_business
    order by created_at desc limit 1 for update;
  v_old_plan := v_sub.plan_id;
  v_old_exp := v_sub.expiry_date;
  -- A renewal continues from the current expiry; a lapsed shop starts today.
  v_base := greatest(coalesce(case when v_sub.status in ('active') then v_sub.expiry_date end, v_today), v_today);
  if v_plan.billing = 'lifetime' then
    v_expiry := date '2099-12-31';
    v_addon_to := (v_today + interval '1 year')::date;
  else
    v_expiry := (v_base + interval '1 year')::date;
    v_addon_to := v_expiry;
  end if;

  if v_sub.id is null then
    insert into public.subscriptions (business_id, plan_id, status, start_date, expiry_date)
      values (p_business, v_plan.id, 'active', v_today, v_expiry) returning * into v_sub;
  else
    update public.subscriptions set plan_id = v_plan.id, status = 'active', expiry_date = v_expiry,
      grace_days = case when v_plan.billing = 'lifetime' then 0 else grace_days end
      where id = v_sub.id returning * into v_sub;
  end if;
  perform public.set_plan_features(p_business, v_plan.id);

  -- What it would cost at list and website prices, and the lowest.
  v_list := v_plan.list_price + v_staff * v_plan.extra_staff_price
            + case when v_ai then v_plan.ai_addon_price else 0 end;
  -- The website's discount is on the plan; add-ons are charged in full.
  v_web := round(v_plan.list_price * (1 - v_disc / 100)) + (v_list - v_plan.list_price);
  v_floor := v_plan.lowest_price + v_staff * v_plan.extra_staff_price
             + case when v_ai then v_plan.ai_addon_price else 0 end;
  v_bd := jsonb_build_object(
    'plan', v_plan.name, 'billing', v_plan.billing, 'plan_list', v_plan.list_price,
    'extra_staff', v_staff, 'extra_staff_price', v_plan.extra_staff_price,
    'ai_addon', v_ai, 'ai_addon_price', case when v_ai then v_plan.ai_addon_price else 0 end,
    'list_total', v_list, 'website_total', v_web, 'paid', v_amount,
    'discount', greatest(v_list - v_amount, 0),
    'below_lowest', v_amount > 0 and v_amount < v_floor);

  if v_amount > 0 then
    v_receipt := 'SR-' || to_char(v_today, 'YYMM') || '-'
                 || lpad(nextval('public.subscription_receipt_seq')::text, 4, '0');
    insert into public.subscription_payments
      (business_id, subscription_id, amount, payment_date, payment_mode, note, recorded_by,
       reference, period_start, period_end, plan_id, receipt_no, breakdown)
    values
      (p_business, v_sub.id, v_amount, coalesce(nullif(p ->> 'payment_date', '')::date, v_today), v_mode,
       btrim(coalesce(p ->> 'note', '')), auth.uid(), btrim(coalesce(p ->> 'reference', '')),
       v_base, v_expiry, v_plan.id, v_receipt, v_bd)
    returning id into v_pay;
  end if;

  if v_staff > 0 then
    insert into public.shop_addons (business_id, kind, quantity, valid_until, price, payment_id, created_by)
      values (p_business, 'staff', v_staff, v_addon_to, v_staff * v_plan.extra_staff_price, v_pay, auth.uid());
  end if;
  if v_ai then
    insert into public.shop_addons (business_id, kind, quantity, valid_until, price, payment_id, created_by)
      values (p_business, 'ai', 1, v_addon_to, v_plan.ai_addon_price, v_pay, auth.uid());
  end if;
  perform public.refresh_business_ai(p_business);

  perform public.admin_log(p_business, 'subscription.sold', 'subscription', v_sub.id::text,
    v_bd || jsonb_build_object('from', v_old_exp, 'to', v_expiry, 'old_plan', v_old_plan,
                               'receipt', v_receipt, 'mode', v_mode, 'reference', p ->> 'reference'));
  return v_bd || jsonb_build_object('expiry_date', v_expiry, 'receipt_no', v_receipt, 'payment_id', v_pay);
end $$;

-- admin_reject_renewal_claim (from 0053_admin_operations.sql)
create or replace function public.admin_reject_renewal_claim(p_claim uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v record;
begin
  perform public.assert_admin_area('payments');
  if btrim(coalesce(p_reason, '')) = '' then raise exception 'Give a reason the shop will see'; end if;
  update public.renewal_claims
     set status = 'rejected', decision_note = btrim(p_reason), decided_at = now()
   where id = p_claim and status = 'pending'
   returning * into v;
  if v.id is null then raise exception 'Claim not found or already handled'; end if;
  perform public.admin_log(v.business_id, 'subscription.claim_rejected', 'renewal_claim', v.id::text,
    jsonb_build_object('reason', p_reason, 'amount', v.amount, 'reference', v.reference));
end $$;

-- admin_renew_subscription (from 0053_admin_operations.sql)
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
  perform public.assert_admin_area('payments');
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

-- admin_update_subscription (from 0053_admin_operations.sql)
create or replace function public.admin_update_subscription(
  p_business uuid, p_plan uuid, p_status text, p_expiry date, p_grace integer, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_sub record;
  v_before jsonb;
begin
  perform public.assert_admin_area('payments');
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

-- admin_delete_plan (from 0055_plans.sql)
create or replace function public.admin_delete_plan(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v public.plans;
begin
  perform public.assert_admin_area('plans');
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

-- admin_save_plan (from 0055_plans.sql)
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
  perform public.assert_admin_area('plans');
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

-- admin_save_plan_pricing (from 0096_pricing_and_addons.sql)
create or replace function public.admin_save_plan_pricing(p_id uuid, p jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_billing text := coalesce(nullif(p ->> 'billing', ''), 'yearly');
  v_list    numeric := coalesce((p ->> 'list_price')::numeric, 0);
  v_lowest  numeric := coalesce((p ->> 'lowest_price')::numeric, 0);
  v_staff   numeric := coalesce((p ->> 'extra_staff_price')::numeric, 0);
  v_ai      numeric := coalesce((p ->> 'ai_addon_price')::numeric, 0);
  v_before  jsonb;
begin
  perform public.assert_admin_area('plans');
  if v_billing not in ('yearly', 'lifetime') then raise exception 'Billing is yearly or lifetime'; end if;
  if v_list < 0 or v_lowest < 0 or v_staff < 0 or v_ai < 0 then
    raise exception 'A price can''t be negative';
  end if;
  if v_list > 0 and v_lowest > v_list then
    raise exception 'The lowest price can''t be above the list price';
  end if;
  select jsonb_build_object('billing', billing, 'list_price', list_price, 'lowest_price', lowest_price,
                            'extra_staff_price', extra_staff_price, 'ai_addon_price', ai_addon_price)
    into v_before from public.plans where id = p_id;
  if v_before is null then raise exception 'Plan not found'; end if;
  update public.plans set
    billing = v_billing, list_price = v_list, lowest_price = v_lowest,
    extra_staff_price = v_staff, ai_addon_price = v_ai,
    -- Older screens and the website's "from" price read yearly_price.
    yearly_price = case when v_billing = 'yearly' then v_list else 0 end,
    monthly_price = case when v_billing = 'yearly' then monthly_price else 0 end
  where id = p_id;
  perform public.admin_log(null, 'plan.pricing', 'plan', p_id::text,
    jsonb_build_object('before', v_before, 'after', p));
end $$;

-- admin_set_plan_active (from 0055_plans.sql)
create or replace function public.admin_set_plan_active(p_id uuid, p_active boolean)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_name text;
begin
  perform public.assert_admin_area('plans');
  update public.plans set is_active = p_active where id = p_id returning name into v_name;
  if v_name is null then raise exception 'Plan not found'; end if;
  perform public.admin_log(null, case when p_active then 'plan.shown' else 'plan.hidden' end,
    'plan', p_id::text, jsonb_build_object('name', v_name));
end $$;

-- admin_export_master_products (from 0066_shop_types_and_suggested_products.sql)
create or replace function public.admin_export_master_products(p_type text default '')
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.assert_admin_area('catalog');
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'name', m.name, 'brand', m.brand, 'category', m.category, 'unit_name', m.unit_name,
      'hsn_code', m.hsn_code, 'gst_rate', m.gst_rate, 'barcode', m.barcode,
      'business_type', m.business_type, 'description', m.description,
      'secondary_unit_name', coalesce(m.secondary_unit_name, ''),
      'conversion_factor', m.conversion_factor,
      'track_serial', m.track_serial, 'track_pieces', m.track_pieces,
      'warranty_months', m.warranty_months, 'status', m.status)
      order by m.business_type, m.category, m.name)
    from public.master_products m
    where coalesce(p_type, '') = '' or m.business_type = p_type), '[]'::jsonb);
end $$;

-- admin_import_master_products (from 0066_shop_types_and_suggested_products.sql)
create or replace function public.admin_import_master_products(p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_row     jsonb;
  v_n       integer := 0;
  v_added   integer := 0;
  v_updated integer := 0;
  v_errors  jsonb := '[]'::jsonb;
  v_result  text;
begin
  perform public.assert_admin_area('catalog');
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then
    raise exception 'There are no rows to import';
  end if;
  if jsonb_array_length(p_rows) > 3000 then raise exception 'Import up to 3000 rows at a time'; end if;

  for v_row in select * from jsonb_array_elements(p_rows) loop
    v_n := v_n + 1;
    begin
      v_result := public.master_upsert(v_row, true, true);
      if v_result = 'added' then v_added := v_added + 1; else v_updated := v_updated + 1; end if;
    exception when others then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'row', v_n, 'name', coalesce(v_row ->> 'name', ''), 'message', sqlerrm));
    end;
  end loop;

  perform public.admin_log(null, 'master_product.imported', 'master_product', '',
    jsonb_build_object('added', v_added, 'updated', v_updated, 'errors', jsonb_array_length(v_errors)));
  return jsonb_build_object('added', v_added, 'updated', v_updated, 'errors', v_errors);
end $$;

-- admin_merge_master_products (from 0057_master_products.sql)
create or replace function public.admin_merge_master_products(p_from uuid, p_into uuid)
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_from public.master_products;
  v_into public.master_products;
  v_moved integer;
begin
  perform public.assert_admin_area('catalog');
  if p_from = p_into then raise exception 'Choose two different products'; end if;
  select * into v_from from public.master_products where id = p_from for update;
  select * into v_into from public.master_products where id = p_into for update;
  if v_from.id is null or v_into.id is null then raise exception 'Product not found'; end if;
  update public.products set master_product_id = p_into where master_product_id = p_from;
  get diagnostics v_moved = row_count;
  delete from public.master_products where id = p_from;
  perform public.admin_log(null, 'master_product.merged', 'master_product', p_into::text,
    jsonb_build_object('from', v_from.name, 'into', v_into.name, 'products_moved', v_moved));
  return v_moved;
end $$;

-- admin_save_master_product (from 0057_master_products.sql)
create or replace function public.admin_save_master_product(p_id uuid, p jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_old   public.master_products;
  v_new   public.master_products;
  v_name  text := btrim(coalesce(p ->> 'name', ''));
  v_key   text := public.master_name_key(p ->> 'name');
  v_hsn   text := btrim(coalesce(p ->> 'hsn_code', ''));
  v_code  text := btrim(coalesce(p ->> 'barcode', ''));
  v_gst   numeric := coalesce((p ->> 'gst_rate')::numeric, 0);
  v_type  text := coalesce(p ->> 'business_type', '');
  v_bulk  text := nullif(btrim(coalesce(p ->> 'secondary_unit_name', '')), '');
  v_factor numeric := (p ->> 'conversion_factor')::numeric;
  v_other text;
begin
  perform public.assert_admin_area('catalog');
  if char_length(v_key) < 3 then raise exception 'Give the product a name (3 letters or more)'; end if;
  select name into v_other from public.master_products where name_key = v_key and id is distinct from p_id;
  if v_other is not null then raise exception 'Already in the list as "%"', v_other; end if;
  if v_hsn <> '' and v_hsn !~ '^[0-9]{4}([0-9]{2}){0,2}$' then
    raise exception 'The HSN code must be 4, 6 or 8 digits';
  end if;
  if v_gst < 0 or v_gst > 100 then raise exception 'The GST rate must be between 0 and 100'; end if;
  if v_code <> '' then
    select name into v_other from public.master_products where barcode = v_code and id is distinct from p_id limit 1;
    if v_other is not null then raise exception 'This barcode is already on "%"', v_other; end if;
  end if;
  if v_type <> '' and v_type not in (select unnest(enum_range(null::public.business_type))::text) then
    raise exception 'Unknown kind of shop: %', v_type;
  end if;
  if v_bulk is not null and coalesce(v_factor, 0) <= 0 then
    raise exception 'Say how many units make one %', v_bulk;
  end if;

  if p_id is null then
    insert into public.master_products
      (name, name_key, brand, category, unit_name, unit_short, allow_decimal, hsn_code, gst_rate,
       barcode, business_type, description, secondary_unit_name, conversion_factor, track_serial,
       track_pieces, warranty_months, status, source, verified)
    values
      (v_name, v_key, btrim(coalesce(p ->> 'brand', '')), btrim(coalesce(p ->> 'category', '')),
       btrim(coalesce(p ->> 'unit_name', '')), btrim(coalesce(p ->> 'unit_short', '')),
       coalesce((p ->> 'allow_decimal')::boolean, false), v_hsn, v_gst, v_code, v_type,
       btrim(coalesce(p ->> 'description', '')), v_bulk, case when v_bulk is null then null else v_factor end,
       coalesce((p ->> 'track_serial')::boolean, false), coalesce((p ->> 'track_pieces')::boolean, false),
       (p ->> 'warranty_months')::integer, 'published', 'softraxa', true)
    returning * into v_new;
  else
    select * into v_old from public.master_products where id = p_id for update;
    if v_old.id is null then raise exception 'Product not found'; end if;
    update public.master_products set
      name = v_name, name_key = v_key,
      brand = btrim(coalesce(p ->> 'brand', '')),
      category = btrim(coalesce(p ->> 'category', '')),
      unit_name = btrim(coalesce(p ->> 'unit_name', '')),
      unit_short = btrim(coalesce(p ->> 'unit_short', '')),
      allow_decimal = coalesce((p ->> 'allow_decimal')::boolean, false),
      hsn_code = v_hsn, gst_rate = v_gst, barcode = v_code, business_type = v_type,
      description = btrim(coalesce(p ->> 'description', '')),
      secondary_unit_name = v_bulk,
      conversion_factor = case when v_bulk is null then null else v_factor end,
      track_serial = coalesce((p ->> 'track_serial')::boolean, false),
      track_pieces = coalesce((p ->> 'track_pieces')::boolean, false),
      warranty_months = (p ->> 'warranty_months')::integer,
      verified = true,
      status = case when status = 'pending' then 'published' else status end,
      updated_at = now()
    where id = p_id
    returning * into v_new;
  end if;

  perform public.admin_log(null,
    case when p_id is null then 'master_product.created' else 'master_product.updated' end,
    'master_product', v_new.id::text,
    jsonb_build_object('name', v_new.name,
                       'before', case when p_id is null then null else to_jsonb(v_old) end,
                       'after', to_jsonb(v_new)));
  return v_new.id;
end $$;

-- admin_set_catalog_auto_publish (from 0057_master_products.sql)
create or replace function public.admin_set_catalog_auto_publish(p_on boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_admin_area('catalog');
  update public.platform_settings set catalog_auto_publish = coalesce(p_on, true) where id = 1;
  perform public.admin_log(null, 'settings.updated', 'platform_settings', '1',
    jsonb_build_object('catalog_auto_publish', coalesce(p_on, true)));
end $$;

-- admin_set_master_product_image (from 0082_product_photos.sql)
create or replace function public.admin_set_master_product_image(p_id uuid, p_url text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_url text := nullif(btrim(coalesce(p_url, '')), '');
  v_old text;
  v_name text;
begin
  perform public.assert_admin_area('catalog');
  if v_url is not null and v_url !~ '^https://[^ ]+$' then
    raise exception 'The photo address must start with https://';
  end if;
  select image_url, name into v_old, v_name from public.master_products where id = p_id for update;
  if v_name is null then raise exception 'Product not found'; end if;
  update public.master_products set image_url = v_url, updated_at = now() where id = p_id;
  perform public.admin_log(null, 'master_product.photo', 'master_product', p_id::text,
    jsonb_build_object('name', v_name, 'before', v_old, 'after', v_url));
end $$;

-- admin_set_master_product_status (from 0057_master_products.sql)
create or replace function public.admin_set_master_product_status(p_id uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_name text;
begin
  perform public.assert_admin_area('catalog');
  if p_status not in ('published', 'pending', 'hidden') then raise exception 'Unknown status'; end if;
  update public.master_products set status = p_status, updated_at = now()
    where id = p_id returning name into v_name;
  if v_name is null then raise exception 'Product not found'; end if;
  perform public.admin_log(null, 'master_product.' || p_status, 'master_product', p_id::text,
    jsonb_build_object('name', v_name));
end $$;

-- admin_set_master_products_status (from 0066_shop_types_and_suggested_products.sql)
create or replace function public.admin_set_master_products_status(p_ids uuid[], p_status text)
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_n integer;
begin
  perform public.assert_admin_area('catalog');
  if p_status not in ('published', 'pending', 'hidden') then raise exception 'Unknown status'; end if;
  if p_ids is null or coalesce(array_length(p_ids, 1), 0) = 0 then raise exception 'Choose some products'; end if;
  if array_length(p_ids, 1) > 2000 then raise exception 'Up to 2000 products at a time'; end if;
  update public.master_products set status = p_status, updated_at = now() where id = any(p_ids);
  get diagnostics v_n = row_count;
  perform public.admin_log(null, 'master_product.bulk_' || p_status, 'master_product', '',
    jsonb_build_object('count', v_n));
  return v_n;
end $$;

-- get_admin_master_products (from 0066_shop_types_and_suggested_products.sql)
create or replace function public.get_admin_master_products(
  p_search text default '', p_status text default '', p_limit integer default 200,
  p_type text default '', p_category text default '', p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_key  text := public.master_name_key(p_search);
  v_code text := btrim(coalesce(p_search, ''));
  v_cat  text := btrim(coalesce(p_category, ''));
begin
  perform public.assert_admin_area('catalog');
  return (
    with base as (
      select m.*,
             (select count(distinct p.business_id) from public.products p
              where p.master_product_id = m.id) as shops,
             (select b.name from public.businesses b where b.id = m.source_business_id) as source_shop
      from public.master_products m
      where (v_key = '' or m.name_key like '%' || v_key || '%'
             or lower(m.brand) like '%' || lower(v_code) || '%'
             or (v_code <> '' and m.barcode = v_code))),
    by_status as (
      select * from base where coalesce(p_status, '') = '' or status = p_status),
    by_type as (
      select * from by_status where coalesce(p_type, '') = '' or business_type = p_type),
    shown as (
      select * from by_type
      where v_cat = '' or coalesce(nullif(category, ''), 'Other') = v_cat)
    select jsonb_build_object(
      'auto_publish', (select catalog_auto_publish from public.platform_settings where id = 1),
      'counts', (select jsonb_build_object(
                   'all', count(*),
                   'published', count(*) filter (where status = 'published'),
                   'pending', count(*) filter (where status = 'pending'),
                   'hidden', count(*) filter (where status = 'hidden'))
                 from public.master_products),
      'total', (select count(*) from shown),
      'types', coalesce((select jsonb_agg(jsonb_build_object('type', t.business_type, 'count', t.c)
                                          order by t.business_type)
                         from (select business_type, count(*) as c from by_status group by 1) t), '[]'::jsonb),
      'categories', coalesce((select jsonb_agg(jsonb_build_object('category', c.cat, 'count', c.n)
                                               order by c.cat)
                              from (select coalesce(nullif(category, ''), 'Other') as cat, count(*) as n
                                    from by_type group by 1) c), '[]'::jsonb),
      'rows', coalesce((
        select jsonb_agg(to_jsonb(r) order by r.business_type, r.category, r.name)
        from (select * from shown order by business_type, category, name
              limit least(greatest(coalesce(p_limit, 200), 1), 1000)
              offset greatest(coalesce(p_offset, 0), 0)) r), '[]'::jsonb)));
end $$;

-- admin_provision_business (from 0039_admin_provisioning.sql)
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
  perform public.assert_admin_area('clients');

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

-- admin_set_business_status (from 0039_admin_provisioning.sql)
create or replace function public.admin_set_business_status(p_business uuid, p_suspend boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_sub    record;
  v_status public.subscription_status;
begin
  perform public.assert_admin_area('clients');

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

-- admin_set_feature (from 0053_admin_operations.sql)
create or replace function public.admin_set_feature(p_business uuid, p_key text, p_on boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_admin_area('clients');
  if not (p_key = any(public.app_feature_keys())) then raise exception 'Unknown feature %', p_key; end if;
  insert into public.feature_flags (business_id) values (p_business) on conflict (business_id) do nothing;
  execute format('update public.feature_flags set %I = $1, updated_at = now() where business_id = $2', p_key)
    using p_on, p_business;
  perform public.admin_log(p_business, 'feature.' || case when p_on then 'enabled' else 'disabled' end,
    'feature_flags', p_key, jsonb_build_object('feature', p_key));
end $$;

-- admin_reply_ticket (from 0054_support_replies_and_notes.sql)
create or replace function public.admin_reply_ticket(
  p_ticket uuid, p_body text, p_status text default 'in_progress')
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_ticket record;
  v_id     uuid;
begin
  perform public.assert_admin_area('support');
  if btrim(coalesce(p_body, '')) = '' then raise exception 'Write a reply'; end if;
  if p_status not in ('open', 'in_progress', 'resolved') then raise exception 'Unknown status'; end if;
  select * into v_ticket from public.support_tickets where id = p_ticket for update;
  if v_ticket.id is null then raise exception 'Ticket not found'; end if;

  insert into public.support_messages (ticket_id, business_id, from_softraxa, body, created_by)
    values (v_ticket.id, v_ticket.business_id, true, btrim(p_body), auth.uid())
    returning id into v_id;
  update public.support_tickets
     set last_reply_at = clock_timestamp(), status = p_status::public.ticket_status, reply_notified_at = null
   where id = v_ticket.id;
  perform public.admin_log(v_ticket.business_id, 'support.replied', 'support_ticket', v_ticket.id::text,
    jsonb_build_object('status', p_status));
  return v_id;
end $$;

-- admin_set_ticket_status (from 0054_support_replies_and_notes.sql)
create or replace function public.admin_set_ticket_status(p_ticket uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_business uuid;
begin
  perform public.assert_admin_area('support');
  if p_status not in ('open', 'in_progress', 'resolved') then raise exception 'Unknown status'; end if;
  update public.support_tickets set status = p_status::public.ticket_status
    where id = p_ticket returning business_id into v_business;
  if v_business is null then raise exception 'Ticket not found'; end if;
  perform public.admin_log(v_business, 'support.status', 'support_ticket', p_ticket::text,
    jsonb_build_object('status', p_status));
end $$;

-- admin_save_settings (from 0095_dukania_name.sql)
create or replace function public.admin_save_settings(p jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_old     public.platform_settings;
  v_new     public.platform_settings;
  v_upi     text := btrim(coalesce(p ->> 'payment_upi_id', ''));
  v_wa      text := regexp_replace(coalesce(p ->> 'support_whatsapp', ''), '[^0-9]', '', 'g');
  v_gstin   text := upper(btrim(coalesce(p ->> 'business_gstin', '')));
  v_email   text := lower(btrim(coalesce(p ->> 'business_email', '')));
  v_android text := btrim(coalesce(p ->> 'android_download_url', ''));
  v_windows text := btrim(coalesce(p ->> 'windows_download_url', ''));
begin
  perform public.assert_admin_area('settings');
  if v_upi <> '' and v_upi !~ '^[A-Za-z0-9._-]{2,255}@[A-Za-z][A-Za-z0-9]{1,63}$' then
    raise exception 'That doesn''t look like a UPI ID — it should be like dukania@okaxis';
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
  if (v_android <> '' and v_android !~ '^https://[^[:space:]]+$')
     or (v_windows <> '' and v_windows !~ '^https://[^[:space:]]+$') then
    raise exception 'Download links must start with https://';
  end if;

  select * into v_old from public.platform_settings where id = 1 for update;
  update public.platform_settings set
    payment_upi_id       = v_upi,
    payment_payee_name   = coalesce(nullif(btrim(p ->> 'payment_payee_name'), ''), 'Dukania'),
    support_whatsapp     = v_wa,
    business_name        = coalesce(nullif(btrim(p ->> 'business_name'), ''), 'Dukania'),
    business_address     = btrim(coalesce(p ->> 'business_address', '')),
    business_phone       = btrim(coalesce(p ->> 'business_phone', '')),
    business_email       = v_email,
    business_gstin       = v_gstin,
    receipt_footer       = btrim(coalesce(p ->> 'receipt_footer', '')),
    android_download_url = case when p ? 'android_download_url' then v_android else android_download_url end,
    windows_download_url = case when p ? 'windows_download_url' then v_windows else windows_download_url end,
    updated_at           = now(),
    updated_by           = auth.uid()
  where id = 1
  returning * into v_new;

  perform public.admin_log(null, 'settings.updated', 'platform_settings', '1',
    jsonb_build_object(
      'before', to_jsonb(v_old) - 'confirmed_checks' - 'updated_at' - 'updated_by',
      'after',  to_jsonb(v_new) - 'confirmed_checks' - 'updated_at' - 'updated_by'));
end $$;

-- admin_set_website_discount (from 0096_pricing_and_addons.sql)
create or replace function public.admin_set_website_discount(p_pct numeric)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_old numeric;
begin
  perform public.assert_admin_area('settings');
  if p_pct is null or p_pct < 0 or p_pct > 90 then raise exception 'Discount: 0 to 90%%'; end if;
  select website_discount_pct into v_old from public.platform_settings where id = 1;
  update public.platform_settings set website_discount_pct = round(p_pct, 2) where id = 1;
  perform public.admin_log(null, 'settings.website_discount', 'platform_settings', '1',
    jsonb_build_object('from', v_old, 'to', p_pct));
end $$;

-- get_system_health (from 0058_launch_fixes.sql)
create or replace function public.get_system_health()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_cron     boolean := false;
  v_job      boolean := false;
  v_vault    boolean;
begin
  perform public.assert_admin_area('system');
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

-- get_admin_today (from 0095_dukania_name.sql)
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
        where l.status in ('new', 'contacted', 'demo') and l.follow_up_date <= v_today) t), '[]')
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

-- ============================================================
-- F. Each table stays in its area (restrictive: added on top of the
--    existing policies). Shops and the public are not admins, so
--    nothing changes for them.
-- ============================================================
do $$
declare r record;
begin
  for r in select * from (values
      ('leads', 'leads'), ('lead_activities', 'leads'),
      ('support_tickets', 'support'), ('support_messages', 'support'),
      ('subscription_payments', 'payments'), ('renewal_claims', 'payments'), ('shop_addons', 'payments'),
      ('audit_logs', 'system'), ('reconciliation_runs', 'system'), ('reconciliation_issues', 'system'),
      ('website_content', 'website'), ('website_seo', 'website')) v(t, a)
  loop
    execute format('drop policy if exists "team area" on public.%I', r.t);
    execute format('create policy "team area" on public.%I as restrictive for all '
                   'using (not public.is_admin() or public.admin_can(%L)) '
                   'with check (not public.is_admin() or public.admin_can(%L))', r.t, r.a, r.a);
  end loop;
end $$;

-- Plans and settings: everyone on the team may read them, only their area may change them.
do $$
declare r record; c text;
begin
  for r in select * from (values ('plans', 'plans'), ('platform_settings', 'settings')) v(t, a) loop
    foreach c in array array['insert', 'update', 'delete'] loop
      execute format('drop policy if exists "team area %s" on public.%I', c, r.t);
      execute format('create policy "team area %s" on public.%I as restrictive for %s %s',
        c, r.t, c,
        case c
          when 'insert' then format('with check (not public.is_admin() or public.admin_can(%L))', r.a)
          when 'update' then format('using (not public.is_admin() or public.admin_can(%L)) '
                                    'with check (not public.is_admin() or public.admin_can(%L))', r.a, r.a)
          else format('using (not public.is_admin() or public.admin_can(%L))', r.a)
        end);
    end loop;
  end loop;
end $$;

-- ============================================================
-- G. Assigned to: leads and support requests
-- ============================================================
alter table public.leads
  add column if not exists assigned_to uuid references public.profiles(id) on delete set null;
alter table public.support_tickets
  add column if not exists assigned_to uuid references public.profiles(id) on delete set null;
create index if not exists idx_leads_assigned on public.leads(assigned_to);
create index if not exists idx_tickets_assigned on public.support_tickets(assigned_to);

-- A lead someone on the team adds is theirs; website leads stay unassigned.
create or replace function public.leads_default_assignee()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.assigned_to is null and public.is_admin() then
    new.assigned_to := auth.uid();
  end if;
  return new;
end $$;
drop trigger if exists trg_leads_assignee on public.leads;
create trigger trg_leads_assignee before insert on public.leads
  for each row execute function public.leads_default_assignee();

-- p_kind 'lead' or 'ticket'; p_user null = nobody.
create or replace function public.admin_assign(p_kind text, p_id uuid, p_user uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_area text := case p_kind when 'lead' then 'leads' when 'ticket' then 'support' end;
  v_business uuid;
begin
  if v_area is null then raise exception 'Unknown kind %', p_kind; end if;
  perform public.assert_admin_area(v_area);
  if p_user is not null and not public.admin_can(v_area, p_user) then
    raise exception 'That team member has no access to %', v_area;
  end if;
  if p_kind = 'lead' then
    update public.leads set assigned_to = p_user where id = p_id;
  else
    update public.support_tickets set assigned_to = p_user where id = p_id returning business_id into v_business;
  end if;
  if not found then raise exception 'Not found'; end if;
  perform public.admin_log(v_business, p_kind || '.assigned', p_kind, p_id::text,
    jsonb_build_object('to', p_user));
end $$;

-- ============================================================
-- H. The Team page
-- ============================================================

-- The signed-in team member (null = not an active admin). Notes when they were last seen.
create or replace function public.admin_me()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v record;
begin
  select p.id, p.full_name, p.email, t.team_role, t.areas, t.last_seen_at into v
  from public.profiles p join public.admin_team t on t.user_id = p.id
  where p.id = auth.uid() and p.role = 'admin' and t.active;
  if not found then return null; end if;
  if v.last_seen_at is null or v.last_seen_at < now() - interval '5 minutes' then
    update public.admin_team set last_seen_at = now() where user_id = v.id;
  end if;
  return jsonb_build_object(
    'id', v.id, 'name', v.full_name, 'email', v.email, 'team_role', v.team_role,
    'is_owner', v.team_role = 'owner',
    'areas', to_jsonb(case when v.team_role = 'owner' then public.admin_all_areas() else v.areas end));
end $$;

-- Everyone on the team, removed members too (their names stay in the audit log).
create or replace function public.admin_team_list()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admin only' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
        'id', p.id, 'name', p.full_name, 'email', p.email, 'team_role', t.team_role,
        'areas', to_jsonb(case when t.team_role = 'owner' then public.admin_all_areas() else t.areas end),
        'active', t.active, 'last_seen_at', t.last_seen_at, 'created_at', t.created_at,
        'two_step', exists (select 1 from auth.mfa_factors f
                            where f.user_id = p.id and f.status::text = 'verified'))
      order by t.active desc, t.team_role = 'owner' desc, p.full_name)
    from public.admin_team t join public.profiles p on p.id = t.user_id), '[]'::jsonb);
end $$;

-- Owner only: add or change a team member. The login itself is created by
-- the panel (/api/team) with a set-password email; this makes it an admin.
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
     where assigned_to = p_user and status in ('new', 'contacted', 'demo');
    update public.support_tickets set assigned_to = null
     where assigned_to = p_user and status <> 'resolved';
  end if;

  perform public.admin_log(null,
    case when not v_existed then 'team.added' when not v_active then 'team.removed' else 'team.changed' end,
    'admin_team', p_user::text,
    jsonb_build_object('email', v_prof.email, 'role', p_role, 'areas', v_areas, 'active', v_active));
end $$;

-- ============================================================
-- Grants
-- ============================================================
revoke execute on function public.admin_assign(text, uuid, uuid) from public, anon;
revoke execute on function public.admin_me() from public, anon;
revoke execute on function public.admin_team_list() from public, anon;
revoke execute on function public.admin_team_save(uuid, text, text, text[], boolean) from public, anon;
revoke execute on function public.assert_admin_area(text) from public, anon;
grant execute on function public.admin_assign(text, uuid, uuid) to authenticated;
grant execute on function public.admin_me() to authenticated;
grant execute on function public.admin_team_list() to authenticated;
grant execute on function public.admin_team_save(uuid, text, text, text[], boolean) to authenticated;
grant execute on function public.admin_can(text, uuid) to anon, authenticated;
grant execute on function public.admin_is_owner() to authenticated;
