-- ============================================================
-- 0057_master_products.sql — one shared product list for all shops
--
-- When a shop adds a product, its details go into a master list: name,
-- brand, category, unit, HSN, GST rate, barcode. Never prices, stock, SKU,
-- the shop's description or its photo. The next shop searches the list by
-- name (or scans the barcode), picks the product and only enters its own
-- prices and stock. SOFTRAXA sees the list in the admin panel and can add,
-- correct, hide and merge products.
--
--   * master_products: shops cannot read the table. They search through
--     search_master_products(), which never says which shop added a
--     product.
--   * link_master_product(): a trigger on products. It can never stop a
--     shop from saving a product — if anything goes wrong with the shared
--     list, the product is saved without a link.
--   * The same product typed slightly differently ("Samsung A15",
--     "samsung  a-15") is one entry. A shop that corrects a typo in a
--     product only it has corrects the entry too.
--   * platform_settings.catalog_auto_publish: on (default) = a shop's new
--     product is offered to other shops at once; off = it waits for
--     SOFTRAXA's approval.
--   * Entries SOFTRAXA has edited are "verified": shops no longer change
--     them.
--
-- Products that already exist are not copied in; they join the list when
-- they are next edited. Run AFTER 0056.
-- ============================================================

-- ============================================================
-- A. The list
-- ============================================================
-- "Samsung  Galaxy-A15" and "samsung galaxy a15" are the same product.
create or replace function public.master_name_key(p text)
returns text language sql immutable as $$
  select btrim(regexp_replace(lower(coalesce(p, '')), '[[:space:][:punct:]]+', ' ', 'g'));
$$;

