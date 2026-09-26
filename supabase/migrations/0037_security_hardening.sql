-- ============================================================
-- 0037_security_hardening.sql — launch release R0, batch 1
-- (PROJECT_ANALYSIS.md findings 1–4, 13, 14, 16, 18 + key handling)
--
-- Principle: every rule is enforced in the database, so it holds for the
-- app, for direct API calls, and inside security-definer RPCs alike.
--
--   A. Helpers: request role, permission checks, writable-subscription check
--   B. Profiles: role/business_id can't be self-edited; owners can list staff
--   C. Businesses: only owners edit; is_active is admin-only
--   D. Tenant-consistency triggers: a row may only reference rows of its
--      own business (products, variants, customers, invoices, …)
--   E. Protected columns: stock totals and party balances change only
--      through the ledger / document RPCs; the stock ledger is append-only
--   F. Row-level security rebuilt per table with staff permissions
--   G. Document triggers: permission + subscription checks on invoices,
--      purchases, returns, payments, stock movements, job cards, expenses
--   H. Serial/IMEI integrity
--   I. Staff management: working staff logins, correct user limits
--   J. Admin-only plan RPCs, report permissions, internal helpers locked
--   K. ImageKit private key read from Supabase Vault (never from source)
--
-- Run AFTER 0036. Owner steps after running: see the end of this file.
-- ============================================================

-- ============================================================
-- A. Helpers
-- ============================================================

-- Role of the HTTP request ('anon' | 'authenticated' | 'service_role'),
-- or null for direct database sessions (SQL editor, migrations).
create or replace function public.request_role()
returns text language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'));
$$;

-- True when the current statement comes straight from an API client
-- (PostgREST runs as these roles). Inside a security-definer function
-- current_user is the function owner instead, so RPC-internal writes are
-- not "direct".
create or replace function public.is_direct_api_write()
returns boolean language sql stable as $$
  select current_user in ('authenticated', 'anon');
$$;

-- Default staff permissions when a staff member has no row yet.
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
    'can_record_payments', true);
$$;

-- Human-readable names for permission errors.
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
    'owner', 'do this (owner only)') ->> p_perm, p_perm);
$$;

-- Does the caller hold a permission?
--   ''       → any member of a business
--   'owner'  → the business owner (or a platform admin)
--   'can_*'  → owners always; staff per staff_permissions (or defaults)
-- Service-role and direct database sessions (no JWT user) are trusted.
create or replace function public.has_permission(p_perm text)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
  v_role     text;
  v_business uuid;
  v_perms    jsonb;
begin
  if auth.uid() is null then
    return coalesce(public.request_role(), '') not in ('anon', 'authenticated');
  end if;

  select role::text, business_id into v_role, v_business
    from public.profiles where id = auth.uid();
  if v_role is null then return false; end if;
  if v_role = 'admin' then return true; end if;
  if v_business is null then return false; end if;
  if coalesce(p_perm, '') = '' then return true; end if;
  if v_role = 'owner' then return true; end if;
  if p_perm = 'owner' then return false; end if;

  select to_jsonb(sp) into v_perms from public.staff_permissions sp where sp.profile_id = auth.uid();
  if v_perms is not null and v_perms ? p_perm then
    return coalesce((v_perms ->> p_perm)::boolean, false);
  end if;
  return coalesce((public.staff_permission_defaults() ->> p_perm)::boolean, false);
end $$;

-- Same rule the app uses for its blocked screen (AppContext.subscriptionState):
-- inactive business, suspended/expired status, or past expiry + grace days.
-- A business without any subscription row is writable.
create or replace function public.business_is_writable(p_business uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select b.is_active from public.businesses b where b.id = p_business), false)
     and coalesce((
       select not (s.status in ('expired', 'suspended')
                   or current_date > s.expiry_date + s.grace_days)
       from public.subscriptions s
       where s.business_id = p_business
       order by s.created_at desc limit 1), true);
$$;

-- Raise unless the caller holds p_perm. With p_write, also refuse when the
-- shop is read-only (expired/suspended). Payments pass p_write = false so a
-- lapsed shop can still collect money it is owed.
create or replace function public.assert_can(p_perm text, p_write boolean default true)
returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not public.has_permission(p_perm) then
    raise exception 'You don''t have permission to %', public.permission_label(p_perm)
      using errcode = '42501';
  end if;
  if p_write and auth.uid() is not null and not public.is_admin()
     and not public.business_is_writable(public.current_business_id()) then
    raise exception 'This shop''s subscription has expired or is suspended — renew it to continue'
      using errcode = '42501';
  end if;
end $$;

