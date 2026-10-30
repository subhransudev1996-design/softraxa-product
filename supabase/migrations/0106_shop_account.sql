-- ============================================================
-- 0106 — The shop's account on dukania.in.
--
--   * upgrades in the middle of a yearly plan:
--       to a dearer yearly plan — starts today, same end date, the shop
--       pays the difference for the days left;
--       to Lifetime — the Lifetime price minus the unused days of the
--       current year;
--   * online_account(token): the plan, days left, logins, add-ons,
--     payments and the upgrades on offer, for dukania.in/account;
--   * a pay link no longer needs online payments switched on (it only
--     says who the shop is; paying still does).
-- ============================================================

alter table public.online_orders drop constraint if exists online_orders_kind_check;
alter table public.online_orders add constraint online_orders_kind_check
  check (kind in ('plan', 'addon', 'upgrade'));

-- The owner's link to dukania.in/pay and /account, good for 2 hours.
create or replace function public.create_pay_link()
returns text language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_token text := replace(gen_random_uuid()::text, '-', '');
begin
  if v_business is null then raise exception 'No shop'; end if;
  if (select role from public.profiles where id = auth.uid()) <> 'owner' then
    raise exception 'Only the shop owner can manage the plan';
  end if;
  delete from public.pay_links where business_id = v_business and expires_at < now();
  insert into public.pay_links (token, business_id, user_id, expires_at)
  values (v_token, v_business, auth.uid(), now() + interval '2 hours');
  return v_token;
end $$;

-- The exact amount for an item:
--   {kind:'plan', plan_id, extra_staff, ai_addon, code}
--   {kind:'addon', addon:'staff'|'ai', quantity}
--   {kind:'upgrade', plan_id}
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
  v_cur_web numeric;
  v_off numeric := 0;
  v_lines jsonb := '[]'::jsonb;
  v_amount numeric;
  v_base date;
  v_until date;
  v_active boolean;
  v_addon text := p ->> 'addon';
  v_qty int := greatest(coalesce((p ->> 'quantity')::int, 1), 1);
  v_year numeric;
  v_days int;
  v_new_part numeric;
  v_credit numeric;
begin
  select * into v_sub from public.subscriptions where business_id = p_business order by created_at desc limit 1;
  select * into v_cur from public.plans where id = v_sub.plan_id;
  v_active := v_sub.id is not null and v_sub.status = 'active' and v_sub.expiry_date >= v_today;

  if v_kind in ('plan', 'upgrade') then
    select p2.* into v_plan from public.plans p2 join public.software_products sp on sp.id = p2.software_id
     where p2.id = nullif(p ->> 'plan_id', '')::uuid and sp.slug = 'dukania' and p2.is_active
       and not p2.is_trial and not coalesce(p2.is_custom, false) and p2.list_price > 0;
    if v_plan.id is null then raise exception 'Choose a plan'; end if;
    v_web := round(v_plan.list_price * (1 - v_disc / 100));
  end if;

  if v_kind = 'plan' then
    if v_active and v_cur.billing = 'lifetime' then
      raise exception 'You''re on Lifetime — no renewal needed. You can buy add-ons.';
    end if;
    if v_staff < 0 or v_staff > 50 then raise exception 'Extra staff logins: 0 to 50'; end if;
    if v_ai and public.plan_includes_ai(v_plan.id) then v_ai := false; end if;
    if v_ai and v_plan.ai_addon_price <= 0 then raise exception 'Choose Standard + AI for the AI assistant'; end if;

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

  elsif v_kind = 'upgrade' then
    if not v_active or coalesce(v_cur.is_trial, false) then
      raise exception 'Upgrades are for a running paid plan — take a plan instead';
    end if;
    if v_cur.billing = 'lifetime' then raise exception 'You''re on Lifetime already'; end if;
    if v_plan.id = v_cur.id then raise exception 'You''re already on %', v_plan.name; end if;
    v_cur_web := round(v_cur.list_price * (1 - v_disc / 100));
    v_days := least(v_sub.expiry_date - v_today, 365);
    v_credit := round(v_cur_web * v_days / 365.0);
    if v_plan.billing = 'lifetime' then
      v_amount := v_web - v_credit;
      v_until := null;
      v_lines := jsonb_build_array(
        jsonb_build_object('label', v_plan.name || ' (lifetime)', 'amount', v_web),
        jsonb_build_object('label', 'Unused ' || v_days || ' days of ' || v_cur.name, 'amount', -v_credit));
    else
      if v_web <= v_cur_web then
        raise exception '% isn''t an upgrade from % — you can change plan when you renew', v_plan.name, v_cur.name;
      end if;
      v_new_part := round(v_web * v_days / 365.0);
      v_amount := v_new_part - v_credit;
      v_until := v_sub.expiry_date;
      v_lines := jsonb_build_array(
        jsonb_build_object('label', v_plan.name || ' for ' || v_days || ' days', 'amount', v_new_part),
        jsonb_build_object('label', v_cur.name || ' for those days', 'amount', -v_credit));
    end if;
    if v_amount < 1 then raise exception 'The amount is too small to pay online — contact Dukania'; end if;
    return jsonb_build_object('kind', 'upgrade', 'plan_id', v_plan.id, 'plan', v_plan.name, 'billing', v_plan.billing,
      'from_plan', v_cur.name, 'days_left', v_days, 'credit', v_credit, 'lines', v_lines, 'discount', 0,
      'amount', v_amount, 'from', v_today, 'until', v_until);

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