create table if not exists public.master_products (
  id                  uuid primary key default gen_random_uuid(),
  name                text not null check (btrim(name) <> ''),
  name_key            text not null,
  brand               text not null default '',
  category            text not null default '',
  unit_name           text not null default '',
  unit_short          text not null default '',
  allow_decimal       boolean not null default false,
  hsn_code            text not null default ''
                        check (hsn_code = '' or hsn_code ~ '^[0-9]{4}([0-9]{2}){0,2}$'),
  gst_rate            numeric(5,2) not null default 0 check (gst_rate between 0 and 100),
  barcode             text not null default '',
  business_type       text not null default '',     -- kind of shop it suits, for search order
  description         text not null default '',     -- written by SOFTRAXA only
  secondary_unit_name text,
  conversion_factor   numeric(12,3) check (conversion_factor is null or conversion_factor > 0),
  track_serial        boolean not null default false,
  track_pieces        boolean not null default false,
  warranty_months     integer,
  status              text not null default 'published'
                        check (status in ('published', 'pending', 'hidden')),
  source              text not null default 'shop' check (source in ('shop', 'softraxa')),
  verified            boolean not null default false,
  source_business_id  uuid references public.businesses(id) on delete set null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create unique index if not exists uq_master_products_key on public.master_products(name_key);
create index if not exists idx_master_products_barcode on public.master_products(barcode) where barcode <> '';
create index if not exists idx_master_products_status on public.master_products(status, created_at desc);

-- SOFTRAXA only. Shops use the functions below.
alter table public.master_products enable row level security;
drop policy if exists "admin all" on public.master_products;
create policy "admin all" on public.master_products for all
  using (public.is_admin()) with check (public.is_admin());

alter table public.products add column if not exists master_product_id uuid
  references public.master_products(id) on delete set null;
create index if not exists idx_products_master on public.products(master_product_id)
  where master_product_id is not null;

alter table public.platform_settings add column if not exists catalog_auto_publish boolean not null default true;

-- ============================================================
-- B. Shops' products feed the list
-- ============================================================
-- Fill the blanks of an entry from a shop's product; nothing already
-- there is overwritten, and verified entries are left alone.
create or replace function public.enrich_master_product(
  p_id uuid, p_barcode text, p_hsn text, p_brand text, p_category text,
  p_unit_name text, p_unit_short text, p_decimal boolean)
returns void language sql security definer set search_path = public as $$
  update public.master_products m set
    barcode = case when m.barcode = '' and p_barcode <> ''
                        and not exists (select 1 from public.master_products o where o.barcode = p_barcode)
                   then p_barcode else m.barcode end,
    hsn_code = case when m.hsn_code = '' and p_hsn ~ '^[0-9]{4}([0-9]{2}){0,2}$' then p_hsn else m.hsn_code end,
    brand = case when m.brand = '' then p_brand else m.brand end,
    category = case when m.category = '' then p_category else m.category end,
    unit_name = case when m.unit_name = '' then p_unit_name else m.unit_name end,
    unit_short = case when m.unit_name = '' then p_unit_short else m.unit_short end,
    allow_decimal = case when m.unit_name = '' then p_decimal else m.allow_decimal end,
    updated_at = now()
  where m.id = p_id and not m.verified
    and ((m.barcode = '' and p_barcode <> '') or (m.hsn_code = '' and p_hsn <> '')
         or (m.brand = '' and p_brand <> '') or (m.category = '' and p_category <> '')
         or (m.unit_name = '' and p_unit_name <> ''));
$$;

create or replace function public.link_master_product()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_key      text := public.master_name_key(new.name);
  v_barcode  text := case when new.barcode ~ '^[0-9]{8,14}$' then new.barcode else '' end;
  v_brand    text := '';
  v_category text := '';
  v_unit     text := '';
  v_short    text := '';
  v_decimal  boolean := false;
  v_m        public.master_products;
  v_id       uuid;
begin
  begin
    -- A shop can point a NEW product at the entry it picked; afterwards
    -- the link is ours to manage.
    if tg_op = 'UPDATE' then
      new.master_product_id := old.master_product_id;
    elsif new.master_product_id is not null then
      if exists (select 1 from public.master_products where id = new.master_product_id) then
        return new;
      end if;
      new.master_product_id := null;
    end if;
    if char_length(v_key) < 3 then return new; end if;

    select coalesce((select b.name from public.brands b where b.id = new.brand_id), ''),
           coalesce((select c.name from public.categories c where c.id = new.category_id), '')
      into v_brand, v_category;
    select u.name, u.short_name, u.allow_decimal into v_unit, v_short, v_decimal
      from public.units u where u.id = new.unit_id;
    v_unit := coalesce(v_unit, ''); v_short := coalesce(v_short, ''); v_decimal := coalesce(v_decimal, false);

    -- Already linked (an edit).
    if new.master_product_id is not null then
      select * into v_m from public.master_products where id = new.master_product_id;
      if public.master_name_key(old.name) = v_key then
        perform public.enrich_master_product(v_m.id, v_barcode, new.hsn_code, v_brand, v_category,
                                             v_unit, v_short, v_decimal);
        return new;
      end if;
      -- Renamed. If the entry is this shop's own and nothing else uses it,
      -- the correction (usually a typo) is made in the list too.
      if v_m.source = 'shop' and not v_m.verified and v_m.source_business_id = new.business_id
         and not exists (select 1 from public.products p
                         where p.master_product_id = v_m.id and p.id <> new.id) then
        select id into v_id from public.master_products where name_key = v_key and id <> v_m.id;
        if v_id is null then
          update public.master_products set name = btrim(new.name), name_key = v_key, updated_at = now()
            where id = v_m.id;
        else
          -- The corrected name is already in the list: use that entry and
          -- stop offering the misspelt one. (Hidden, not deleted: deleting
          -- would touch the very product row being saved.)
          new.master_product_id := v_id;
          update public.master_products set status = 'hidden', updated_at = now() where id = v_m.id;
        end if;
      end if;
      return new;
    end if;

    -- Not linked yet: the same name (or the same barcode) is the same product.
    select * into v_m from public.master_products
      where name_key = v_key or (v_barcode <> '' and barcode = v_barcode)
      order by (name_key = v_key) desc limit 1;
    if v_m.id is not null then
      new.master_product_id := v_m.id;
      perform public.enrich_master_product(v_m.id, v_barcode, new.hsn_code, v_brand, v_category,
                                           v_unit, v_short, v_decimal);
      return new;
    end if;

    insert into public.master_products
      (name, name_key, brand, category, unit_name, unit_short, allow_decimal, hsn_code, gst_rate,
       barcode, business_type, secondary_unit_name, conversion_factor, track_serial, track_pieces,
       warranty_months, status, source, source_business_id)
    values
      (btrim(new.name), v_key, v_brand, v_category, v_unit, v_short, v_decimal,
       case when new.hsn_code ~ '^[0-9]{4}([0-9]{2}){0,2}$' then new.hsn_code else '' end,
       new.gst_rate, v_barcode,
       coalesce((select b.business_type::text from public.businesses b where b.id = new.business_id), ''),
       new.secondary_unit_name, new.conversion_factor, new.track_serial, new.track_pieces,
       new.warranty_months,
       case when coalesce((select catalog_auto_publish from public.platform_settings where id = 1), true)
            then 'published' else 'pending' end,
       'shop', new.business_id)
    on conflict (name_key) do nothing
    returning id into v_id;
    if v_id is null then
      select id into v_id from public.master_products where name_key = v_key;
    end if;
    new.master_product_id := v_id;
    return new;
  exception when others then
    -- The shop's product must always save; the shared list can wait.
    new.master_product_id := case when tg_op = 'UPDATE' then old.master_product_id end;
    return new;
  end;
end $$;

drop trigger if exists trg_products_master on public.products;
create trigger trg_products_master
  before insert or update of name, barcode, hsn_code, brand_id, category_id, unit_id
  on public.products
  for each row execute function public.link_master_product();

-- ============================================================
-- C. Shops search the list and use a product
-- ============================================================
-- Products offered to shops that this shop doesn't have yet. Matches part
-- of the name, or a whole barcode. Products for the same kind of shop come
-- first. No prices exist in the list, and the shop that added a product
-- is never shown.
create or replace function public.search_master_products(p_query text, p_limit integer default 10)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_key      text := public.master_name_key(p_query);
  v_code     text := btrim(coalesce(p_query, ''));
  v_type     text;
begin
  if v_business is null then raise exception 'No shop selected'; end if;
  if char_length(v_key) < 2 then return '[]'::jsonb; end if;
  select business_type::text into v_type from public.businesses where id = v_business;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', r.id, 'name', r.name, 'brand', r.brand, 'category', r.category,
             'unit_name', r.unit_name, 'unit_short', r.unit_short, 'hsn_code', r.hsn_code,
             'gst_rate', r.gst_rate, 'barcode', r.barcode) order by r.pos)
    from (
      select m.*, row_number() over (
               order by (m.barcode <> '' and m.barcode = v_code) desc,
                        (m.business_type = v_type) desc,
                        (m.name_key like v_key || '%') desc,
                        m.verified desc, m.name) as pos
      from public.master_products m
      where m.status = 'published'
        and (m.name_key like '%' || v_key || '%' or (v_code ~ '^[0-9]{8,14}$' and m.barcode = v_code))
        and not exists (select 1 from public.products p
                        where p.business_id = v_business and p.master_product_id = m.id)
      order by pos
      limit least(greatest(coalesce(p_limit, 10), 1), 30)) r), '[]'::jsonb);
