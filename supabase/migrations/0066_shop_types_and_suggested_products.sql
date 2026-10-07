-- ============================================================
-- 0066_shop_types_and_suggested_products.sql
--
-- 1. Three new kinds of shop: Grocery / kirana, Stationery & gift,
--    Cosmetics & general.
-- 2. "Suggested products" for a shop: browse the master list for the
--    shop's kind of shop (or any other), tick many products, give each a
--    selling price (and optionally cost, MRP and opening stock) and add
--    them all in one go. Category, brand and unit are created in the shop
--    when missing. Nothing in the list has a price; the shop's prices
--    stay its own.
-- 3. For SOFTRAXA: fill the list in bulk (paste or upload a sheet; an
--    existing product with the same name is corrected), download the whole
--    list, hide / offer / approve many products at once, and filter the
--    admin page by kind of shop.
-- 4. master_upsert(): one place that adds or corrects a list entry. The
--    starter products (next migrations) use it too.
--
-- Run AFTER 0065. The starter products come in 0067 onwards.
-- ============================================================

-- ============================================================
-- A. New kinds of shop
-- ============================================================
alter type public.business_type add value if not exists 'grocery';
alter type public.business_type add value if not exists 'stationery';
alter type public.business_type add value if not exists 'cosmetics';

-- ============================================================
-- B. Units the list uses (same spelling as a new shop's own units)
-- ============================================================
create or replace function public.master_unit_info(p_name text, out short_name text, out allow_decimal boolean)
returns record language sql immutable as $$
  select u.s, u.d
  from (values
    ('piece', 'pcs', false), ('kg', 'kg', true), ('gram', 'g', true), ('metre', 'm', true),
    ('litre', 'L', true), ('box', 'box', false), ('dozen', 'dz', false), ('set', 'set', false),
    ('pair', 'pr', false), ('packet', 'pkt', false), ('bag', 'bag', false), ('bundle', 'bdl', false),
    ('roll', 'roll', false), ('carton', 'ctn', false), ('bottle', 'btl', false), ('can', 'can', false),
    ('tube', 'tube', false), ('sheet', 'sht', false), ('rod', 'rod', false), ('coil', 'coil', false),
    ('strip', 'strip', false), ('unit', 'unit', false), ('number', 'nos', false),
    ('millilitre', 'ml', true), ('centimetre', 'cm', true), ('millimetre', 'mm', true),
    ('foot', 'ft', true), ('inch', 'in', true), ('yard', 'yd', true), ('square foot', 'sqft', true),
    ('square metre', 'sqm', true), ('running foot', 'rft', true), ('running metre', 'rmt', true),
    ('cubic foot', 'cft', true), ('cubic metre', 'cbm', true), ('quintal', 'qtl', true),
    ('tonne', 't', true)
  ) as u(n, s, d)
  where u.n = lower(btrim(coalesce(p_name, '')));
$$;

-- ============================================================
-- C. Add or correct one entry of the list
-- ============================================================
-- p keys (all optional except name): brand, category, unit_name,
-- unit_short, allow_decimal, hsn_code, gst_rate, barcode, business_type,
-- description, secondary_unit_name, conversion_factor, track_serial,
-- track_pieces, warranty_months. Returns 'added', 'updated' or 'skipped'.
--   p_overwrite false: an entry with the same name is left as it is.
--   p_overwrite true : the keys given replace the entry's values.
--   p_verified       : mark the entry as checked by SOFTRAXA (shops can then
--                      no longer add blanks to it).
create or replace function public.master_upsert(
  p jsonb, p_overwrite boolean default true, p_verified boolean default true)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_name   text := btrim(coalesce(p ->> 'name', ''));
  v_key    text := public.master_name_key(p ->> 'name');
  v_old    public.master_products;
  v_unit   text;
  v_short  text;
  v_dec    boolean;
  v_info   record;
  v_hsn    text;
  v_gst    numeric;
  v_code   text;
  v_type   text;
  v_bulk   text;
  v_factor numeric;
  v_other  text;
begin
  if char_length(v_key) < 3 then raise exception 'Give the product a name (3 letters or more)'; end if;

  select * into v_old from public.master_products where name_key = v_key;
  if v_old.id is not null and not p_overwrite then return 'skipped'; end if;

  v_hsn  := btrim(coalesce(p ->> 'hsn_code', case when v_old.id is not null then v_old.hsn_code else '' end));
  v_gst  := coalesce(nullif(p ->> 'gst_rate', '')::numeric, v_old.gst_rate, 0);
  v_code := btrim(coalesce(p ->> 'barcode', case when v_old.id is not null then v_old.barcode else '' end));
  v_type := btrim(coalesce(p ->> 'business_type', case when v_old.id is not null then v_old.business_type else '' end));
  v_unit := btrim(coalesce(p ->> 'unit_name', case when v_old.id is not null then v_old.unit_name else '' end));
  select * into v_info from public.master_unit_info(v_unit);
  v_short := btrim(coalesce(nullif(p ->> 'unit_short', ''), v_info.short_name,
                            case when v_old.id is not null then v_old.unit_short else '' end, ''));
  v_dec := coalesce(nullif(p ->> 'allow_decimal', '')::boolean, v_info.allow_decimal, v_old.allow_decimal, false);
  v_bulk := case when p ? 'secondary_unit_name' then nullif(btrim(coalesce(p ->> 'secondary_unit_name', '')), '')
                 else v_old.secondary_unit_name end;
  v_factor := case when p ? 'conversion_factor' then nullif(p ->> 'conversion_factor', '')::numeric
                   else v_old.conversion_factor end;

  if v_hsn <> '' and v_hsn !~ '^[0-9]{4}([0-9]{2}){0,2}$' then
    raise exception 'The HSN code must be 4, 6 or 8 digits (%)', v_name;
  end if;
  if v_gst < 0 or v_gst > 100 then raise exception 'The GST rate must be between 0 and 100 (%)', v_name; end if;
  if v_type <> '' and v_type not in (select unnest(enum_range(null::public.business_type))::text) then
    raise exception 'Unknown kind of shop "%" (%)', v_type, v_name;
  end if;
  if v_bulk is not null and coalesce(v_factor, 0) <= 0 then
    raise exception 'Say how many units make one % (%)', v_bulk, v_name;
  end if;
  if v_code <> '' then
    select name into v_other from public.master_products
      where barcode = v_code and id is distinct from v_old.id limit 1;
    if v_other is not null then raise exception 'The barcode % is already on "%"', v_code, v_other; end if;
  end if;

  if v_old.id is null then
    insert into public.master_products
      (name, name_key, brand, category, unit_name, unit_short, allow_decimal, hsn_code, gst_rate,
       barcode, business_type, description, secondary_unit_name, conversion_factor, track_serial,
       track_pieces, warranty_months, status, source, verified)
    values
      (v_name, v_key, btrim(coalesce(p ->> 'brand', '')), btrim(coalesce(p ->> 'category', '')),
       v_unit, v_short, v_dec, v_hsn, v_gst, v_code, v_type, btrim(coalesce(p ->> 'description', '')),
       v_bulk, case when v_bulk is null then null else v_factor end,
       coalesce(nullif(p ->> 'track_serial', '')::boolean, false), coalesce(nullif(p ->> 'track_pieces', '')::boolean, false),
       nullif(p ->> 'warranty_months', '')::integer, 'published', 'softraxa', coalesce(p_verified, true));
    return 'added';
  end if;

  update public.master_products set
    name = v_name,
    brand = btrim(coalesce(p ->> 'brand', brand)),
    category = btrim(coalesce(p ->> 'category', category)),
    unit_name = v_unit, unit_short = v_short, allow_decimal = v_dec,
    hsn_code = v_hsn, gst_rate = v_gst, barcode = v_code, business_type = v_type,
    description = btrim(coalesce(p ->> 'description', description)),
    secondary_unit_name = v_bulk,
    conversion_factor = case when v_bulk is null then null else v_factor end,
    track_serial = coalesce(nullif(p ->> 'track_serial', '')::boolean, track_serial),
    track_pieces = coalesce(nullif(p ->> 'track_pieces', '')::boolean, track_pieces),
    warranty_months = case when p ? 'warranty_months' then nullif(p ->> 'warranty_months', '')::integer
                           else warranty_months end,
    verified = verified or coalesce(p_verified, true),
    status = case when status = 'pending' then 'published' else status end,
    updated_at = now()
  where id = v_old.id;
  return 'updated';
end $$;

-- ============================================================
-- D. Suggested products for a shop
-- ============================================================
-- The category, brand and unit of a list entry, created in the shop when
-- it has none of that name (matched by name, ignoring capitals).
create or replace function public.master_shop_refs(
  p_business uuid, p_master public.master_products,
  out category_id uuid, out brand_id uuid, out unit_id uuid)
returns record language plpgsql security definer set search_path = public as $$
begin
  if p_master.category <> '' then
    select id into category_id from public.categories
      where business_id = p_business and lower(name) = lower(p_master.category) limit 1;
    if category_id is null then
      insert into public.categories (business_id, name) values (p_business, p_master.category)
        returning id into category_id;
    else
      update public.categories set is_active = true where id = category_id and not is_active;
    end if;
  end if;
  if p_master.brand <> '' then
    select id into brand_id from public.brands
      where business_id = p_business and lower(name) = lower(p_master.brand) limit 1;
    if brand_id is null then
      insert into public.brands (business_id, name) values (p_business, p_master.brand)
        returning id into brand_id;
    else
      update public.brands set is_active = true where id = brand_id and not is_active;
    end if;
  end if;
  if p_master.unit_name <> '' then
    select id into unit_id from public.units
      where business_id = p_business
        and (lower(name) = lower(p_master.unit_name)
             or (p_master.unit_short <> '' and lower(short_name) = lower(p_master.unit_short)))
      order by (lower(name) = lower(p_master.unit_name)) desc limit 1;
    if unit_id is null then
      insert into public.units (business_id, name, short_name, allow_decimal)
        values (p_business, p_master.unit_name, p_master.unit_short, p_master.allow_decimal)
        returning id into unit_id;
    end if;
  end if;
end $$;

-- What the shop can still pick. p_type: a kind of shop (blank = the
-- shop's own, '*' = every kind). p_query: part of the name or brand.
-- Products the shop already has (picked from the list, or the same name)
-- are left out. Returns the products, the categories and kinds of shop
-- with counts, and the total.
create or replace function public.browse_master_products(
  p_type text default '', p_category text default '', p_query text default '',
  p_limit integer default 200, p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_mine     text;
  v_type     text;
  v_key      text := public.master_name_key(p_query);
  v_text     text := lower(btrim(coalesce(p_query, '')));
  v_cat      text := btrim(coalesce(p_category, ''));
  v_limit    integer := least(greatest(coalesce(p_limit, 200), 1), 500);
  v_out      jsonb;
begin
  if v_business is null then raise exception 'No shop selected'; end if;
  select business_type::text into v_mine from public.businesses where id = v_business;
  v_type := coalesce(nullif(btrim(p_type), ''), v_mine);

  with have as (
         select public.master_name_key(name) as k, master_product_id as mid
         from public.products where business_id = v_business),
       avail as (
         select m.*, coalesce(nullif(m.category, ''), 'Other') as cat
         from public.master_products m
         where m.status = 'published'
           and not exists (select 1 from have h where h.mid = m.id or h.k = m.name_key)),
       matched as (
         select * from avail
         where (v_key = '' or name_key like '%' || v_key || '%' or lower(brand) like '%' || v_text || '%')),
       scoped as (
         select * from matched where v_type = '*' or business_type = v_type),
       picked as (
         select * from scoped where v_cat = '' or cat = v_cat)
  select jsonb_build_object(
    'type', v_type,
    'mine', v_mine,
    'total', (select count(*) from picked),
    'types', coalesce((select jsonb_agg(jsonb_build_object('type', t.business_type, 'count', t.c)
                                        order by t.c desc)
                       from (select business_type, count(*) as c from matched
                             where business_type <> '' group by 1) t), '[]'::jsonb),
    'categories', coalesce((select jsonb_agg(jsonb_build_object('category', c.cat, 'count', c.n)
                                             order by c.cat)
                            from (select cat, count(*) as n from scoped group by 1) c), '[]'::jsonb),
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
                'id', r.id, 'name', r.name, 'brand', r.brand, 'category', r.cat,
                'unit_name', r.unit_name, 'unit_short', r.unit_short, 'allow_decimal', r.allow_decimal,
                'gst_rate', r.gst_rate, 'hsn_code', r.hsn_code, 'business_type', r.business_type)
                order by r.cat, r.name)
              from (select * from picked order by cat, name
                    limit v_limit offset greatest(coalesce(p_offset, 0), 0)) r), '[]'::jsonb))
  into v_out;
  return v_out;