-- Record the order once a payment for it is captured (see 0105); now
-- with upgrades.
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
  v_today date := public.ist_date(now());
  v_sub public.subscriptions;
  v_plan public.plans;
  v_receipt text;
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
    if coalesce(o.quote ->> 'code', '') <> '' and coalesce((o.quote ->> 'code_ok')::boolean, false) then
      begin
        perform public.admin_redeem_promo(o.quote ->> 'code', v_pay);
      exception when others then
        r := r || jsonb_build_object('code_note', sqlerrm);
      end;
    end if;

  elsif o.kind = 'upgrade' then
    -- The new plan from today; a yearly upgrade keeps the end date.
    select * into v_sub from public.subscriptions where business_id = o.business_id
      order by created_at desc limit 1 for update;
    select * into v_plan from public.plans where id = (o.quote ->> 'plan_id')::uuid;
    update public.subscriptions
       set plan_id = v_plan.id, status = 'active',
           expiry_date = case when v_plan.billing = 'lifetime' then date '2099-12-31' else expiry_date end,
           grace_days = case when v_plan.billing = 'lifetime' then 0 else grace_days end
     where id = v_sub.id returning * into v_sub;
    perform public.set_plan_features(o.business_id, v_plan.id);
    perform public.refresh_business_ai(o.business_id);
    v_receipt := 'SR-' || to_char(v_today, 'YYMM') || '-'
                 || lpad(nextval('public.subscription_receipt_seq')::text, 4, '0');
    insert into public.subscription_payments
      (business_id, subscription_id, amount, payment_date, payment_mode, note, recorded_by,
       reference, period_start, period_end, plan_id, receipt_no, breakdown)
    values
      (o.business_id, v_sub.id, o.amount, v_today, v_mode::public.payment_mode, v_note, null, v_ref,
       v_today, v_sub.expiry_date, v_plan.id, v_receipt,
       jsonb_build_object('upgrade_from', o.quote ->> 'from_plan', 'plan', v_plan.name, 'billing', v_plan.billing,
                          'days_left', o.quote -> 'days_left', 'credit', o.quote -> 'credit', 'paid', o.amount))
    returning id into v_pay;
    perform public.admin_log(o.business_id, 'subscription.upgraded', 'subscription', v_sub.id::text,
      jsonb_build_object('from', o.quote ->> 'from_plan', 'to', v_plan.name, 'amount', o.amount, 'receipt', v_receipt));
    r := jsonb_build_object('payment_id', v_pay, 'receipt_no', v_receipt, 'expiry_date', v_sub.expiry_date);

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

