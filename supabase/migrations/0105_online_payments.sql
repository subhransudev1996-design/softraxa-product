-- ============================================================
-- 0105 — Online payments (Razorpay) on the website.
--
--   * a switch in Settings (platform_settings.online_payments);
--   * the owner gets a short-lived pay link (create_pay_link) from the app
--     or after signing in on the website: dukania.in/pay knows the shop
--     without a password in the URL;
--   * the server functions razorpay (quote, order, confirm) and
--     razorpay-webhook use the service role:
--       online_context(token)        the shop, its plan and what it can buy;
--       online_quote(business, item) the exact amount — the browser never
--                                    sets a price;
--       online_order_paid(order, payment)
--                                    records the sale once: plan and add-ons
--                                    as on Record a sale (GST invoice,
--                                    promo code, partner commission), or an
--                                    add-on on its own;
--   * plans are paid once a year (no auto-renew); Lifetime is one payment.
--     An add-on bought mid-year on a yearly plan is charged for the days
--     left; on Lifetime it runs a year.
--   * online_orders: every checkout, for the Payments page.
-- ============================================================

create or replace function pg_temp.team_table(p_table text, p_area text) returns void language plpgsql as $$
begin
  execute format('alter table public.%I enable row level security', p_table);
  execute format('drop policy if exists "admin all" on public.%I', p_table);
  execute format('create policy "admin all" on public.%I for all using (public.is_admin()) with check (public.is_admin())', p_table);
  execute format('drop policy if exists "team area" on public.%I', p_table);
  execute format('create policy "team area" on public.%I as restrictive for all '
                 'using (not public.is_admin() or public.admin_can(%L)) '
                 'with check (not public.is_admin() or public.admin_can(%L))', p_table, p_area, p_area);
end $$;

alter table public.platform_settings
  add column if not exists online_payments boolean not null default false;

-- A server job: the service role, not a signed-in person (same rule as
-- assert_admin_area).
create or replace function public.is_server_job()
returns boolean language sql stable security definer set search_path = public as $$
  select auth.uid() is null and coalesce(public.request_role(), '') not in ('anon', 'authenticated')
$$;
revoke execute on function public.is_server_job() from public, anon, authenticated;

-- Promo codes are checked for online checkouts too (by the server).
create or replace function public.admin_check_promo(p_code text, p_plan uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v public.promo_codes;
  v_plan public.plans;
  v_web numeric;
  v_off numeric;
begin
  if not (public.is_server_job() or public.admin_can('payments') or public.admin_can('marketing')) then
    raise exception 'Admin only' using errcode = '42501';
  end if;
  select * into v from public.promo_codes where code = upper(btrim(coalesce(p_code, '')));
  if v.id is null then return jsonb_build_object('ok', false, 'reason', 'No such code'); end if;
  if not v.active then return jsonb_build_object('ok', false, 'reason', 'This code is switched off'); end if;
  if v.valid_until is not null and v.valid_until < public.ist_date(now()) then
    return jsonb_build_object('ok', false, 'reason', 'This code ended on ' || to_char(v.valid_until, 'DD Mon YYYY'));
  end if;
  if v.max_uses is not null and v.used_count >= v.max_uses then
    return jsonb_build_object('ok', false, 'reason', 'This code has been used ' || v.used_count || ' times — its limit');
  end if;
  select * into v_plan from public.plans where id = p_plan;
  if v_plan.id is null then return jsonb_build_object('ok', false, 'reason', 'Choose the plan'); end if;
  if v.plan_ids is not null and not (p_plan = any(v.plan_ids)) then
    return jsonb_build_object('ok', false, 'reason', 'Not for the ' || v_plan.name || ' plan');
  end if;
  v_web := round(v_plan.list_price * (1 - (select website_discount_pct from public.platform_settings where id = 1) / 100));
  v_off := least(v_web, case when v.kind = 'amount' then v.value else round(v_web * v.value / 100) end);
  return jsonb_build_object('ok', true, 'code', v.code, 'kind', v.kind, 'value', v.value,
                            'website_price', v_web, 'discount', v_off, 'price', v_web - v_off);
end $$;

-- ============================================================
-- A. Pay links
-- ============================================================
create table if not exists public.pay_links (
  token        text primary key,
  business_id  uuid not null references public.businesses(id) on delete cascade,
  user_id      uuid references public.profiles(id) on delete cascade,
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null
);
alter table public.pay_links enable row level security;   -- no policies: functions only

create or replace function public.online_payments_on()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select online_payments from public.platform_settings where id = 1), false)
$$;

