-- ============================================================
-- 0096: Plan pricing, lifetime plans and paid add-ons.
--
--   * Plans carry how they are billed (yearly or lifetime), a LIST price,
--     the admin's LOWEST price (never shown to shops or on the website),
--     and the prices of their add-ons: an extra staff login and, for
--     plans without AI, the AI assistant. The website shows the list
--     price less one site-wide discount (platform_settings).
--   * Paid add-ons per shop (shop_addons), each valid until a date:
--     extra staff logins raise the shop's user limit; an AI add-on
--     switches the AI assistant on. Both stop on their own when they
--     expire — every check works out the shop's limit and AI from the
--     plan plus the add-ons in force that day.
--   * The three plans of October 2026: Standard and Standard + AI
--     (yearly) and Lifetime, each with 1 owner + 2 staff.
--   * admin_record_sale(): plan, period, add-ons and the payment in one
--     step, with a receipt that shows list price, discount and add-ons.
--
-- The app still shows no prices (0055): plan_public() carries none.
-- Run AFTER 0095.
-- ============================================================

-- ------------------------------------------------------------
-- A. Plans and settings
-- ------------------------------------------------------------
alter table public.plans
  add column if not exists billing text not null default 'yearly',
  add column if not exists list_price numeric(12,2) not null default 0,
  add column if not exists lowest_price numeric(12,2) not null default 0,
  add column if not exists extra_staff_price numeric(12,2) not null default 0,
  add column if not exists ai_addon_price numeric(12,2) not null default 0;
alter table public.plans drop constraint if exists plans_billing_check;
alter table public.plans add constraint plans_billing_check
  check (billing in ('yearly', 'lifetime')
         and list_price >= 0 and lowest_price >= 0
         and extra_staff_price >= 0 and ai_addon_price >= 0);

alter table public.platform_settings
  add column if not exists website_discount_pct numeric(5,2) not null default 20;
alter table public.platform_settings drop constraint if exists platform_settings_discount_check;
alter table public.platform_settings add constraint platform_settings_discount_check
  check (website_discount_pct >= 0 and website_discount_pct <= 90);

alter table public.subscription_payments
  add column if not exists breakdown jsonb not null default '{}'::jsonb;

-- ------------------------------------------------------------
-- B. Paid add-ons per shop
-- ------------------------------------------------------------
create table if not exists public.shop_addons (
  id          uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  kind        text not null check (kind in ('staff', 'ai')),
  quantity    integer not null default 1 check (quantity between 1 and 50),
  valid_until date not null,
  price       numeric(12,2) not null default 0 check (price >= 0),
  payment_id  uuid references public.subscription_payments(id) on delete set null,
  note        text not null default '',
  created_by  uuid references public.profiles(id),
  created_at  timestamptz not null default now()
);
create index if not exists shop_addons_business_idx on public.shop_addons (business_id, kind, valid_until);

alter table public.shop_addons enable row level security;
drop policy if exists "admin all" on public.shop_addons;
create policy "admin all" on public.shop_addons for all
  using (public.is_admin()) with check (public.is_admin());
-- Shops see their add-ons only through my_addons(), which carries no prices.

-- ------------------------------------------------------------
-- C. What a shop has today: plan + add-ons in force
-- ------------------------------------------------------------
create or replace function public.plan_includes_ai(p_plan uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select included_features ? 'ai_assistant' from public.plans where id = p_plan), false);
$$;

create or replace function public.business_extra_staff(p_business uuid)
returns integer language sql stable security definer set search_path = public as $$
  select coalesce(sum(quantity), 0)::integer from public.shop_addons
  where business_id = p_business and kind = 'staff'
    and valid_until >= public.ist_date(now());
$$;