-- ============================================================
-- The account page
-- ============================================================
create or replace function public.online_account(p_token text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_link public.pay_links;
  v_b public.businesses;
  v_sub public.subscriptions;
  v_plan public.plans;
  v_today date := public.ist_date(now());
  v_ups jsonb := '[]'::jsonb;
  q jsonb;
  p record;
begin
  select * into v_link from public.pay_links where token = p_token and expires_at > now();
  if v_link.token is null then return null; end if;
  select * into v_b from public.businesses where id = v_link.business_id;
  select * into v_sub from public.subscriptions where business_id = v_b.id order by created_at desc limit 1;
  select * into v_plan from public.plans where id = v_sub.plan_id;

  -- The upgrades this shop can buy now, with their price.
  for p in
    select p2.id, p2.name, p2.billing from public.plans p2 join public.software_products sp on sp.id = p2.software_id
     where sp.slug = 'dukania' and p2.is_active and not p2.is_trial and not coalesce(p2.is_custom, false)
       and p2.list_price > 0 and p2.id is distinct from v_plan.id
     order by p2.sort_order, p2.list_price
  loop
    begin
      q := public.online_quote(v_b.id, jsonb_build_object('kind', 'upgrade', 'plan_id', p.id));
      v_ups := v_ups || jsonb_build_array(jsonb_build_object('plan_id', p.id, 'plan', p.name, 'billing', p.billing,
                                                             'amount', q -> 'amount', 'until', q -> 'until'));
    exception when others then
      null;   -- not an upgrade for this shop
    end;
  end loop;

  return jsonb_build_object(
    'shop', v_b.name,
    'email', coalesce(nullif((select email from public.profiles where id = v_link.user_id), ''), v_b.email),
    'online_payments', public.online_payments_on(),
    'plan', case when v_plan.id is null then null else jsonb_build_object(
      'name', v_plan.name, 'billing', v_plan.billing, 'is_trial', v_plan.is_trial,
      'includes_ai', public.plan_includes_ai(v_plan.id),
      'status', v_sub.status, 'start', v_sub.start_date, 'expiry', v_sub.expiry_date,
      'days_left', v_sub.expiry_date - v_today,
      'active', v_sub.status = 'active' and v_sub.expiry_date >= v_today) end,
    'logins', jsonb_build_object(
      'limit', case when v_plan.user_limit is null then null else v_plan.user_limit + coalesce((
        select sum(a.quantity) from public.shop_addons a
         where a.business_id = v_b.id and a.kind = 'staff' and a.valid_until >= v_today), 0) end,
      'used', (select count(*) from public.profiles x where x.business_id = v_b.id)),
    'addons', coalesce((
      select jsonb_agg(jsonb_build_object('kind', a.kind, 'quantity', a.quantity, 'valid_until', a.valid_until)
                       order by a.valid_until)
      from public.shop_addons a where a.business_id = v_b.id and a.valid_until >= v_today), '[]'::jsonb),
    'payments', coalesce((
      select jsonb_agg(x order by x.payment_date desc, x.created_at desc) from (
        select s.payment_date, s.created_at, s.amount, s.receipt_no, s.payment_mode as mode, s.reference,
               coalesce(pl.name, '') as plan,
               case when s.breakdown ? 'upgrade_from' then 'upgrade'
                    when s.breakdown ? 'addon' then 'addon' else 'plan' end as kind,
               s.breakdown ->> 'addon' as addon
          from public.subscription_payments s left join public.plans pl on pl.id = s.plan_id
         where s.business_id = v_b.id and s.amount > 0
         order by s.payment_date desc, s.created_at desc limit 20) x), '[]'::jsonb),
    'upgrades', v_ups);
end $$;

revoke execute on function public.online_account(text) from public, anon, authenticated;
grant execute on function public.online_account(text) to service_role;
revoke execute on function public.online_quote(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.online_quote(uuid, jsonb) to service_role;
revoke execute on function public.online_order_paid(text, jsonb) from public, anon, authenticated;
grant execute on function public.online_order_paid(text, jsonb) to service_role;
revoke execute on function public.create_pay_link() from public, anon;
grant execute on function public.create_pay_link() to authenticated;
