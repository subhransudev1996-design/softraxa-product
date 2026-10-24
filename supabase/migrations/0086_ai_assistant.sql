-- ============================================================
-- 0086_ai_assistant.sql — Dukania AI: shops use ChatGPT / Claude.
--
-- The shop connector (supabase/functions/shop-mcp) runs every request with
-- the signed-in shop user's own login, so all the existing checks (own shop
-- only, staff permissions, plan features, subscription) apply unchanged.
-- This migration adds what decides WHO may use it, plus two read helpers:
--
--   1. Plan feature `ai_assistant` (feature_flags column, default OFF).
--      Unlike the other features it is never switched on by a plan with
--      no feature list ("all features"): a plan must tick it, or the admin
--      turns it on for one shop.
--   2. Staff permission `can_use_ai` (default off). Owners always may;
--      staff and managers only when the owner allows them.
--   3. ai_context(): may this user use the AI assistant, and if not why;
--      plus the shop, the user and what they are allowed to do.
--   4. ai_find_products(): product search for the AI, including low / out
--      of stock, with cost prices only for users who may see them.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Plan feature
-- ------------------------------------------------------------
alter table public.feature_flags add column if not exists ai_assistant boolean not null default false;

create or replace function public.app_feature_keys()
returns text[] language sql immutable as $$
  select array[
    'gst_billing', 'reports', 'pdf_invoice', 'a4_print', 'thermal_print',
    'offline_billing', 'expense_module', 'excel_import', 'service_module',
    'ai_assistant'
  ]
$$;

-- A plan with no feature list means "all features" — except the AI
-- assistant, which a plan must include by name.
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
end $$;

-- Offer it in the admin panel's plan editor.
update public.software_products
set features = features || '[{ "key": "ai_assistant", "label": "AI assistant (ChatGPT / Claude)" }]'::jsonb
where slug = 'dukania'
  and not exists (select 1 from jsonb_array_elements(features) f where f ->> 'key' = 'ai_assistant');

-- ------------------------------------------------------------
-- 2. Staff permission
-- ------------------------------------------------------------
alter table public.staff_permissions add column if not exists can_use_ai boolean not null default false;

create or replace function public.staff_permission_defaults()
returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'can_create_invoice', true,
    'can_edit_prices', false,
    'can_view_profit', false,
    'can_manage_products', true,
    'can_manage_stock', false,
    'can_manage_expenses', false,
    'can_manage_services', true,
    'can_view_reports', false,
    'can_manage_staff', false,
    'can_manage_purchases', false,
    'can_manage_returns', false,
    'can_edit_invoices', false,
    'can_record_payments', true,
    'can_manage_cash', false,
    'can_use_ai', false);
$$;

create or replace function public.permission_label(p_perm text)
returns text language sql immutable as $$
  select coalesce(jsonb_build_object(
    'can_create_invoice', 'create bills',
    'can_edit_prices', 'change prices or give discounts',
    'can_view_profit', 'view cost and profit',
    'can_manage_products', 'manage products',
    'can_manage_stock', 'adjust stock',
    'can_manage_expenses', 'manage expenses',
    'can_manage_services', 'manage services and job cards',
    'can_view_reports', 'view reports',
    'can_manage_purchases', 'manage purchases and suppliers',
    'can_manage_returns', 'process returns',
    'can_edit_invoices', 'edit or cancel bills',
    'can_record_payments', 'record payments',
    'can_manage_cash', 'manage the cash drawer and closing',
    'can_use_ai', 'use the AI assistant (ChatGPT / Claude)',
    'owner', 'do this (owner only)') ->> p_perm, p_perm);
$$;

-- Owner allows or stops one staff member using the AI assistant.
create or replace function public.set_staff_ai_permission(p_profile uuid, p_value boolean)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
begin
  perform public.assert_can('owner');
  if not exists (select 1 from public.profiles
                 where id = p_profile and business_id = v_business and role::text <> 'owner') then
    raise exception 'Staff member not found';
  end if;
  perform public.write_staff_permissions(p_profile, v_business, '{}'::jsonb);
  update public.staff_permissions set can_use_ai = coalesce(p_value, false), updated_at = now()
    where profile_id = p_profile;
  perform public.log_audit('staff.permissions_changed', 'profile', p_profile::text,
    jsonb_build_object('can_use_ai', coalesce(p_value, false)));
end $$;