end $$;

-- Add the ticked products. p_items: [{master_id, selling_price,
-- purchase_price?, mrp?, opening_stock?}, ...] (up to 100). Every product
-- needs a selling price. A product the shop already has is skipped. The
-- plan's product limit applies as for any new product.
create or replace function public.add_products_from_master(p_items jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  it         jsonb;
  m          public.master_products;
  r          record;
  v_price    numeric;
  v_cost     numeric;
  v_mrp      numeric;
  v_open     numeric;
  v_id       uuid;
  v_added    integer := 0;
  v_skipped  integer := 0;
begin
  if v_business is null then raise exception 'No shop selected'; end if;
  perform public.assert_can('can_manage_products');
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Choose at least one product';
  end if;
  if jsonb_array_length(p_items) > 100 then
    raise exception 'Add up to 100 products at a time';
  end if;

  for it in select * from jsonb_array_elements(p_items) loop
    select * into m from public.master_products
      where id = nullif(it ->> 'master_id', '')::uuid and status = 'published';
    if m.id is null then v_skipped := v_skipped + 1; continue; end if;

    v_price := coalesce(nullif(it ->> 'selling_price', '')::numeric, 0);
    v_cost  := coalesce(nullif(it ->> 'purchase_price', '')::numeric, 0);
    v_mrp   := coalesce(nullif(it ->> 'mrp', '')::numeric, 0);
    v_open  := coalesce(nullif(it ->> 'opening_stock', '')::numeric, 0);
    if v_price <= 0 then raise exception 'Enter a selling price for "%"', m.name; end if;
    if v_cost < 0 or v_mrp < 0 or v_open < 0 then
      raise exception 'Prices and stock cannot be negative ("%")', m.name;
    end if;

    if exists (select 1 from public.products p
               where p.business_id = v_business
                 and (p.master_product_id = m.id or public.master_name_key(p.name) = m.name_key)) then
      v_skipped := v_skipped + 1; continue;
    end if;

    select * into r from public.master_shop_refs(v_business, m);
    insert into public.products
      (business_id, master_product_id, name, barcode, hsn_code, gst_rate,
       category_id, brand_id, unit_id, purchase_price, selling_price, mrp, description,
       track_serial, track_pieces, warranty_months, secondary_unit_name, conversion_factor)
    values
      (v_business, m.id, m.name, m.barcode, m.hsn_code, m.gst_rate,
       r.category_id, r.brand_id, r.unit_id, v_cost, v_price, v_mrp, m.description,
       m.track_serial, m.track_pieces, m.warranty_months, m.secondary_unit_name, m.conversion_factor)
    returning id into v_id;
    if v_open > 0 then perform public.add_opening_stock(v_id, null, v_open); end if;
    v_added := v_added + 1;
  end loop;

  perform public.log_audit('product.bulk_added', 'product', '',
    jsonb_build_object('added', v_added, 'skipped', v_skipped));
  return jsonb_build_object('added', v_added, 'skipped', v_skipped);
end $$;

-- ============================================================
-- E. SOFTRAXA: the list in bulk
-- ============================================================
-- Adds new products and corrects those with the same name. p_rows: a JSON
-- array of the keys master_upsert() takes. A row with a problem is
-- reported (row number, name, message) and the others still go in.
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
  perform public.assert_platform_admin();
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

-- The whole list (for a sheet), optionally one kind of shop.
create or replace function public.admin_export_master_products(p_type text default '')
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.assert_platform_admin();
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

-- Offer, hide or approve many products at once.
create or replace function public.admin_set_master_products_status(p_ids uuid[], p_status text)
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_n integer;
begin
  perform public.assert_platform_admin();
  if p_status not in ('published', 'pending', 'hidden') then raise exception 'Unknown status'; end if;
  if p_ids is null or coalesce(array_length(p_ids, 1), 0) = 0 then raise exception 'Choose some products'; end if;
  if array_length(p_ids, 1) > 2000 then raise exception 'Up to 2000 products at a time'; end if;
  update public.master_products set status = p_status, updated_at = now() where id = any(p_ids);
  get diagnostics v_n = row_count;
  perform public.admin_log(null, 'master_product.bulk_' || p_status, 'master_product', '',
    jsonb_build_object('count', v_n));
  return v_n;
end $$;

-- The admin page's list, now filtered by kind of shop and category, with
-- paging, and counts per kind of shop and per category.
drop function if exists public.get_admin_master_products(text, text, integer);
create or replace function public.get_admin_master_products(
  p_search text default '', p_status text default '', p_limit integer default 200,
  p_type text default '', p_category text default '', p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_key  text := public.master_name_key(p_search);
  v_code text := btrim(coalesce(p_search, ''));
  v_cat  text := btrim(coalesce(p_category, ''));
begin
  perform public.assert_platform_admin();
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

-- ============================================================
-- Grants
-- ============================================================
revoke execute on function public.master_unit_info(text) from public, anon, authenticated;
revoke execute on function public.master_upsert(jsonb, boolean, boolean) from public, anon, authenticated;
revoke execute on function public.master_shop_refs(uuid, public.master_products) from public, anon, authenticated;
revoke execute on function public.browse_master_products(text, text, text, integer, integer) from public, anon;
revoke execute on function public.add_products_from_master(jsonb) from public, anon;
revoke execute on function public.admin_import_master_products(jsonb) from public, anon;
revoke execute on function public.admin_export_master_products(text) from public, anon;
revoke execute on function public.admin_set_master_products_status(uuid[], text) from public, anon;
revoke execute on function public.get_admin_master_products(text, text, integer, text, text, integer) from public, anon;
grant execute on function public.browse_master_products(text, text, text, integer, integer) to authenticated;
grant execute on function public.add_products_from_master(jsonb) to authenticated;
grant execute on function public.admin_import_master_products(jsonb) to authenticated, service_role;
grant execute on function public.admin_export_master_products(text) to authenticated, service_role;
grant execute on function public.admin_set_master_products_status(uuid[], text) to authenticated, service_role;
grant execute on function public.get_admin_master_products(text, text, integer, text, text, integer) to authenticated, service_role;