-- Plan feature switch for the caller's business (missing flag = on).
create or replace function public.feature_enabled(p_key text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((
    select (to_jsonb(f) ->> p_key)::boolean
    from public.feature_flags f where f.business_id = public.current_business_id()), true);
$$;

create or replace function public.assert_feature(p_key text, p_label text)
returns void language plpgsql stable as $$
begin
  if auth.uid() is not null and not public.is_admin() and not public.feature_enabled(p_key) then
    raise exception '% is not included in your plan', p_label using errcode = '42501';
  end if;
end $$;

-- ============================================================
-- B. Profiles
-- ============================================================
create or replace function public.guard_profile_columns()
returns trigger language plpgsql as $$
begin
  if public.is_direct_api_write() and not public.is_admin() then
    if new.id is distinct from old.id
       or new.role is distinct from old.role
       or new.business_id is distinct from old.business_id then
      raise exception 'Your role and business can''t be changed from the app'
        using errcode = '42501';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_profiles_guard on public.profiles;
create trigger trg_profiles_guard before update on public.profiles
  for each row execute function public.guard_profile_columns();

drop policy if exists "own profile update" on public.profiles;
create policy "own profile update" on public.profiles for update
  using (id = auth.uid() or public.is_admin())
  with check (id = auth.uid() or public.is_admin());

-- Finding 13: owners can list the staff of their own business.
drop policy if exists "owner reads business profiles" on public.profiles;
create policy "owner reads business profiles" on public.profiles for select
  using (business_id = (select public.current_business_id())
         and (select public.has_permission('owner')));

-- ============================================================
-- C. Businesses
-- ============================================================
create or replace function public.guard_business_columns()
returns trigger language plpgsql as $$
begin
  if public.is_direct_api_write() and not public.is_admin() then
    if new.id is distinct from old.id or new.is_active is distinct from old.is_active then
      raise exception 'Only SOFTRAXA can activate or deactivate a business'
        using errcode = '42501';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_businesses_guard on public.businesses;
create trigger trg_businesses_guard before update on public.businesses
  for each row execute function public.guard_business_columns();

drop policy if exists "own business update" on public.businesses;
create policy "own business update" on public.businesses for update
  using (id = (select public.current_business_id()) and (select public.has_permission('owner')))
  with check (id = (select public.current_business_id()) and (select public.has_permission('owner')));

-- ============================================================
-- D. Tenant-consistency triggers (finding 2)
-- TG_ARGV entries are 'column=table'. Every referenced row must carry the
-- same business_id; a variant must also belong to the row's product.
-- ============================================================
create or replace function public.enforce_tenant_refs()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_row   jsonb := to_jsonb(new);
  v_arg   text;
  v_col   text;
  v_tab   text;
  v_val   uuid;
  v_owner uuid;
begin
  foreach v_arg in array tg_argv loop
    v_col := split_part(v_arg, '=', 1);
    v_tab := split_part(v_arg, '=', 2);
    v_val := nullif(v_row ->> v_col, '')::uuid;
    if v_val is not null then
      execute format('select business_id from public.%I where id = $1', v_tab)
        into v_owner using v_val;
      if v_owner is null or v_owner <> new.business_id then
        raise exception 'Invalid reference: % does not belong to this business', v_col
          using errcode = '42501';
      end if;
    end if;
  end loop;

  if v_row ? 'variant_id' and v_row ? 'product_id'
     and nullif(v_row ->> 'variant_id', '') is not null
     and nullif(v_row ->> 'product_id', '') is not null then
    if not exists (select 1 from public.product_variants
                   where id = (v_row ->> 'variant_id')::uuid
                     and product_id = (v_row ->> 'product_id')::uuid) then
      raise exception 'Invalid reference: variant does not belong to the product'
        using errcode = '42501';
    end if;
  end if;
  return new;
end $$;

do $$
declare
  r record;
begin
  for r in select * from (values
    ('products',              'category_id=categories,brand_id=brands,unit_id=units'),
    ('product_variants',      'product_id=products'),
    ('product_serials',       'product_id=products,variant_id=product_variants,invoice_id=invoices,purchase_id=purchases'),
    ('customer_payments',     'customer_id=customers,invoice_id=invoices'),
    ('supplier_payments',     'supplier_id=suppliers,purchase_id=purchases'),
    ('invoices',              'customer_id=customers'),
    ('invoice_items',         'invoice_id=invoices,product_id=products,variant_id=product_variants'),
    ('invoice_payments',      'invoice_id=invoices'),
    ('sale_returns',          'invoice_id=invoices,customer_id=customers'),
    ('sale_return_items',     'sale_return_id=sale_returns,product_id=products,variant_id=product_variants'),
    ('purchases',             'supplier_id=suppliers'),
    ('purchase_items',        'purchase_id=purchases,product_id=products,variant_id=product_variants'),
    ('purchase_returns',      'purchase_id=purchases,supplier_id=suppliers'),
    ('purchase_return_items', 'purchase_return_id=purchase_returns,product_id=products,variant_id=product_variants'),
    ('stock_movements',       'product_id=products,variant_id=product_variants'),
    ('expenses',              'category_id=expense_categories'),
    ('job_cards',             'customer_id=customers,invoice_id=invoices'),
    ('job_card_items',        'job_card_id=job_cards,product_id=products,variant_id=product_variants,service_id=services'),
    ('job_status_history',    'job_card_id=job_cards'),
    ('stock_pieces',          'product_id=products,variant_id=product_variants'),
    ('staff_permissions',     'profile_id=profiles'),
    ('device_tokens',         'user_id=profiles')
  ) as t(tbl, refs) loop
    execute format('drop trigger if exists trg_00_tenant_refs on public.%I', r.tbl);
    execute format(
      'create trigger trg_00_tenant_refs before insert or update on public.%I
         for each row execute function public.enforce_tenant_refs(%s)',
      r.tbl,
      (select string_agg(quote_literal(x), ', ') from unnest(string_to_array(r.refs, ',')) x));
  end loop;
end $$;

-- ============================================================
-- E. Protected columns + append-only stock ledger (findings 2, 18)
-- ============================================================

-- Stock ledger: scope the stock update to the movement's own business too.
create or replace function public.apply_stock_movement()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.variant_id is not null then
    update public.product_variants
      set current_stock = current_stock + new.quantity
      where id = new.variant_id and business_id = new.business_id;
    update public.products
      set current_stock = current_stock + new.quantity
      where id = new.product_id and business_id = new.business_id;
  else
    update public.products
      set current_stock = current_stock + new.quantity
      where id = new.product_id and business_id = new.business_id;
  end if;
  return new;
end $$;

-- current_stock is derived from the ledger. API clients can't set it.
create or replace function public.guard_stock_columns()
returns trigger language plpgsql as $$
begin
  if public.is_direct_api_write() then
    if tg_op = 'INSERT' then
      new.current_stock := 0;
    elsif new.current_stock is distinct from old.current_stock then
      raise exception 'Stock can only change through bills, purchases or stock adjustments'
        using errcode = '42501';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_products_stock_guard on public.products;
create trigger trg_products_stock_guard before insert or update on public.products
  for each row execute function public.guard_stock_columns();
drop trigger if exists trg_variants_stock_guard on public.product_variants;
create trigger trg_variants_stock_guard before insert or update on public.product_variants
  for each row execute function public.guard_stock_columns();

-- Party balances (due_amount) change only through documents and payments.
-- Credit limits are owner-only (PD17). Runs before normalize_customer_credit.
create or replace function public.guard_party_columns()
returns trigger language plpgsql as $$
begin
  if public.is_direct_api_write() then
    if tg_op = 'INSERT' then
      new.due_amount := 0;
    elsif new.due_amount is distinct from old.due_amount then
      raise exception 'Balances can only change through bills, purchases and payments'
        using errcode = '42501';
    end if;
  end if;

  if tg_table_name = 'customers' and auth.uid() is not null
     and not public.has_permission('owner') then
    if tg_op = 'INSERT' then
      new.credit_unlimited := false;
      new.credit_limit := null;          -- store default, via normalize_customer_credit
    elsif new.credit_limit is distinct from old.credit_limit
       or new.credit_unlimited is distinct from old.credit_unlimited then
      raise exception 'Only the owner can change credit limits' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_customers_a_guard on public.customers;
create trigger trg_customers_a_guard before insert or update on public.customers
  for each row execute function public.guard_party_columns();
drop trigger if exists trg_suppliers_a_guard on public.suppliers;
create trigger trg_suppliers_a_guard before insert or update on public.suppliers
  for each row execute function public.guard_party_columns();

-- ============================================================
-- F. Row-level security per table (findings 4, 16, 18)
--   read  : '' = any member, else the permission needed to read
--   write : '' = any member, 'none' = RPC-only (no direct API writes)
-- Direct writes also require a writable (non-expired) subscription.
-- ============================================================
do $$
declare
  r        record;
  v_tenant text := 'business_id = (select public.current_business_id())';
  v_read   text;
  v_write  text;
begin
  for r in select * from (values
    ('categories',            '',                     'can_manage_products'),
    ('brands',                '',                     'can_manage_products'),
    ('units',                 '',                     'can_manage_products'),
    ('products',              '',                     'can_manage_products'),
    ('product_variants',      '',                     'can_manage_products'),
    ('product_serials',       '',                     'can_manage_products'),
    ('customers',             '',                     ''),
    ('customer_payments',     '',                     'none'),
    ('suppliers',             '',                     'can_manage_purchases'),
    ('supplier_payments',     'can_manage_purchases', 'none'),
    ('invoices',              '',                     'none'),
    ('invoice_items',         '',                     'none'),
    ('invoice_payments',      '',                     'none'),
    ('sale_returns',          '',                     'none'),
    ('sale_return_items',     '',                     'none'),
    ('purchases',             'can_manage_purchases', 'none'),
    ('purchase_items',        'can_manage_purchases', 'none'),
    ('purchase_returns',      'can_manage_purchases', 'none'),
    ('purchase_return_items', 'can_manage_purchases', 'none'),
    ('stock_movements',       '',                     'none'),
    ('expense_categories',    'can_manage_expenses',  'can_manage_expenses'),
    ('expenses',              'can_manage_expenses',  'can_manage_expenses'),
    ('services',              '',                     'can_manage_services'),
    ('job_cards',             '',                     'can_manage_services'),
    ('job_card_items',        '',                     'can_manage_services'),
    ('job_status_history',    '',                     'none'),
    ('stock_pieces',          '',                     'can_manage_stock')
  ) as t(tbl, read_perm, write_perm) loop
    execute format('drop policy if exists "tenant all" on public.%I', r.tbl);
    execute format('drop policy if exists "tenant read" on public.%I', r.tbl);
    execute format('drop policy if exists "tenant insert" on public.%I', r.tbl);
    execute format('drop policy if exists "tenant update" on public.%I', r.tbl);
    execute format('drop policy if exists "tenant delete" on public.%I', r.tbl);
    execute format('drop policy if exists "admin all" on public.%I', r.tbl);

    v_read := v_tenant || case when r.read_perm = '' then ''
      else format(' and (select public.has_permission(%L))', r.read_perm) end;
    execute format('create policy "tenant read" on public.%I for select using (%s)', r.tbl, v_read);

    if r.write_perm <> 'none' then
      v_write := v_tenant
        || case when r.write_perm = '' then ''
             else format(' and (select public.has_permission(%L))', r.write_perm) end
        || ' and (select public.business_is_writable(public.current_business_id()))';
      execute format('create policy "tenant insert" on public.%I for insert with check (%s)', r.tbl, v_write);
      execute format('create policy "tenant update" on public.%I for update using (%s) with check (%s)', r.tbl, v_write, v_write);
      execute format('create policy "tenant delete" on public.%I for delete using (%s)', r.tbl, v_write);
    end if;

    -- Platform admins keep full access, except to rewrite the stock ledger.
    if r.tbl = 'stock_movements' then
      execute format('create policy "admin all" on public.%I for select using (public.is_admin())', r.tbl);
    else
      execute format('create policy "admin all" on public.%I for all using (public.is_admin()) with check (public.is_admin())', r.tbl);
    end if;
  end loop;
end $$;

-- Customers: members add/edit, only owners delete.
drop policy if exists "tenant delete" on public.customers;
create policy "tenant delete" on public.customers for delete
  using (business_id = (select public.current_business_id())
         and (select public.has_permission('owner')));

-- Device tokens: each user manages only their own device rows.
drop policy if exists "tenant all" on public.device_tokens;
drop policy if exists "own device tokens" on public.device_tokens;
create policy "own device tokens" on public.device_tokens for all
  using ((business_id = (select public.current_business_id()) and user_id = auth.uid()) or public.is_admin())
  with check ((business_id = (select public.current_business_id()) and user_id = auth.uid()) or public.is_admin());

-- The stock ledger is append-only for everyone but the database owner.
revoke update, delete on public.stock_movements from anon, authenticated;

-- ============================================================
-- G. Document triggers — permission + subscription checks that also
-- apply inside security-definer RPCs (auth.uid() is still the caller).
-- ============================================================

-- Price guard (can_edit_prices): a line may not go below the catalogue
-- price (variant price, else product price; wholesale price once its
-- minimum quantity is reached). Prices are compared per base unit and,
-- for GST invoices, tax-inclusive — the same basis the POS uses.
create or replace function public.check_line_price(
  p_product uuid, p_variant uuid, p_qty numeric, p_unit_price numeric,
  p_discount numeric, p_gst_rate numeric, p_inclusive boolean, p_name text)
returns void language plpgsql stable security definer set search_path = public as $$
declare
  v_list     numeric;
  v_ws       numeric;
  v_ws_min   numeric;
  v_eff      numeric;
begin
  if p_product is null or coalesce(p_qty, 0) <= 0 or public.has_permission('can_edit_prices') then
    return;
  end if;
  select coalesce(v.selling_price, p.selling_price), p.wholesale_price, p.wholesale_min_qty
    into v_list, v_ws, v_ws_min
    from public.products p
    left join public.product_variants v on v.id = p_variant and v.product_id = p.id
    where p.id = p_product;
  if v_list is null or v_list <= 0 then return; end if;
  if v_ws is not null and v_ws > 0 and v_ws_min is not null and p_qty >= v_ws_min then
    v_list := least(v_list, v_ws);
  end if;
  v_eff := (p_qty * p_unit_price - coalesce(p_discount, 0)) / p_qty;
  if p_inclusive then v_eff := v_eff * (1 + coalesce(p_gst_rate, 0) / 100); end if;
  if v_eff < v_list - 0.05 then
    raise exception 'The price of % is below its list price (%) — you don''t have permission to change prices',
      coalesce(p_name, 'this item'), round(v_list, 2) using errcode = '42501';
  end if;
end $$;

create or replace function public.guard_invoices()
returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    perform public.assert_can('can_create_invoice');
    if new.invoice_type = 'gst' then
      perform public.assert_feature('gst_billing', 'GST billing');
    end if;
    if new.discount_amount > 0 and not public.has_permission('can_edit_prices') then
      raise exception 'You don''t have permission to give discounts' using errcode = '42501';
    end if;
    return new;
  end if;

  -- UPDATE
  if row(new.business_id, new.invoice_no, new.invoice_type, new.invoice_date, new.customer_id,
         new.subtotal, new.discount_amount, new.tax_amount, new.round_off, new.total,
         new.is_cancelled, new.notes)
     is distinct from
     row(old.business_id, old.invoice_no, old.invoice_type, old.invoice_date, old.customer_id,
         old.subtotal, old.discount_amount, old.tax_amount, old.round_off, old.total,
         old.is_cancelled, old.notes) then
    perform public.assert_can('can_edit_invoices');
    if new.discount_amount > old.discount_amount and not public.has_permission('can_edit_prices') then
      raise exception 'You don''t have permission to give discounts' using errcode = '42501';
    end if;
  elsif new.place_of_supply is distinct from old.place_of_supply then
    perform public.assert_can('can_create_invoice');
  elsif new.paid_amount is distinct from old.paid_amount
     or new.payment_status is distinct from old.payment_status then
    perform public.assert_can('can_record_payments', false);
  end if;
  return new;
end $$;

drop trigger if exists trg_invoices_guard on public.invoices;
create trigger trg_invoices_guard before insert or update on public.invoices
  for each row execute function public.guard_invoices();

create or replace function public.guard_invoice_items()
returns trigger language plpgsql as $$
declare
  v_type public.invoice_type;
begin
  if tg_op = 'DELETE' then
    perform public.assert_can('can_edit_invoices');
    return old;
  end if;
  -- New bills need create permission; re-inserting lines while editing a
  -- bill (update_invoice) is covered by edit permission.
  if public.has_permission('can_create_invoice') then
    perform public.assert_can('can_create_invoice');
  else
    perform public.assert_can('can_edit_invoices');
  end if;
  select invoice_type into v_type from public.invoices where id = new.invoice_id;
  perform public.check_line_price(new.product_id, new.variant_id, new.quantity, new.unit_price,
    new.discount_amount, new.gst_rate, v_type = 'gst', new.product_name);
  return new;
end $$;

drop trigger if exists trg_invoice_items_guard on public.invoice_items;
create trigger trg_invoice_items_guard before insert or delete on public.invoice_items
  for each row execute function public.guard_invoice_items();

create or replace function public.guard_invoice_payments()
returns trigger language plpgsql as $$
begin
  if not (public.has_permission('can_create_invoice') or public.has_permission('can_record_payments')) then
    perform public.assert_can('can_record_payments', false);
  end if;
  return new;
end $$;

drop trigger if exists trg_invoice_payments_guard on public.invoice_payments;
create trigger trg_invoice_payments_guard before insert on public.invoice_payments
  for each row execute function public.guard_invoice_payments();

-- Generic "this table needs permission X" guard. TG_ARGV[0] = permission,
-- TG_ARGV[1] = 'write' (subscription must be active) or 'payment'.
create or replace function public.guard_by_permission()
returns trigger language plpgsql as $$
begin
  perform public.assert_can(tg_argv[0], coalesce(tg_argv[1], 'write') = 'write');
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;

drop trigger if exists trg_customer_payments_guard on public.customer_payments;
create trigger trg_customer_payments_guard before insert on public.customer_payments
  for each row execute function public.guard_by_permission('can_record_payments', 'payment');

drop trigger if exists trg_supplier_payments_guard on public.supplier_payments;
create trigger trg_supplier_payments_guard before insert on public.supplier_payments
  for each row execute function public.guard_by_permission('can_manage_purchases', 'payment');

drop trigger if exists trg_sale_returns_guard on public.sale_returns;
create trigger trg_sale_returns_guard before insert on public.sale_returns
  for each row execute function public.guard_by_permission('can_manage_returns', 'write');

drop trigger if exists trg_purchase_returns_guard on public.purchase_returns;
create trigger trg_purchase_returns_guard before insert on public.purchase_returns
  for each row execute function public.guard_by_permission('can_manage_purchases', 'write');

create or replace function public.guard_purchases()
returns trigger language plpgsql as $$
begin
  if tg_op = 'UPDATE'
     and row(new.subtotal, new.discount_amount, new.tax_amount, new.extra_charges, new.round_off,
             new.total, new.supplier_id, new.purchase_date, new.bill_no)
         is not distinct from
         row(old.subtotal, old.discount_amount, old.tax_amount, old.extra_charges, old.round_off,
             old.total, old.supplier_id, old.purchase_date, old.bill_no) then
    perform public.assert_can('can_manage_purchases', false);   -- payment-only change
  else
    perform public.assert_can('can_manage_purchases');
  end if;
  return new;
end $$;

drop trigger if exists trg_purchases_guard on public.purchases;
create trigger trg_purchases_guard before insert or update on public.purchases
  for each row execute function public.guard_purchases();

-- Manual stock movements (no source document) need stock permission.
-- Opening stock is allowed with product permission only while that
-- product/variant has no stock history yet (i.e. right after creating it).
create or replace function public.guard_stock_movements()
returns trigger language plpgsql as $$
begin
  if new.reference_type is null then
    if new.movement_type in ('opening', 'import')
       and not exists (select 1 from public.stock_movements m
                       where m.product_id = new.product_id
                         and m.variant_id is not distinct from new.variant_id) then
      if not public.has_permission('can_manage_products') then
        perform public.assert_can('can_manage_stock');
      else
        perform public.assert_can('can_manage_products');
      end if;
    else
      perform public.assert_can('can_manage_stock');
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_stock_movements_guard on public.stock_movements;
create trigger trg_stock_movements_guard before insert on public.stock_movements
  for each row execute function public.guard_stock_movements();

-- Job cards (service module): permission, plan feature, subscription.
create or replace function public.guard_job_cards()
returns trigger language plpgsql as $$
begin
  perform public.assert_can('can_manage_services');
  if tg_op = 'DELETE' then return old; end if;
  -- Nested IFs: NEW's fields differ between job_cards and job_card_items,
  -- and PL/pgSQL only plans a field reference when the branch runs.
  if tg_table_name = 'job_cards' then
    if tg_op = 'INSERT' then
      perform public.assert_feature('service_module', 'Services & job cards');
    end if;
  else
    if new.item_type = 'part' then
      perform public.check_line_price(new.product_id, new.variant_id, new.quantity, new.unit_price,
        0, new.gst_rate, coalesce(new.gst_rate, 0) > 0, new.name);
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_job_cards_guard on public.job_cards;
create trigger trg_job_cards_guard before insert or update on public.job_cards
  for each row execute function public.guard_job_cards();
drop trigger if exists trg_job_card_items_guard on public.job_card_items;
create trigger trg_job_card_items_guard before insert or update or delete on public.job_card_items
  for each row execute function public.guard_job_cards();

create or replace function public.guard_expenses()
returns trigger language plpgsql as $$
begin
  perform public.assert_can('can_manage_expenses');
  perform public.assert_feature('expense_module', 'Expense tracking');
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;

drop trigger if exists trg_expenses_guard on public.expenses;
create trigger trg_expenses_guard before insert or update or delete on public.expenses
  for each row execute function public.guard_expenses();

-- Place of supply is changed through this RPC (not a direct table write).
create or replace function public.set_invoice_place_of_supply(p_invoice_id uuid, p_state text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.invoices set place_of_supply = coalesce(p_state, '')
    where id = p_invoice_id and business_id = public.current_business_id() and not is_cancelled;
  if not found then raise exception 'Invoice not found'; end if;
end $$;

-- Cutting a piece at the counter: billing staff may only shorten a piece
-- (editing or scrapping pieces otherwise needs stock permission).
create or replace function public.apply_piece_cut(p_piece_id uuid, p_cut numeric)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_piece record;
  v_left  numeric;
begin
  perform public.assert_can('can_create_invoice');
  if p_cut is null or p_cut <= 0 then raise exception 'Cut length must be positive'; end if;
  select * into v_piece from public.stock_pieces
    where id = p_piece_id and business_id = public.current_business_id() for update;
  if v_piece.id is null then raise exception 'Piece not found'; end if;
  if v_piece.status <> 'available' then raise exception 'Piece is no longer available'; end if;
  if p_cut > v_piece.length + 0.0005 then raise exception 'Cut is longer than the piece'; end if;
  v_left := greatest(v_piece.length - p_cut, 0);
  update public.stock_pieces
     set length = case when v_left <= 0.0005 then v_piece.length else v_left end,
         status = case when v_left <= 0.0005 then 'consumed' else status end
   where id = p_piece_id;
end $$;

-- Push tokens: a device that switches accounts moves its token to the
-- signed-in user (the own-rows RLS policy would otherwise block the upsert).
create or replace function public.register_device_token(p_token text, p_platform text default 'android')
returns void language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
begin
  if auth.uid() is null or v_business is null then raise exception 'Not signed in'; end if;
  if coalesce(trim(p_token), '') = '' then raise exception 'Missing token'; end if;
  insert into public.device_tokens (business_id, user_id, token, platform, updated_at)
  values (v_business, auth.uid(), p_token, coalesce(p_platform, 'android'), now())
  on conflict (token) do update
    set business_id = excluded.business_id, user_id = excluded.user_id,
        platform = excluded.platform, updated_at = now();
end $$;

-- ============================================================
-- H. Serial / IMEI integrity (finding 15)
-- ============================================================
create or replace function public.guard_product_serials()
returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    if public.is_direct_api_write() and new.status <> 'in_stock' then
      raise exception 'New serial numbers must start in stock' using errcode = '42501';
    end if;
    return new;
  end if;

  -- A sold serial comes back only through a reversal that clears its
  -- invoice (bill edit/cancel) or a sale return — never by re-importing it.
  if old.status = 'sold' and new.status = 'in_stock' and new.invoice_id is not null then
    raise exception 'Serial % is already sold — record a sale return before adding it again',
      old.serial_no using errcode = '23505';
  end if;

  -- Re-adding an in-stock serial must not move it to another product.
  if old.status = 'in_stock' and new.status = 'in_stock'
     and (new.product_id is distinct from old.product_id
          or new.variant_id is distinct from old.variant_id) then
    raise exception 'Serial % is already in stock for another product', old.serial_no
      using errcode = '23505';
  end if;

  -- Selling: the serial must be available and match the product on the bill.
  if new.status = 'sold' and old.status is distinct from 'sold' then
    if old.status not in ('in_stock', 'returned') then
      raise exception 'Serial % is not available for sale', old.serial_no using errcode = '23505';
    end if;
    if new.invoice_id is not null and not exists (
         select 1 from public.invoice_items ii
         where ii.invoice_id = new.invoice_id and ii.serial_no = new.serial_no
           and ii.product_id = new.product_id) then
      raise exception 'Serial % belongs to a different product', old.serial_no using errcode = '23505';
    end if;
  elsif new.status = 'sold' and old.status = 'sold'
        and new.invoice_id is distinct from old.invoice_id then
    raise exception 'Serial % is already sold', old.serial_no using errcode = '23505';
  end if;
  return new;
end $$;

drop trigger if exists trg_product_serials_guard on public.product_serials;
create trigger trg_product_serials_guard before insert or update on public.product_serials
  for each row execute function public.guard_product_serials();

-- Import helper: skip serials already registered for this product, reject
-- conflicts with a clear message instead of silently resetting them.
create or replace function public.add_product_serials(
  p_product_id uuid,
  p_variant_id uuid default null,
  p_serials    text[] default array[]::text[],
  p_purchase_id uuid default null
)
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_s        text;
  v_existing record;
  v_count    integer := 0;
begin
  if v_business is null then raise exception 'Not authenticated or missing business'; end if;
  perform public.assert_can('can_manage_products');
  if not exists (select 1 from public.products where id = p_product_id and business_id = v_business) then
    raise exception 'Product not found';
  end if;

  foreach v_s in array p_serials loop
    v_s := trim(v_s);
    continue when v_s = '';
    select * into v_existing from public.product_serials
      where business_id = v_business and serial_no = v_s for update;
    if v_existing.id is null then
      insert into public.product_serials
        (business_id, product_id, variant_id, serial_no, status, purchase_id)
      values (v_business, p_product_id, p_variant_id, v_s, 'in_stock', p_purchase_id);
      v_count := v_count + 1;
    elsif v_existing.product_id = p_product_id
          and v_existing.variant_id is not distinct from p_variant_id
          and v_existing.status in ('in_stock', 'returned') then
      update public.product_serials set status = 'in_stock',
             purchase_id = coalesce(p_purchase_id, purchase_id)
        where id = v_existing.id;
    else
      raise exception 'Serial % is already registered (%)', v_s, v_existing.status
        using errcode = '23505';
    end if;
  end loop;
  return v_count;
end $$;

-- ============================================================
-- I. Staff management (findings 4, 13, 14)
-- ============================================================
alter table public.staff_permissions add column if not exists can_manage_purchases boolean not null default false;
alter table public.staff_permissions add column if not exists can_manage_returns   boolean not null default false;
alter table public.staff_permissions add column if not exists can_edit_invoices    boolean not null default false;
alter table public.staff_permissions add column if not exists can_record_payments  boolean not null default true;

-- Staff read only their own row; owners manage their business's rows.
drop policy if exists "Users can view staff permissions in their business" on public.staff_permissions;
drop policy if exists "Owners can manage staff permissions" on public.staff_permissions;
drop policy if exists "staff read own permissions" on public.staff_permissions;
drop policy if exists "owner manage staff permissions" on public.staff_permissions;
create policy "staff read own permissions" on public.staff_permissions for select
  using (profile_id = auth.uid() or public.is_admin()
         or (business_id = (select public.current_business_id()) and (select public.has_permission('owner'))));
create policy "owner manage staff permissions" on public.staff_permissions for all
  using ((business_id = (select public.current_business_id()) and (select public.has_permission('owner'))) or public.is_admin())
  with check ((business_id = (select public.current_business_id()) and (select public.has_permission('owner'))) or public.is_admin());

-- Staff login limit for a business: plan user_limit, NULL = unlimited;
-- no subscription or no plan = owner only (1). Returns NULL for unlimited.
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
  if not coalesce(v_found, false) or v_plan is null then return 1; end if;
  return v_limit;   -- NULL = unlimited
end $$;

create or replace function public.write_staff_permissions(p_profile uuid, p_business uuid, p jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  d jsonb := public.staff_permission_defaults();
begin
  insert into public.staff_permissions (
    profile_id, business_id,
    can_create_invoice, can_edit_prices, can_view_profit, can_manage_products, can_manage_stock,
    can_manage_expenses, can_manage_services, can_view_reports, can_manage_staff,
    can_manage_purchases, can_manage_returns, can_edit_invoices, can_record_payments)
  values (
    p_profile, p_business,
    coalesce((p ->> 'can_create_invoice')::boolean,   (d ->> 'can_create_invoice')::boolean),
    coalesce((p ->> 'can_edit_prices')::boolean,      (d ->> 'can_edit_prices')::boolean),
    coalesce((p ->> 'can_view_profit')::boolean,      (d ->> 'can_view_profit')::boolean),
    coalesce((p ->> 'can_manage_products')::boolean,  (d ->> 'can_manage_products')::boolean),
    coalesce((p ->> 'can_manage_stock')::boolean,     (d ->> 'can_manage_stock')::boolean),
    coalesce((p ->> 'can_manage_expenses')::boolean,  (d ->> 'can_manage_expenses')::boolean),
    coalesce((p ->> 'can_manage_services')::boolean,  (d ->> 'can_manage_services')::boolean),
    coalesce((p ->> 'can_view_reports')::boolean,     (d ->> 'can_view_reports')::boolean),
    false,  -- staff management is owner-only at launch
    coalesce((p ->> 'can_manage_purchases')::boolean, (d ->> 'can_manage_purchases')::boolean),
    coalesce((p ->> 'can_manage_returns')::boolean,   (d ->> 'can_manage_returns')::boolean),
    coalesce((p ->> 'can_edit_invoices')::boolean,    (d ->> 'can_edit_invoices')::boolean),
    coalesce((p ->> 'can_record_payments')::boolean,  (d ->> 'can_record_payments')::boolean))
  on conflict (profile_id) do update set
    can_create_invoice   = coalesce((p ->> 'can_create_invoice')::boolean,   staff_permissions.can_create_invoice),
    can_edit_prices      = coalesce((p ->> 'can_edit_prices')::boolean,      staff_permissions.can_edit_prices),
    can_view_profit      = coalesce((p ->> 'can_view_profit')::boolean,      staff_permissions.can_view_profit),
    can_manage_products  = coalesce((p ->> 'can_manage_products')::boolean,  staff_permissions.can_manage_products),
    can_manage_stock     = coalesce((p ->> 'can_manage_stock')::boolean,     staff_permissions.can_manage_stock),
    can_manage_expenses  = coalesce((p ->> 'can_manage_expenses')::boolean,  staff_permissions.can_manage_expenses),
    can_manage_services  = coalesce((p ->> 'can_manage_services')::boolean,  staff_permissions.can_manage_services),
    can_view_reports     = coalesce((p ->> 'can_view_reports')::boolean,     staff_permissions.can_view_reports),
    can_manage_staff     = false,
    can_manage_purchases = coalesce((p ->> 'can_manage_purchases')::boolean, staff_permissions.can_manage_purchases),
    can_manage_returns   = coalesce((p ->> 'can_manage_returns')::boolean,   staff_permissions.can_manage_returns),
    can_edit_invoices    = coalesce((p ->> 'can_edit_invoices')::boolean,    staff_permissions.can_edit_invoices),
    can_record_payments  = coalesce((p ->> 'can_record_payments')::boolean,  staff_permissions.can_record_payments),
    updated_at           = now();
end $$;

-- Staff login creation. Writes a complete GoTrue user + identity so the
-- staff member can sign in with email/password (the 0034 version left the
-- token columns NULL and skipped auth.identities, which blocks sign-in).
create or replace function public.create_staff_user(
  p_email text,
  p_password text,
  p_full_name text,
  p_permissions jsonb default '{}'::jsonb
)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_business uuid := public.current_business_id();
  v_email    text := lower(trim(p_email));
  v_limit    integer;
  v_count    integer;
  v_user_id  uuid := gen_random_uuid();
  v_now      timestamptz := now();
begin
  if v_business is null or not public.has_permission('owner') then
    raise exception 'Only the store owner can add staff' using errcode = '42501';
  end if;
  perform public.assert_can('owner');
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Enter a valid email address'; end if;
  if length(coalesce(p_password, '')) < 8 then raise exception 'Password must be at least 8 characters'; end if;
  if coalesce(trim(p_full_name), '') = '' then raise exception 'Enter the staff member''s name'; end if;

  -- Serialise staff additions per business so two requests can't both pass the limit.
  perform 1 from public.businesses where id = v_business for update;

  v_limit := public.business_user_limit(v_business);
  select count(*) into v_count from public.profiles where business_id = v_business;
  if v_limit is not null and v_count >= v_limit then
    raise exception 'Staff limit reached (% users allowed on your plan). Upgrade your plan to add more staff.', v_limit;
  end if;

  if exists (select 1 from auth.users where lower(email) = v_email) then
    raise exception 'An account with this email already exists';
  end if;

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change, email_change_token_new)
  values (
    '00000000-0000-0000-0000-000000000000', v_user_id, 'authenticated', 'authenticated',
    v_email, crypt(p_password, gen_salt('bf')), v_now,
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('full_name', trim(p_full_name)), v_now, v_now,
    '', '', '', '');

  -- auth.identities changed shape across GoTrue versions (provider_id added).
  if exists (select 1 from information_schema.columns
             where table_schema = 'auth' and table_name = 'identities' and column_name = 'provider_id') then
    execute 'insert into auth.identities
               (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
             values ($1::text, $1, $2, ''email'', $3, $3, $3)'
      using v_user_id,
            jsonb_build_object('sub', v_user_id::text, 'email', v_email, 'email_verified', true),
            v_now;
  else
    execute 'insert into auth.identities
               (id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
             values ($1::text, $1, $2, ''email'', $3, $3, $3)'
      using v_user_id,
            jsonb_build_object('sub', v_user_id::text, 'email', v_email),
            v_now;
  end if;

  -- handle_new_user created the profile as 'owner'; make it staff of this shop.
  update public.profiles
     set business_id = v_business, role = 'staff', full_name = trim(p_full_name), email = v_email
   where id = v_user_id;

  perform public.write_staff_permissions(v_user_id, v_business, coalesce(p_permissions, '{}'::jsonb));
  perform public.log_audit('staff.created', 'profile', v_user_id::text,
    jsonb_build_object('email', v_email, 'permissions', p_permissions));
  return jsonb_build_object('user_id', v_user_id, 'email', v_email);
end $$;

create or replace function public.update_staff_permissions(p_profile_id uuid, p_permissions jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_target   record;
begin
  if v_business is null or not public.has_permission('owner') then
    raise exception 'Only the store owner can change staff permissions' using errcode = '42501';
  end if;
  select * into v_target from public.profiles where id = p_profile_id;
  if v_target.id is null or v_target.business_id is distinct from v_business
     or v_target.role::text not in ('staff', 'manager') then
    raise exception 'Staff member not found in your store';
  end if;
  perform public.write_staff_permissions(p_profile_id, v_business, coalesce(p_permissions, '{}'::jsonb));
  perform public.log_audit('staff.permissions_changed', 'profile', p_profile_id::text,
    coalesce(p_permissions, '{}'::jsonb));
end $$;

create or replace function public.delete_staff_user(p_profile_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_target   record;
begin
  if v_business is null or not public.has_permission('owner') then
    raise exception 'Only the store owner can remove staff' using errcode = '42501';
  end if;
  select * into v_target from public.profiles where id = p_profile_id;
  if v_target.id is null or v_target.business_id is distinct from v_business
     or v_target.role::text not in ('staff', 'manager') then
    raise exception 'Staff member not found in your store';
  end if;
  perform public.log_audit('staff.deleted', 'profile', p_profile_id::text,
    jsonb_build_object('email', v_target.email));
  delete from auth.users where id = p_profile_id;   -- cascades to profile + permissions
end $$;

-- Session bootstrap with effective permissions and the corrected user limit
-- (the app treats 999 as "unlimited").
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
        'plan', to_jsonb(pl), 'user_limit', v_limit, 'staff_count', v_count)
      from public.subscriptions s left join public.plans pl on pl.id = s.plan_id
      where s.business_id = v_business
      order by s.created_at desc limit 1));
end $$;

-- ============================================================
-- J. Privileged RPCs and reports (findings 3, 4)
-- ============================================================

-- Admin panel callers use either an admin JWT or the service role.
create or replace function public.assert_platform_admin()
returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_admin()
          or (auth.uid() is null and coalesce(public.request_role(), '') not in ('anon', 'authenticated'))) then
    raise exception 'Admin only' using errcode = '42501';
  end if;
end $$;

create or replace function public.apply_plan_features(p_business uuid, p_plan uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_included text[];
  v_key text;
begin
  perform public.assert_platform_admin();
  insert into public.feature_flags (business_id) values (p_business)
    on conflict (business_id) do nothing;
  if p_plan is null then return; end if;
  select coalesce(array(select jsonb_array_elements_text(included_features)), '{}')
    into v_included from public.plans where id = p_plan;
  if array_length(v_included, 1) is null then return; end if;
  foreach v_key in array public.app_feature_keys() loop
    execute format(
      'update public.feature_flags set %I = $1, updated_at = now() where business_id = $2', v_key)
      using v_key = any(v_included), p_business;
  end loop;
end $$;

create or replace function public.resync_plan_features(p_plan uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  r record;
begin
  perform public.assert_platform_admin();
  for r in select distinct business_id from public.subscriptions where plan_id = p_plan loop
    perform public.apply_plan_features(r.business_id, p_plan);
  end loop;
end $$;

revoke execute on function public.apply_plan_features(uuid, uuid) from public, anon;
revoke execute on function public.resync_plan_features(uuid) from public, anon;
grant execute on function public.apply_plan_features(uuid, uuid) to authenticated, service_role;
grant execute on function public.resync_plan_features(uuid) to authenticated, service_role;

-- Reports: keep each original body as *_impl (not callable by clients) and
-- expose a permission-checked wrapper under the original name.
do $$
begin
  if not exists (select 1 from pg_proc where proname = 'get_sales_report_impl') then
    alter function public.get_sales_report(date, date) rename to get_sales_report_impl;
    alter function public.get_product_sales_report(date, date) rename to get_product_sales_report_impl;
    alter function public.get_profit_report(date, date) rename to get_profit_report_impl;
    alter function public.get_expense_report(date, date) rename to get_expense_report_impl;
    alter function public.get_gst_report(date, date) rename to get_gst_report_impl;
    alter function public.get_dashboard_stats() rename to get_dashboard_stats_impl;
  end if;
end $$;

revoke execute on function public.get_sales_report_impl(date, date) from public, anon, authenticated;
revoke execute on function public.get_product_sales_report_impl(date, date) from public, anon, authenticated;
revoke execute on function public.get_profit_report_impl(date, date) from public, anon, authenticated;
revoke execute on function public.get_expense_report_impl(date, date) from public, anon, authenticated;
revoke execute on function public.get_gst_report_impl(date, date) from public, anon, authenticated;
revoke execute on function public.get_dashboard_stats_impl() from public, anon, authenticated;

create or replace function public.assert_reports()
returns void language plpgsql stable as $$
begin
  perform public.assert_can('can_view_reports', false);
  perform public.assert_feature('reports', 'Reports & analytics');
end $$;

create or replace function public.get_sales_report(p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_reports();
  return public.get_sales_report_impl(p_from, p_to);
end $$;

create or replace function public.get_product_sales_report(p_from date, p_to date)
returns table (product_id uuid, product_name text, variant_name text,
               qty_sold numeric, revenue numeric, profit numeric)
language plpgsql security definer set search_path = public as $$
declare
  v_profit boolean;
begin
  perform public.assert_reports();
  v_profit := public.has_permission('can_view_profit');
  return query
    select r.product_id, r.product_name, r.variant_name, r.qty_sold, r.revenue,
           case when v_profit then r.profit end
    from public.get_product_sales_report_impl(p_from, p_to) r;
end $$;

create or replace function public.get_profit_report(p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_reports();
  perform public.assert_can('can_view_profit', false);
  return public.get_profit_report_impl(p_from, p_to);
end $$;

create or replace function public.get_expense_report(p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_reports();
  perform public.assert_can('can_manage_expenses', false);
  return public.get_expense_report_impl(p_from, p_to);
end $$;

create or replace function public.get_gst_report(p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_reports();
  return public.get_gst_report_impl(p_from, p_to);
end $$;

-- Dashboard stays available to every member; cost-based figures are
-- blanked for staff without cost/profit visibility.
create or replace function public.get_dashboard_stats()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v jsonb := public.get_dashboard_stats_impl();
begin
  if not public.has_permission('can_view_profit') then
    v := v || jsonb_build_object('today_profit', null, 'stock_value', null);
  end if;
  if not public.has_permission('can_manage_purchases') then
    v := v || jsonb_build_object('supplier_due_total', null);
  end if;
  return v;
end $$;

-- Internal helpers are only for use inside security-definer functions.
revoke execute on function public.next_doc_no(uuid, text, text) from public, anon, authenticated;
revoke execute on function public.log_audit(text, text, text, jsonb) from public, anon, authenticated;
revoke execute on function public.gst_is_inter_state(uuid, text) from public, anon, authenticated;
revoke execute on function public.write_staff_permissions(uuid, uuid, jsonb) from public, anon, authenticated;
revoke execute on function public.enforce_tenant_refs() from public, anon, authenticated;

-- Opening stock and manual adjustments: permission checks happen in
-- guard_stock_movements; these just validate the product and variant.
create or replace function public.add_opening_stock(
  p_product_id uuid, p_variant_id uuid, p_quantity numeric
) returns void language plpgsql security definer set search_path = public as $$
declare
  v_business uuid;
begin
  select business_id into v_business from public.products where id = p_product_id;
  if v_business is null or v_business <> public.current_business_id() then
    raise exception 'Product not found';
  end if;
  if p_quantity is null or p_quantity = 0 then return; end if;
  if p_quantity < 0 then raise exception 'Opening stock cannot be negative'; end if;
  insert into public.stock_movements
    (business_id, product_id, variant_id, movement_type, quantity, note, created_by)
  values (v_business, p_product_id, p_variant_id, 'opening', p_quantity, 'Opening stock', auth.uid());
end $$;

-- ============================================================
-- K. ImageKit key from Supabase Vault (key removed from source control)
-- ============================================================
create or replace function public.get_imagekit_auth()
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_private_key text;
  v_token       text := gen_random_uuid()::text;
  v_expire      bigint := extract(epoch from now())::bigint + 3540;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  select decrypted_secret into v_private_key
    from vault.decrypted_secrets where name = 'imagekit_private_key' limit 1;
  if v_private_key is null then
    raise exception 'Image upload is not configured yet';
  end if;
  return jsonb_build_object(
    'token', v_token,
    'expire', v_expire,
    'signature', encode(hmac(v_token || v_expire::text, v_private_key, 'sha1'), 'hex'));
end $$;

revoke execute on function public.get_imagekit_auth() from public, anon;
grant execute on function public.get_imagekit_auth() to authenticated;

-- ============================================================
-- Owner steps after running this migration
--   1. In ImageKit, generate a NEW private key (the old one is public on
--      GitHub). Then, in the SQL editor:
--        select vault.create_secret('<new private key>', 'imagekit_private_key');
--      Update the public key in apps/mobile/lib/core/imagekit.dart if it changed.
--   2. Existing staff now have the new permissions switched off
--      (purchases, returns, edit/cancel bills). Grant them in Staff if needed.
-- ============================================================