-- ------------------------------------------------------------
-- 3. Who may use the AI assistant
-- ------------------------------------------------------------
-- allowed + reason (shown to the user as is), and the context the AI
-- needs: shop, user, permissions, features, subscription.
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
    v_reason := 'This is a SOFTRAXA admin account. Use the Dukania Admin connector instead.';
  elsif v_profile.business_id is null then
    v_reason := 'This account isn''t part of a shop yet. Finish setting up your shop in the Dukania app first.';
  elsif v_id is null then
    v_reason := 'Your shop''s plan has more staff than it allows, so this login is paused. Ask the shop owner.';
  elsif not coalesce(v_business.is_active, false) then
    v_reason := 'This shop is suspended. Contact SOFTRAXA support.';
  elsif not coalesce((select f.ai_assistant from public.feature_flags f where f.business_id = v_id), false) then
    v_reason := 'The AI assistant isn''t included in your shop''s plan. Contact SOFTRAXA to add it.';
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

-- ------------------------------------------------------------
-- 4. Product search for the AI
-- ------------------------------------------------------------
-- p_filter: 'all' | 'low' (at or below its low-stock level) | 'out' (none
-- left). p_search matches name, SKU, barcode (also of a variant).
create or replace function public.ai_find_products(
  p_search text default '', p_filter text default 'all', p_limit integer default 50
) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_cost     boolean := public.has_permission('can_view_profit');
  v_text     text := btrim(coalesce(p_search, ''));
  v_like     text;
  v_filter   text := coalesce(nullif(p_filter, ''), 'all');
  v_limit    integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_rows     jsonb;
  v_count    integer;
begin
  if v_business is null then raise exception 'No shop selected'; end if;
  if v_filter not in ('all', 'low', 'out') then raise exception 'Filter must be all, low or out'; end if;
  v_like := '%' || replace(replace(replace(lower(v_text), '\', '\\'), '%', '\%'), '_', '\_') || '%';

  with found as (
    select p.*
    from public.products p
    where p.business_id = v_business and p.is_active
      and (v_text = ''
           or lower(p.name) like v_like or lower(p.sku) like v_like or p.barcode = v_text
           or exists (select 1 from public.product_variants v
                      where v.product_id = p.id and v.is_active
                        and (v.barcode = v_text or lower(v.name) like v_like)))
      and case v_filter
            when 'low' then
              (p.low_stock_qty > 0 and p.current_stock <= p.low_stock_qty)
              or exists (select 1 from public.product_variants v
                         where v.product_id = p.id and v.is_active
                           and coalesce(v.low_stock_qty, p.low_stock_qty) > 0
                           and v.current_stock <= coalesce(v.low_stock_qty, p.low_stock_qty))
            when 'out' then
              p.current_stock <= 0
              or exists (select 1 from public.product_variants v
                         where v.product_id = p.id and v.is_active and v.current_stock <= 0)
            else true
          end
  ), page as (
    select * from found order by lower(name) limit v_limit
  )
  select (select count(*) from found),
         coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'id', p.id,
           'name', p.name,
           'barcode', nullif(p.barcode, ''),
           'sku', nullif(p.sku, ''),
           'category', c.name,
           'unit', u.name,
           'selling_price', p.selling_price,
           'mrp', nullif(p.mrp, 0),
           'wholesale_price', p.wholesale_price,
           'purchase_price', case when v_cost then p.purchase_price end,
           'gst_rate', p.gst_rate,
           'hsn', nullif(p.hsn_code, ''),
           'stock', p.current_stock,
           'low_stock_at', nullif(p.low_stock_qty, 0),
           'variants', case when p.has_variants then (
             select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                      'id', v.id, 'name', v.name, 'barcode', nullif(v.barcode, ''),
                      'selling_price', coalesce(v.selling_price, p.selling_price),
                      'purchase_price', case when v_cost then coalesce(v.purchase_price, p.purchase_price) end,
                      'stock', v.current_stock)) order by v.name)
             from public.product_variants v where v.product_id = p.id and v.is_active) end
         )) order by lower(p.name)), '[]'::jsonb)
    into v_count, v_rows
  from page p
  left join public.categories c on c.id = p.category_id
  left join public.units u on u.id = p.unit_id;

  return jsonb_build_object('total', v_count, 'shown', jsonb_array_length(v_rows), 'products', v_rows);
end $$;

revoke execute on function public.set_staff_ai_permission(uuid, boolean) from public, anon;
revoke execute on function public.ai_context() from public, anon;
revoke execute on function public.ai_find_products(text, text, integer) from public, anon;
grant execute on function public.set_staff_ai_permission(uuid, boolean) to authenticated;
grant execute on function public.ai_context() to authenticated;
grant execute on function public.ai_find_products(text, text, integer) to authenticated;