create or replace function public.business_has_ai(p_business uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.plan_includes_ai((select plan_id from public.subscriptions
                                  where business_id = p_business
                                  order by created_at desc limit 1))
      or exists (select 1 from public.shop_addons
                 where business_id = p_business and kind = 'ai'
                   and valid_until >= public.ist_date(now()));
$$;

-- As 0037, plus the extra staff logins the shop has paid for.
create or replace function public.business_user_limit(p_business uuid)
returns integer language plpgsql stable security definer set search_path = public as $$
declare
  v_found boolean := false;
  v_plan  uuid;
  v_limit integer;
begin
  select true, s.plan_id, pl.user_limit into v_found, v_plan, v_limit
    from public.subscriptions s left join public.plans pl on pl.id = s.plan_id
    where s.business_id = p_business
    order by s.created_at desc limit 1;
  if not coalesce(v_found, false) or v_plan is null then
    return 1 + public.business_extra_staff(p_business);
  end if;
  if v_limit is null then return null; end if;   -- unlimited
  return v_limit + public.business_extra_staff(p_business);
end $$;

-- The shop's AI switch follows the plan and its AI add-on.
create or replace function public.refresh_business_ai(p_business uuid)
returns void language sql security definer set search_path = public as $$
  update public.feature_flags set ai_assistant = public.business_has_ai(p_business), updated_at = now()
  where business_id = p_business and ai_assistant is distinct from public.business_has_ai(p_business);
$$;

-- As 0086, then the AI add-on on top of the plan.
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
      using (v_key = any(v_included)
             or (array_length(v_included, 1) is null and v_key <> 'ai_assistant')), p_business;
  end loop;
  perform public.refresh_business_ai(p_business);
end $$;

-- Nightly: AI switches off for shops whose AI add-on has run out.
create or replace function public.expire_addons()
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_n integer := 0;
  v_b uuid;
begin
  for v_b in select f.business_id from public.feature_flags f
             where f.ai_assistant and not public.business_has_ai(f.business_id) loop
    perform public.refresh_business_ai(v_b);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;
revoke execute on function public.expire_addons() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('dukania-expire-addons', '35 18 * * *', 'select public.expire_addons()');
  end if;
end $$;

-- ------------------------------------------------------------
-- D. Saving a plan's pricing (admin)
-- ------------------------------------------------------------
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
  perform public.assert_platform_admin();
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

-- ------------------------------------------------------------
-- E. Selling: plan + period + add-ons + payment, one step
-- ------------------------------------------------------------
-- p: plan_id, extra_staff (count), ai_addon (bool, plans without AI),
--    amount (what the shop paid in all), mode, reference, payment_date, note.
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
  perform public.assert_platform_admin();
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
  v_web := round(v_list * (1 - v_disc / 100));
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

-- An add-on bought on its own (one more staff login mid-year, or a year
-- of AI for a lifetime shop), with its payment when there is one.
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
  perform public.assert_platform_admin();
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

-- Ending an add-on entered by mistake (its payment stays on record).
create or replace function public.admin_end_addon(p_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_b uuid;
begin
  perform public.assert_platform_admin();
  if btrim(coalesce(p_reason, '')) = '' then raise exception 'Give a reason'; end if;
  update public.shop_addons set valid_until = public.ist_date(now()) - 1
    where id = p_id returning business_id into v_b;
  if v_b is null then raise exception 'Add-on not found'; end if;
  perform public.refresh_business_ai(v_b);
  perform public.admin_log(v_b, 'addon.ended', 'shop_addon', p_id::text, jsonb_build_object('reason', p_reason));
end $$;

-- ------------------------------------------------------------
-- F. What the app and the website see (no lowest price anywhere)
-- ------------------------------------------------------------
-- As 0055, plus how the plan is billed (no prices).
create or replace function public.plan_public(p public.plans)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', p.id,
    'name', p.name,
    'description', p.description,
    'highlights', p.highlights,
    'billing', p.billing,
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
               'included', case when jsonb_array_length(p.included_features) = 0
                                then x.f ->> 'key' <> 'ai_assistant'
                                else p.included_features ? (x.f ->> 'key') end)
             order by x.ord)
      from public.software_products sp,
           jsonb_array_elements(sp.features) with ordinality as x(f, ord)
      where sp.id = coalesce(p.software_id,
                             (select id from public.software_products where slug = 'dukania'))
    ), '[]'::jsonb));
$$;

-- The shop's own add-ons in force, without prices.
create or replace function public.my_addons()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'quantity', quantity,
                                               'valid_until', valid_until) order by kind, valid_until), '[]'::jsonb)
  from public.shop_addons
  where business_id = public.current_business_id() and valid_until >= public.ist_date(now());
$$;

