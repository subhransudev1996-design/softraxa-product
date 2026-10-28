-- ============================================================
-- 0097: Asking for more staff logins; the plan screen's add-ons.
--
--   * request_staff_login(): the owner of a shop at its login limit asks
--     Dukania for more staff logins. It becomes a support request (one
--     open request per shop; asking again updates the count) that the
--     admin sees on the Today page. Adding staff logins to the shop
--     answers and closes it, like a plan request (0055).
--   * get_plans_for_app() also returns the shop's add-ons in force and
--     whether a staff-login request is open — never a price.
--   * admin_record_sale(): the receipt's website total takes the
--     website discount off the plan only; add-ons are charged in full.
--
-- Run AFTER 0096.
-- ============================================================

alter table public.support_tickets
  add column if not exists requested_staff integer
    check (requested_staff is null or requested_staff between 1 and 20);

create or replace function public.request_staff_login(p_count integer default 1)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_id       uuid;
  v_msg      text;
begin
  if v_business is null then raise exception 'No shop selected'; end if;
  if not public.has_permission('owner') then
    raise exception 'Only the owner can ask for more staff logins' using errcode = '42501';
  end if;
  if p_count is null or p_count < 1 or p_count > 20 then raise exception 'Ask for 1 to 20 logins'; end if;
  v_msg := 'Please add ' || p_count || ' more staff login' || case when p_count > 1 then 's' else '' end
           || ' to my shop.';

  select id into v_id from public.support_tickets
    where business_id = v_business and requested_staff is not null and status <> 'resolved'
    order by created_at desc limit 1;
  if v_id is not null then
    update public.support_tickets set requested_staff = p_count, message = v_msg where id = v_id;
    return v_id;
  end if;

  insert into public.support_tickets (business_id, subject, message, created_by, requested_staff)
    values (v_business, 'Request: more staff logins', v_msg, auth.uid(), p_count)
    returning id into v_id;
  insert into public.audit_logs (business_id, user_id, action, entity, entity_id, details)
    values (v_business, auth.uid(), 'subscription.staff_requested', 'support_ticket', v_id::text,
            jsonb_build_object('count', p_count));
  return v_id;
end $$;

-- Adding staff logins answers and closes the shop's open request.
create or replace function public.resolve_staff_requests()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  t record;
begin
  if new.kind <> 'staff' then return new; end if;
  for t in
    select id, business_id from public.support_tickets
    where business_id = new.business_id and requested_staff is not null and status <> 'resolved'
    for update
  loop
    insert into public.support_messages (ticket_id, business_id, from_softraxa, body, created_by)
      values (t.id, t.business_id, true,
              'Done — ' || new.quantity || ' more staff login' || case when new.quantity > 1 then 's' else '' end
                || ' added to your shop. Add them in Staff & Permissions.',
              auth.uid());
    update public.support_tickets
       set last_reply_at = clock_timestamp(), status = 'resolved', reply_notified_at = null
     where id = t.id;
  end loop;
  return new;
end $$;
drop trigger if exists trg_shop_addons_staff_requests on public.shop_addons;
create trigger trg_shop_addons_staff_requests
  after insert on public.shop_addons
  for each row execute function public.resolve_staff_requests();

-- As 0055, plus the add-ons in force and an open staff-login request.
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
    'support_whatsapp', (select support_whatsapp from public.platform_settings where id = 1),
    -- Paid add-ons in force (no prices) and an open staff-login request.
    'addons', public.my_addons(),
    'staff_request_open', exists (
      select 1 from public.support_tickets t
      where t.business_id = v_business and t.requested_staff is not null and t.status <> 'resolved'));
end $$;

-- As 0096, with the website total discounting the plan only.
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

revoke execute on function public.request_staff_login(integer) from public, anon;
grant execute on function public.request_staff_login(integer) to authenticated;