end $$;

-- The shop picked a product: make sure its category, brand and unit exist
-- in the shop (matched by name) and return everything the product form
-- needs. The shop then adds its prices and stock and saves as usual.
create or replace function public.use_master_product(p_master uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  m          public.master_products;
  v_category uuid;
  v_brand    uuid;
  v_unit     uuid;
begin
  if v_business is null then raise exception 'No shop selected'; end if;
  perform public.assert_can('can_manage_products');
  select * into m from public.master_products where id = p_master and status = 'published';
  if m.id is null then raise exception 'This product is no longer in the list'; end if;

  if m.category <> '' then
    select id into v_category from public.categories
      where business_id = v_business and lower(name) = lower(m.category) limit 1;
    if v_category is null then
      insert into public.categories (business_id, name) values (v_business, m.category)
        returning id into v_category;
    else
      update public.categories set is_active = true where id = v_category and not is_active;
    end if;
  end if;
  if m.brand <> '' then
    select id into v_brand from public.brands
      where business_id = v_business and lower(name) = lower(m.brand) limit 1;
    if v_brand is null then
      insert into public.brands (business_id, name) values (v_business, m.brand)
        returning id into v_brand;
    else
      update public.brands set is_active = true where id = v_brand and not is_active;
    end if;
  end if;
  if m.unit_name <> '' then
    select id into v_unit from public.units
      where business_id = v_business
        and (lower(name) = lower(m.unit_name)
             or (m.unit_short <> '' and lower(short_name) = lower(m.unit_short)))
      order by (lower(name) = lower(m.unit_name)) desc limit 1;
    if v_unit is null then
      insert into public.units (business_id, name, short_name, allow_decimal)
        values (v_business, m.unit_name, m.unit_short, m.allow_decimal)
        returning id into v_unit;
    end if;
  end if;

  return jsonb_build_object(
    'master_product_id', m.id, 'name', m.name, 'barcode', m.barcode, 'hsn_code', m.hsn_code,
    'gst_rate', m.gst_rate, 'description', m.description,
    'secondary_unit_name', m.secondary_unit_name, 'conversion_factor', m.conversion_factor,
    'track_serial', m.track_serial, 'track_pieces', m.track_pieces,
    'warranty_months', m.warranty_months,
    'category_id', v_category, 'brand_id', v_brand, 'unit_id', v_unit);
end $$;

-- ============================================================
-- D. SOFTRAXA manages the list (admin panel, logged)
-- ============================================================
-- The list for the admin page, with how many shops use each product and
-- which shop added it.
create or replace function public.get_admin_master_products(
  p_search text default '', p_status text default '', p_limit integer default 200)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_key  text := public.master_name_key(p_search);
  v_code text := btrim(coalesce(p_search, ''));
begin
  perform public.assert_platform_admin();
  return jsonb_build_object(
    'auto_publish', (select catalog_auto_publish from public.platform_settings where id = 1),
    'counts', (select jsonb_build_object(
                 'all', count(*),
                 'published', count(*) filter (where status = 'published'),
                 'pending', count(*) filter (where status = 'pending'),
                 'hidden', count(*) filter (where status = 'hidden'))
               from public.master_products),
    'rows', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.created_at desc)
      from (
        select m.*,
               (select count(distinct p.business_id) from public.products p
                where p.master_product_id = m.id) as shops,
               (select b.name from public.businesses b where b.id = m.source_business_id) as source_shop
        from public.master_products m
        where (coalesce(p_status, '') = '' or m.status = p_status)
          and (v_key = '' or m.name_key like '%' || v_key || '%'
               or lower(m.brand) like '%' || lower(v_code) || '%'
               or (v_code <> '' and m.barcode = v_code))
        order by m.created_at desc
        limit least(greatest(coalesce(p_limit, 200), 1), 500)) r), '[]'::jsonb));