-- As 0059, plus the plans with their list and website prices.
create or replace function public.public_site_info()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'whatsapp', s.support_whatsapp,
    'phone',    s.business_phone,
    'email',    s.business_email,
    'address',  s.business_address,
    'android_download_url', s.android_download_url,
    'windows_download_url', s.windows_download_url,
    'website_discount_pct', s.website_discount_pct,
    -- Dukania's cheapest yearly plan, at its website price.
    'from_yearly', (select min(round(p.list_price * (1 - s.website_discount_pct / 100)))
                    from public.plans p join public.software_products sp on sp.id = p.software_id
                    where sp.slug = 'dukania' and p.is_active and not p.is_trial
                      and not coalesce(p.is_custom, false) and p.billing = 'yearly' and p.list_price > 0),
    'from_monthly', null,
    'plans', coalesce((
      select jsonb_agg(jsonb_build_object(
               'name', p.name, 'description', p.description, 'highlights', p.highlights,
               'billing', p.billing, 'is_recommended', p.is_recommended,
               'includes_ai', p.included_features ? 'ai_assistant',
               'users', p.user_limit,
               'list_price', p.list_price,
               'website_price', round(p.list_price * (1 - s.website_discount_pct / 100)),
               'extra_staff_price', p.extra_staff_price,
               'ai_addon_price', p.ai_addon_price)
             order by p.sort_order, p.list_price)
      from public.plans p join public.software_products sp on sp.id = p.software_id
      where sp.slug = 'dukania' and p.is_active and not p.is_trial
        and not coalesce(p.is_custom, false) and p.list_price > 0), '[]'::jsonb),
    'trial_days', (select trial_days from public.software_products where slug = 'dukania'))
  from public.platform_settings s where s.id = 1
$$;


-- As 0095: the AI check counts an AI add-on in force, not only the plan.
create or replace function public.ai_context()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_profile  public.profiles;
  v_business public.businesses;
  v_id       uuid := public.current_business_id();
  v_reason   text;
  v_perms    jsonb := '{}'::jsonb;
  v_key      text;
  v_sub      jsonb;
begin
  select * into v_profile from public.profiles where id = auth.uid();
  select * into v_business from public.businesses where id = v_id;

  if v_profile.id is null then
    v_reason := 'Sign in with your Dukania account.';
  elsif v_profile.role::text = 'admin' then
    v_reason := 'This is a Dukania admin account. Use the Dukania Admin connector instead.';
  elsif v_profile.business_id is null then
    v_reason := 'This account isn''t part of a shop yet. Finish setting up your shop in the Dukania app first.';
  elsif v_id is null then
    v_reason := 'Your shop''s plan has more staff than it allows, so this login is paused. Ask the shop owner.';
  elsif not coalesce(v_business.is_active, false) then
    v_reason := 'This shop is suspended. Contact Dukania support.';
  elsif not public.business_has_ai(v_id) then
    v_reason := 'The AI assistant isn''t included in your shop''s plan. Contact Dukania to add it.';
  elsif not public.has_permission('can_use_ai') then
    v_reason := 'The shop owner hasn''t allowed you to use the AI assistant. Ask them to turn it on for you in Staff.';
  end if;

  if v_reason is not null then
    return jsonb_build_object('allowed', false, 'reason', v_reason);
  end if;

  for v_key in select jsonb_object_keys(public.staff_permission_defaults()) loop
    v_perms := v_perms || jsonb_build_object(v_key, public.has_permission(v_key));
  end loop;
  v_perms := v_perms || jsonb_build_object('owner', public.has_permission('owner'));

  select jsonb_build_object(
           'plan', pl.name, 'status', s.status, 'expiry_date', s.expiry_date,
           'can_make_changes', public.business_is_writable(v_id))
    into v_sub
    from public.subscriptions s left join public.plans pl on pl.id = s.plan_id
    where s.business_id = v_id
    order by s.created_at desc limit 1;

  return jsonb_build_object(
    'allowed', true,
    'shop', jsonb_strip_nulls(jsonb_build_object(
      'name', v_business.name,
      'type', v_business.business_type,
      'gstin', nullif(v_business.gst_number, ''),
      'state_code', nullif(v_business.state_code, ''),
      'tax', v_business.tax_preference,
      'phone', nullif(v_business.phone, ''))),
    'user', jsonb_build_object('name', v_profile.full_name, 'role', v_profile.role),
    'permissions', v_perms,
    'features', (select to_jsonb(f) - 'business_id' - 'updated_at'
                 from public.feature_flags f where f.business_id = v_id),
    'subscription', v_sub,
    'today', public.ist_date(now()));