-- The owner's link to dukania.in/pay, good for 2 hours.
create or replace function public.create_pay_link()
returns text language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_token text := replace(gen_random_uuid()::text, '-', '');
begin
  if not public.online_payments_on() then raise exception 'Online payment is not available yet — contact Dukania'; end if;
  if v_business is null then raise exception 'No shop'; end if;
  if (select role from public.profiles where id = auth.uid()) <> 'owner' then
    raise exception 'Only the shop owner can pay for the plan';
  end if;
  delete from public.pay_links where business_id = v_business and expires_at < now();
  insert into public.pay_links (token, business_id, user_id, expires_at)
  values (v_token, v_business, auth.uid(), now() + interval '2 hours');
  return v_token;
end $$;

-- ============================================================
-- B. What a shop can buy, and for how much (server only)
-- ============================================================
create or replace function public.online_context(p_token text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_link public.pay_links;
  v_b public.businesses;
  v_sub public.subscriptions;
  v_plan public.plans;
  v_today date := public.ist_date(now());
  v_disc numeric := (select website_discount_pct from public.platform_settings where id = 1);
  v_partner text;
begin
  select * into v_link from public.pay_links where token = p_token and expires_at > now();
  if v_link.token is null then return null; end if;
  select * into v_b from public.businesses where id = v_link.business_id;
  select * into v_sub from public.subscriptions where business_id = v_b.id order by created_at desc limit 1;
  select * into v_plan from public.plans where id = v_sub.plan_id;
  -- An influencer's code fills in on the shop's first payment (0104).
  select p.code into v_partner from public.partners p
   where p.id = v_b.partner_id and p.active and p.buyer_off_pct > 0
     and not exists (select 1 from public.subscription_payments x where x.business_id = v_b.id and x.amount > 0);
  return jsonb_build_object(
    'business_id', v_b.id, 'shop', v_b.name,
    'email', coalesce(nullif((select email from public.profiles where id = v_link.user_id), ''), v_b.email),
    'phone', v_b.phone,
    'current', case when v_plan.id is null then null else jsonb_build_object(
      'plan', v_plan.name, 'billing', v_plan.billing, 'is_trial', v_plan.is_trial,
      'includes_ai', public.plan_includes_ai(v_plan.id),
      'expiry', v_sub.expiry_date,
      'active', v_sub.status = 'active' and v_sub.expiry_date >= v_today,
      'extra_staff_price', v_plan.extra_staff_price, 'ai_addon_price', v_plan.ai_addon_price) end,
    'partner_code', v_partner,
    'plans', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', p.id, 'name', p.name, 'description', p.description, 'billing', p.billing,
               'is_recommended', p.is_recommended, 'includes_ai', public.plan_includes_ai(p.id),
               'users', p.user_limit, 'list_price', p.list_price,
               'website_price', round(p.list_price * (1 - v_disc / 100)),
               'extra_staff_price', p.extra_staff_price, 'ai_addon_price', p.ai_addon_price)
             order by p.sort_order, p.list_price)
      from public.plans p join public.software_products sp on sp.id = p.software_id
      where sp.slug = 'dukania' and p.is_active and not p.is_trial
        and not coalesce(p.is_custom, false) and p.list_price > 0), '[]'::jsonb));
end $$;

