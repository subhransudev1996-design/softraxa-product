-- ============================================================
-- 0003_catalog.sql — categories, brands, units, products, variants, serials
-- ============================================================

create table public.categories (
  id          uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name        text not null,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  unique (business_id, name)
);
create index idx_categories_business on public.categories(business_id);

create table public.brands (
  id          uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name        text not null,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  unique (business_id, name)
);
create index idx_brands_business on public.brands(business_id);

create table public.units (
  id          uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name        text not null,             -- e.g. Piece, Kg, Metre, Box
  short_name  text not null default '',  -- e.g. pcs, kg, m
  allow_decimal boolean not null default false,
  created_at  timestamptz not null default now(),
  unique (business_id, name)
);
create index idx_units_business on public.units(business_id);

-- ---------- Products (PRD 7.4) ----------
create table public.products (
  id             uuid primary key default gen_random_uuid(),
  business_id    uuid not null references public.businesses(id) on delete cascade,
  name           text not null,
  sku            text not null default '',
  barcode        text not null default '',
  category_id    uuid references public.categories(id) on delete set null,
  brand_id       uuid references public.brands(id) on delete set null,
  unit_id        uuid references public.units(id) on delete set null,
  hsn_code       text not null default '',
  purchase_price numeric(12,2) not null default 0,
  selling_price  numeric(12,2) not null default 0,
  mrp            numeric(12,2) not null default 0,
  wholesale_price numeric(12,2),                    -- hardware bulk pricing (PRD 7.5)
  wholesale_min_qty numeric(12,3),
  gst_rate       numeric(5,2) not null default 0,   -- percentage, e.g. 18
  current_stock  numeric(14,3) not null default 0,  -- maintained by stock_movements trigger
  low_stock_qty  numeric(14,3) not null default 0,
  image_url      text,
  description    text not null default '',
  has_variants   boolean not null default false,
  track_serial   boolean not null default false,    -- IMEI/serial tracking (mobile shops)
  warranty_months integer,
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index idx_products_business on public.products(business_id);
create index idx_products_barcode on public.products(business_id, barcode) where barcode <> '';
create index idx_products_name on public.products using gin (to_tsvector('simple', name));
create trigger trg_products_updated before update on public.products
  for each row execute function public.set_updated_at();

-- ---------- Product variants (PRD 7.5) ----------
-- `attributes` holds shop-type-specific fields, e.g.
--   mobile:  {"model":"A54","ram":"8GB","storage":"128GB","color":"Black"}
--   garment: {"size":"XL","color":"Blue","fabric":"Cotton","gender":"Men","design":"D-102"}
--   hardware:{"weight":"5kg","material":"Steel"}
create table public.product_variants (
  id             uuid primary key default gen_random_uuid(),
  business_id    uuid not null references public.businesses(id) on delete cascade,
  product_id     uuid not null references public.products(id) on delete cascade,
  name           text not null,             -- display label, e.g. "8GB/128GB Black"
  sku            text not null default '',
  barcode        text not null default '',
  attributes     jsonb not null default '{}'::jsonb,
  purchase_price numeric(12,2),             -- null = inherit from product
  selling_price  numeric(12,2),
  mrp            numeric(12,2),
  current_stock  numeric(14,3) not null default 0,
  low_stock_qty  numeric(14,3),
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index idx_variants_product on public.product_variants(product_id);
create index idx_variants_business on public.product_variants(business_id);
create index idx_variants_barcode on public.product_variants(business_id, barcode) where barcode <> '';
create trigger trg_variants_updated before update on public.product_variants
  for each row execute function public.set_updated_at();

-- ---------- Serial / IMEI tracking (mobile shops, PRD 7.5) ----------
create table public.product_serials (
  id          uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  product_id  uuid not null references public.products(id) on delete cascade,
  variant_id  uuid references public.product_variants(id) on delete cascade,
  serial_no   text not null,               -- IMEI or serial number
  status      text not null default 'in_stock'
              check (status in ('in_stock', 'sold', 'returned', 'damaged')),
  invoice_id  uuid,                        -- set when sold (FK added in 0005)
  purchase_id uuid,                        -- set when purchased (FK added in 0006)
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (business_id, serial_no)
);
create index idx_serials_product on public.product_serials(product_id);
create trigger trg_serials_updated before update on public.product_serials
  for each row execute function public.set_updated_at();