end $$;

-- The website's discount on list prices (admin Settings).
create or replace function public.admin_set_website_discount(p_pct numeric)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_old numeric;
begin
  perform public.assert_platform_admin();
  if p_pct is null or p_pct < 0 or p_pct > 90 then raise exception 'Discount: 0 to 90%%'; end if;
  select website_discount_pct into v_old from public.platform_settings where id = 1;
  update public.platform_settings set website_discount_pct = round(p_pct, 2) where id = 1;
  perform public.admin_log(null, 'settings.website_discount', 'platform_settings', '1',
    jsonb_build_object('from', v_old, 'to', p_pct));
end $$;

-- ------------------------------------------------------------
-- G. The plans of October 2026 (added once; edit them on the Plans page)
-- ------------------------------------------------------------
insert into public.plans (name, description, highlights, software_id, billing, list_price, lowest_price,
                          yearly_price, extra_staff_price, ai_addon_price, user_limit,
                          included_features, sort_order, is_recommended)
select v.name, v.description, v.highlights::jsonb, sp.id, v.billing, v.list_price, v.lowest_price,
       case when v.billing = 'yearly' then v.list_price else 0 end, 1000, v.ai_price, 3,
       case when v.with_ai then to_jsonb(public.app_feature_keys()) else '[]'::jsonb end,
       v.sort_order, v.recommended
from (values
  ('Standard', 'Everything for billing, stock and GST. 1 owner + 2 staff.',
   '["Every feature except the AI assistant", "Android and Windows on one account", "1 owner + 2 staff logins", "Updates and WhatsApp support"]',
   'yearly', 3499::numeric, 2500::numeric, 0::numeric, false, 10, false),
  ('Standard + AI', 'Everything, with the AI assistant in ChatGPT and Claude. 1 owner + 2 staff.',
   '["Every feature, including the AI assistant", "Run the shop from ChatGPT or Claude", "1 owner + 2 staff logins", "Updates and WhatsApp support"]',
   'yearly', 5999, 3999, 0, true, 20, true),
  ('Lifetime', 'Pay once, use Dukania for life. AI available as a yearly add-on.',
   '["Every feature except the AI assistant", "One payment, no yearly renewal", "1 owner + 2 staff logins", "AI assistant as a yearly add-on"]',
   'lifetime', 19999, 15000, 1499, false, 30, false)
) as v(name, description, highlights, billing, list_price, lowest_price, ai_price, with_ai, sort_order, recommended)
cross join (select id from public.software_products where slug = 'dukania') sp
where not exists (select 1 from public.plans p where lower(p.name) = lower(v.name)
                  and p.software_id is not distinct from sp.id);

-- ------------------------------------------------------------
-- Grants
-- ------------------------------------------------------------
revoke execute on function public.plan_includes_ai(uuid) from public, anon, authenticated;
revoke execute on function public.business_extra_staff(uuid) from public, anon, authenticated;
revoke execute on function public.business_has_ai(uuid) from public, anon, authenticated;
revoke execute on function public.refresh_business_ai(uuid) from public, anon, authenticated;
revoke execute on function public.admin_save_plan_pricing(uuid, jsonb) from public, anon;
revoke execute on function public.admin_record_sale(uuid, jsonb) from public, anon;
revoke execute on function public.admin_add_addon(uuid, jsonb) from public, anon;
revoke execute on function public.admin_end_addon(uuid, text) from public, anon;
revoke execute on function public.my_addons() from public, anon;
grant execute on function public.admin_save_plan_pricing(uuid, jsonb) to authenticated;
grant execute on function public.admin_record_sale(uuid, jsonb) to authenticated;
grant execute on function public.admin_add_addon(uuid, jsonb) to authenticated;
grant execute on function public.admin_end_addon(uuid, text) to authenticated;
grant execute on function public.my_addons() to authenticated;
revoke execute on function public.admin_set_website_discount(numeric) from public, anon;
grant execute on function public.admin_set_website_discount(numeric) to authenticated;
grant execute on function public.public_site_info() to anon, authenticated;