-- The exact amount for an item:
--   {kind:'plan', plan_id, extra_staff, ai_addon, code}
--   {kind:'addon', addon:'staff'|'ai', quantity}
create or replace function public.online_quote(p_business uuid, p jsonb)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_today date := public.ist_date(now());
  v_disc numeric := (select website_discount_pct from public.platform_settings where id = 1);
  v_sub public.subscriptions;
  v_cur public.plans;
  v_plan public.plans;
  v_kind text := p ->> 'kind';
  v_staff int := coalesce((p ->> 'extra_staff')::int, 0);
  v_ai boolean := coalesce((p ->> 'ai_addon')::boolean, false);
  v_code text := upper(btrim(coalesce(p ->> 'code', '')));
  v_check jsonb;
  v_web numeric;
  v_off numeric := 0;
  v_lines jsonb := '[]'::jsonb;
  v_amount numeric;
  v_base date;
  v_until date;
  v_active boolean;
  v_addon text := p ->> 'addon';
  v_qty int := greatest(coalesce((p ->> 'quantity')::int, 1), 1);
  v_year numeric;
begin
  select * into v_sub from public.subscriptions where business_id = p_business order by created_at desc limit 1;
  select * into v_cur from public.plans where id = v_sub.plan_id;
  v_active := v_sub.id is not null and v_sub.status = 'active' and v_sub.expiry_date >= v_today;

  if v_kind = 'plan' then
    select p2.* into v_plan from public.plans p2 join public.software_products sp on sp.id = p2.software_id
     where p2.id = nullif(p ->> 'plan_id', '')::uuid and sp.slug = 'dukania' and p2.is_active
       and not p2.is_trial and not coalesce(p2.is_custom, false) and p2.list_price > 0;
    if v_plan.id is null then raise exception 'Choose a plan'; end if;
    if v_active and v_cur.billing = 'lifetime' then
      raise exception 'You''re on Lifetime — no renewal needed. You can buy add-ons.';
    end if;
    if v_staff < 0 or v_staff > 50 then raise exception 'Extra staff logins: 0 to 50'; end if;
    if v_ai and public.plan_includes_ai(v_plan.id) then v_ai := false; end if;
    if v_ai and v_plan.ai_addon_price <= 0 then raise exception 'Choose Standard + AI for the AI assistant'; end if;

    v_web := round(v_plan.list_price * (1 - v_disc / 100));
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('label', v_plan.name || case when v_plan.billing = 'lifetime'
                                              then ' (lifetime)' else ' (1 year)' end, 'amount', v_web));
    if v_staff > 0 then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('label', v_staff || ' extra staff login' ||
                   case when v_staff > 1 then 's' else '' end, 'amount', v_staff * v_plan.extra_staff_price));
    end if;
    if v_ai then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('label', 'AI assistant', 'amount', v_plan.ai_addon_price));
    end if;
    if v_code <> '' then
      v_check := public.admin_check_promo(v_code, v_plan.id);
      if (v_check ->> 'ok')::boolean then
        v_off := (v_check ->> 'discount')::numeric;
        v_lines := v_lines || jsonb_build_array(jsonb_build_object('label', 'Code ' || v_code, 'amount', -v_off));
      end if;
    end if;
    v_amount := v_web - v_off + v_staff * v_plan.extra_staff_price + case when v_ai then v_plan.ai_addon_price else 0 end;
    v_base := greatest(coalesce(case when v_active then v_sub.expiry_date end, v_today), v_today);
    v_until := case when v_plan.billing = 'lifetime' then null else (v_base + interval '1 year')::date end;
    if v_amount < 1 then raise exception 'The amount is too small to pay online — contact Dukania'; end if;
    return jsonb_build_object('kind', 'plan', 'plan_id', v_plan.id, 'plan', v_plan.name, 'billing', v_plan.billing,
      'extra_staff', v_staff, 'ai_addon', v_ai, 'code', nullif(v_code, ''),
      'code_ok', case when v_code = '' then null else (v_check ->> 'ok')::boolean end,
      'code_reason', v_check ->> 'reason', 'lines', v_lines, 'discount', v_off, 'amount', v_amount,
      'from', v_base, 'until', v_until);

  elsif v_kind = 'addon' then
    if not v_active then raise exception 'Your plan has ended — renew the plan first'; end if;
    if coalesce(v_cur.is_trial, false) then raise exception 'Take a plan first — add-ons are for paid plans'; end if;
    if v_addon not in ('staff', 'ai') then raise exception 'Choose staff logins or the AI assistant'; end if;
    if v_addon = 'ai' then
      v_qty := 1;
      if public.plan_includes_ai(v_cur.id) then raise exception 'Your plan already includes the AI assistant'; end if;
      if exists (select 1 from public.shop_addons where business_id = p_business and kind = 'ai' and valid_until >= v_today) then
        raise exception 'You already have the AI assistant';
      end if;
      v_year := v_cur.ai_addon_price;
    else
      if v_qty > 50 then raise exception 'Staff logins: 1 to 50'; end if;
      v_year := v_qty * v_cur.extra_staff_price;
    end if;
    if coalesce(v_year, 0) <= 0 then raise exception 'This add-on isn''t sold online for your plan — contact Dukania'; end if;
    if v_cur.billing = 'lifetime' then
      v_amount := v_year;
      v_until := (v_today + interval '1 year')::date;
    else
      -- The days left on the yearly plan.
      v_until := v_sub.expiry_date;
      v_amount := round(v_year * least(v_until - v_today, 365) / 365.0);
    end if;
    if v_amount < 1 then raise exception 'The amount is too small to pay online — contact Dukania'; end if;
    v_lines := jsonb_build_array(jsonb_build_object('label',
      case when v_addon = 'ai' then 'AI assistant' else v_qty || ' extra staff login' || case when v_qty > 1 then 's' else '' end end
      || case when v_cur.billing = 'lifetime' then ' (1 year)' else ' (until your plan renews)' end, 'amount', v_amount));
    return jsonb_build_object('kind', 'addon', 'addon', v_addon, 'quantity', v_qty, 'lines', v_lines,
      'discount', 0, 'amount', v_amount, 'from', v_today, 'until', v_until);
  end if;
  raise exception 'Choose what to buy';
