-- ============================================================
-- 0006_purchases.sql — purchases, purchase items, purchase returns
-- ============================================================

-- ---------- Purchases (PRD 7.12) ----------
create table public.purchases (
  id              uuid primary key default gen_random_uuid(),
  business_id     uuid not null references public.businesses(id) on delete cascade,
  purchase_no     text not null,                    -- internal sequential number
  bill_no         text not null default '',         -- supplier's bill number
  supplier_id     uuid references public.suppliers(id) on delete set null,
  supplier_name   text not null default '',         -- snapshot
  purchase_date   date not null default current_date,

  subtotal        numeric(14,2) not null default 0,
  discount_amount numeric(14,2) not null default 0,
  tax_amount      numeric(14,2) not null default 0,
  extra_charges   numeric(14,2) not null default 0, -- transport, loading etc.
  total           numeric(14,2) not null default 0,
  paid_amount     numeric(14,2) not null default 0,
  due_amount      numeric(14,2) generated always as (total - paid_amount) stored,
  payment_status  public.payment_status not null default 'unpaid',
  payment_mode    public.payment_mode not null default 'cash',

  notes           text not null default '',
  created_by      uuid references public.profiles(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (business_id, purchase_no)
);
create index idx_purchases_business_date on public.purchases(business_id, purchase_date desc);
create index idx_purchases_supplier on public.purchases(supplier_id);
create trigger trg_purchases_updated before update on public.purchases
  for each row execute function public.set_updated_at();

create table public.purchase_items (
  id             uuid primary key default gen_random_uuid(),
  business_id    uuid not null references public.businesses(id) on delete cascade,
  purchase_id    uuid not null references public.purchases(id) on delete cascade,
  product_id     uuid references public.products(id) on delete set null,
  variant_id     uuid references public.product_variants(id) on delete set null,
  product_name   text not null,
  quantity       numeric(12,3) not null check (quantity > 0),
  unit_price     numeric(12,2) not null,            -- purchase price per unit (pre-tax)
  discount_amount numeric(12,2) not null default 0,
  gst_rate       numeric(5,2) not null default 0,
  tax_amount     numeric(12,2) not null default 0,
  line_total     numeric(14,2) not null,
  serial_nos     text[] not null default '{}'       -- IMEIs/serials received, if tracked
);
create index idx_purchase_items_purchase on public.purchase_items(purchase_id);
create index idx_purchase_items_product on public.purchase_items(product_id);

-- ---------- Purchase returns (PRD 7.12) ----------
create table public.purchase_returns (
  id            uuid primary key default gen_random_uuid(),
  business_id   uuid not null references public.businesses(id) on delete cascade,
  return_no     text not null,
  purchase_id   uuid references public.purchases(id) on delete set null,
  supplier_id   uuid references public.suppliers(id) on delete set null,
  return_date   date not null default current_date,
  total         numeric(14,2) not null default 0,
  received_amount numeric(14,2) not null default 0, -- refund received now; rest reduces supplier due
  notes         text not null default '',
  created_by    uuid references public.profiles(id),
  created_at    timestamptz not null default now(),
  unique (business_id, return_no)
);
create index idx_purchase_returns_business on public.purchase_returns(business_id, return_date desc);

create table public.purchase_return_items (
  id                 uuid primary key default gen_random_uuid(),
  business_id        uuid not null references public.businesses(id) on delete cascade,
  purchase_return_id uuid not null references public.purchase_returns(id) on delete cascade,
  product_id         uuid references public.products(id) on delete set null,
  variant_id         uuid references public.product_variants(id) on delete set null,
  product_name       text not null,
  quantity           numeric(12,3) not null check (quantity > 0),
  unit_price         numeric(12,2) not null,
  tax_amount         numeric(12,2) not null default 0,
  line_total         numeric(14,2) not null
);
create index idx_purchase_return_items_ret on public.purchase_return_items(purchase_return_id);

-- ---------- Deferred FKs from earlier migrations ----------
alter table public.product_serials
  add constraint fk_serials_purchase foreign key (purchase_id)
  references public.purchases(id) on delete set null;

alter table public.supplier_payments
  add constraint fk_supplier_payments_purchase foreign key (purchase_id)
  references public.purchases(id) on delete set null;