end $$;

-- Add (p_id null) or correct a product. p: name, brand, category,
-- unit_name, unit_short, allow_decimal, hsn_code, gst_rate, barcode,
-- business_type, description, secondary_unit_name, conversion_factor,
-- track_serial, track_pieces, warranty_months. A saved entry is verified
-- and published.
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
  perform public.assert_platform_admin();
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

-- published = offered to shops; hidden = never offered (and a shop adding
-- the same name again does not bring it back); pending = waiting for you.
create or replace function public.admin_set_master_product_status(p_id uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_name text;
begin
  perform public.assert_platform_admin();
  if p_status not in ('published', 'pending', 'hidden') then raise exception 'Unknown status'; end if;
  update public.master_products set status = p_status, updated_at = now()
    where id = p_id returning name into v_name;
  if v_name is null then raise exception 'Product not found'; end if;
  perform public.admin_log(null, 'master_product.' || p_status, 'master_product', p_id::text,
    jsonb_build_object('name', v_name));
end $$;

-- Two entries for one product: every shop's product moves to p_into and
-- p_from disappears.
create or replace function public.admin_merge_master_products(p_from uuid, p_into uuid)
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_from public.master_products;
  v_into public.master_products;
  v_moved integer;
begin
  perform public.assert_platform_admin();
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

-- Offer shops' new products to other shops at once, or after approval.
create or replace function public.admin_set_catalog_auto_publish(p_on boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_platform_admin();
  update public.platform_settings set catalog_auto_publish = coalesce(p_on, true) where id = 1;
  perform public.admin_log(null, 'settings.updated', 'platform_settings', '1',
    jsonb_build_object('catalog_auto_publish', coalesce(p_on, true)));
end $$;

-- ============================================================
-- E. System health knows about this migration
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
      '0056', to_regproc('public.admin_save_settings') is not null,
      '0057', to_regproc('public.search_master_products') is not null),
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
    'master_products_pending', (select count(*) from public.master_products where status = 'pending'),
    'confirmed_checks', (select confirmed_checks from public.platform_settings where id = 1)
  );
end $$;

-- ============================================================
-- Grants
-- ============================================================
revoke execute on function public.enrich_master_product(uuid, text, text, text, text, text, text, boolean) from public, anon, authenticated;
revoke execute on function public.search_master_products(text, integer) from public, anon;
revoke execute on function public.use_master_product(uuid) from public, anon;
revoke execute on function public.get_admin_master_products(text, text, integer) from public, anon;
revoke execute on function public.admin_save_master_product(uuid, jsonb) from public, anon;
revoke execute on function public.admin_set_master_product_status(uuid, text) from public, anon;
revoke execute on function public.admin_merge_master_products(uuid, uuid) from public, anon;
revoke execute on function public.admin_set_catalog_auto_publish(boolean) from public, anon;
grant execute on function public.search_master_products(text, integer) to authenticated;
grant execute on function public.use_master_product(uuid) to authenticated;
grant execute on function public.get_admin_master_products(text, text, integer) to authenticated, service_role;
grant execute on function public.admin_save_master_product(uuid, jsonb) to authenticated, service_role;
grant execute on function public.admin_set_master_product_status(uuid, text) to authenticated, service_role;
grant execute on function public.admin_merge_master_products(uuid, uuid) to authenticated, service_role;
grant execute on function public.admin_set_catalog_auto_publish(boolean) to authenticated, service_role;