end $$;

-- ============================================================
-- C. Orders and activation (server only)
-- ============================================================
create table if not exists public.online_orders (
  id              uuid primary key default gen_random_uuid(),
  business_id     uuid not null references public.businesses(id) on delete cascade,
  rzp_order_id    text not null unique,
  kind            text not null check (kind in ('plan', 'addon')),
  item            jsonb not null,
  quote           jsonb not null,
  amount          numeric(12,2) not null check (amount >= 1),
  status          text not null default 'created' check (status in ('created', 'paid', 'failed')),
  rzp_payment_id  text unique,
  payment_id      uuid references public.subscription_payments(id) on delete set null,
  result          jsonb,
  error           text not null default '',
  created_by      uuid references public.profiles(id) on delete set null,
  created_at      timestamptz not null default now(),
  paid_at         timestamptz
);
create index if not exists idx_online_orders_business on public.online_orders(business_id, created_at desc);
select pg_temp.team_table('online_orders', 'payments');

-- Record the order once a payment for it is captured. Safe to call again
-- (the checkout page and the webhook both do): the second call returns the
-- first result. A payment for the wrong amount activates nothing.
create or replace function public.online_order_paid(p_rzp_order text, p_payment jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  o public.online_orders;
  v_method text := coalesce(p_payment ->> 'method', '');
  v_mode text := case when v_method in ('upi', 'card') then v_method else 'other' end;
  v_ref text := btrim(coalesce(p_payment ->> 'id', ''));
  v_note text;
  r jsonb;
  v_pay uuid;
begin
  if not public.is_server_job() then raise exception 'Server only' using errcode = '42501'; end if;
  select * into o from public.online_orders where rzp_order_id = p_rzp_order for update;
  if o.id is null then raise exception 'Unknown order %', p_rzp_order; end if;
  if o.status = 'paid' then return o.result || jsonb_build_object('already', true); end if;
  if v_ref = '' then raise exception 'No payment id'; end if;
  if round(coalesce((p_payment ->> 'amount')::numeric, 0)) <> round(o.amount * 100) then
    update public.online_orders set status = 'failed', rzp_payment_id = v_ref,
      error = 'Paid ' || coalesce(p_payment ->> 'amount', '?') || ' paise, expected ' || round(o.amount * 100)
     where id = o.id;
    perform public.admin_log(o.business_id, 'online.amount_mismatch', 'online_order', o.id::text, p_payment);
    return jsonb_build_object('ok', false, 'error', 'The amount paid doesn''t match — Dukania will contact you');
  end if;
  v_note := 'Paid online (Razorpay' || case when v_method <> '' then ', ' || v_method else '' end || ')';

  if o.kind = 'plan' then
    r := public.admin_record_sale(o.business_id, jsonb_build_object(
      'plan_id', o.item ->> 'plan_id', 'extra_staff', coalesce((o.quote ->> 'extra_staff')::int, 0),
      'ai_addon', coalesce((o.quote ->> 'ai_addon')::boolean, false), 'amount', o.amount,
      'mode', v_mode, 'reference', v_ref, 'note', v_note));
    v_pay := (r ->> 'payment_id')::uuid;
    -- The code (and an influencer's commission). A code that ended since
    -- the quote doesn't stop the plan.
    if coalesce(o.quote ->> 'code', '') <> '' and coalesce((o.quote ->> 'code_ok')::boolean, false) then
      begin
        perform public.admin_redeem_promo(o.quote ->> 'code', v_pay);
      exception when others then
        r := r || jsonb_build_object('code_note', sqlerrm);
      end;
    end if;
  else
    r := public.admin_add_addon(o.business_id, jsonb_build_object(
      'kind', o.quote ->> 'addon', 'quantity', (o.quote ->> 'quantity')::int, 'amount', o.amount,
      'mode', v_mode, 'reference', v_ref, 'note', v_note, 'valid_until', o.quote ->> 'until'));
    select payment_id into v_pay from public.shop_addons where id = (r ->> 'id')::uuid;
  end if;

  r := r || jsonb_build_object('ok', true, 'kind', o.kind, 'amount', o.amount, 'plan', o.quote ->> 'plan',
                               'addon', o.quote ->> 'addon', 'until', coalesce(r ->> 'expiry_date', r ->> 'valid_until'));
  update public.online_orders set status = 'paid', rzp_payment_id = v_ref, payment_id = v_pay,
    result = r, error = '', paid_at = now()
   where id = o.id;
  return r;
end $$;

-- A failed attempt (from the webhook), for the Payments page.
create or replace function public.online_order_failed(p_rzp_order text, p_error text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_server_job() then raise exception 'Server only' using errcode = '42501'; end if;
  update public.online_orders set error = left(coalesce(p_error, ''), 300)
   where rzp_order_id = p_rzp_order and status = 'created';
end $$;

-- ============================================================
-- D. The switch in Settings
-- ============================================================
create or replace function public.admin_set_online_payments(p_on boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_admin_area('settings');
  update public.platform_settings set online_payments = coalesce(p_on, false) where id = 1;
  perform public.admin_log(null, 'settings.online_payments', 'platform_settings', '1', jsonb_build_object('on', p_on));
end $$;

-- ============================================================
-- Grants
-- ============================================================
revoke execute on function public.online_context(text) from public, anon, authenticated;
revoke execute on function public.online_quote(uuid, jsonb) from public, anon, authenticated;
revoke execute on function public.online_order_paid(text, jsonb) from public, anon, authenticated;
revoke execute on function public.online_order_failed(text, text) from public, anon, authenticated;
grant execute on function public.online_context(text) to service_role;
grant execute on function public.online_quote(uuid, jsonb) to service_role;
grant execute on function public.online_order_paid(text, jsonb) to service_role;
grant execute on function public.online_order_failed(text, text) to service_role;
grant execute on function public.is_server_job() to service_role;
revoke execute on function public.create_pay_link() from public, anon;
grant execute on function public.create_pay_link() to authenticated;
grant execute on function public.online_payments_on() to anon, authenticated;
revoke execute on function public.admin_set_online_payments(boolean) from public, anon;
grant execute on function public.admin_set_online_payments(boolean) to authenticated;
revoke execute on function public.admin_check_promo(text, uuid) from public, anon;
grant execute on function public.admin_check_promo(text, uuid) to authenticated, service_role;
