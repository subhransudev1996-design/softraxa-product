-- ============================================================
-- 0005_sales.sql — invoices, invoice items, sale returns
-- ============================================================

-- ---------- Invoices (PRD 7.7, 7.8) ----------
create table public.invoices (
  id              uuid primary key default gen_random_uuid(),
  business_id     uuid not null references public.businesses(id) on delete cascade,
  invoice_no      text not null,                    -- e.g. INV-000123
  invoice_type    public.invoice_type not null default 'gst',
  invoice_date    timestamptz not null default now(),
  customer_id     uuid references public.customers(id) on delete set null,
  customer_name   text not null default '',         -- snapshot for walk-in / deleted customers
  customer_phone  text not null default '',

  subtotal        numeric(14,2) not null default 0, -- sum of line totals before bill discount & tax
  discount_amount numeric(14,2) not null default 0, -- bill-level discount
  tax_amount      numeric(14,2) not null default 0, -- total GST
  round_off       numeric(6,2)  not null default 0,
  total           numeric(14,2) not null default 0,
  paid_amount     numeric(14,2) not null default 0,
  due_amount      numeric(14,2) generated always as (total - paid_amount) stored,
  payment_status  public.payment_status not null default 'unpaid',
  payment_mode    public.payment_mode not null default 'cash', -- primary mode

  notes           text not null default '',
  is_cancelled    boolean not null default false,

  -- offline sync support (PRD 7.10)
  local_id        uuid,                             -- client-generated id for offline bills
  offline_created boolean not null default false,

  created_by      uuid references public.profiles(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  unique (business_id, invoice_no)
);
create unique index idx_invoices_local on public.invoices(business_id, local_id) where local_id is not null;
create index idx_invoices_business_date on public.invoices(business_id, invoice_date desc);
create index idx_invoices_customer on public.invoices(customer_id);
create trigger trg_invoices_updated before update on public.invoices
  for each row execute function public.set_updated_at();

-- ---------- Invoice items ----------
create table public.invoice_items (
  id            uuid primary key default gen_random_uuid(),
  business_id   uuid not null references public.businesses(id) on delete cascade,
  invoice_id    uuid not null references public.invoices(id) on delete cascade,
  product_id    uuid references public.products(id) on delete set null,
  variant_id    uuid references public.product_variants(id) on delete set null,
  product_name  text not null,                     -- snapshot
  variant_name  text not null default '',
  hsn_code      text not null default '',
  serial_no     text not null default '',          -- IMEI/serial sold, if tracked
  quantity      numeric(12,3) not null check (quantity > 0),
  unit_name     text not null default '',
  unit_price    numeric(12,2) not null,            -- price actually charged per unit (pre-tax)
  mrp           numeric(12,2) not null default 0,
  cost_price    numeric(12,2) not null default 0,  -- purchase price snapshot (for profit reports)
  discount_amount numeric(12,2) not null default 0,-- line discount total
  gst_rate      numeric(5,2) not null default 0,
  tax_amount    numeric(12,2) not null default 0,
  line_total    numeric(14,2) not null             -- (qty*price - discount) + tax
);
create index idx_invoice_items_invoice on public.invoice_items(invoice_id);
create index idx_invoice_items_product on public.invoice_items(product_id);
create index idx_invoice_items_business on public.invoice_items(business_id);

-- ---------- Payments recorded on an invoice ----------
create table public.invoice_payments (
  id           uuid primary key default gen_random_uuid(),
  business_id  uuid not null references public.businesses(id) on delete cascade,
  invoice_id   uuid not null references public.invoices(id) on delete cascade,
  amount       numeric(12,2) not null check (amount > 0),
  payment_mode public.payment_mode not null default 'cash',
  payment_date timestamptz not null default now(),
  note         text not null default '',
  created_at   timestamptz not null default now()
);
create index idx_invoice_payments_invoice on public.invoice_payments(invoice_id);

-- ---------- Sale returns (PRD 7.11) ----------
create table public.sale_returns (
  id            uuid primary key default gen_random_uuid(),
  business_id   uuid not null references public.businesses(id) on delete cascade,
  return_no     text not null,
  invoice_id    uuid references public.invoices(id) on delete set null,
  customer_id   uuid references public.customers(id) on delete set null,
  return_date   timestamptz not null default now(),
  total         numeric(14,2) not null default 0,
  refund_amount numeric(14,2) not null default 0,  -- cash/upi refunded now; rest reduces customer due
  refund_mode   public.payment_mode not null default 'cash',
  notes         text not null default '',
  created_by    uuid references public.profiles(id),
  created_at    timestamptz not null default now(),
  unique (business_id, return_no)
);
create index idx_sale_returns_business on public.sale_returns(business_id, return_date desc);

create table public.sale_return_items (
  id             uuid primary key default gen_random_uuid(),
  business_id    uuid not null references public.businesses(id) on delete cascade,
  sale_return_id uuid not null references public.sale_returns(id) on delete cascade,
  product_id     uuid references public.products(id) on delete set null,
  variant_id     uuid references public.product_variants(id) on delete set null,
  product_name   text not null,
  serial_no      text not null default '',
  quantity       numeric(12,3) not null check (quantity > 0),
  unit_price     numeric(12,2) not null,
  tax_amount     numeric(12,2) not null default 0,
  line_total     numeric(14,2) not null
);
create index idx_sale_return_items_ret on public.sale_return_items(sale_return_id);

-- ---------- Deferred FKs from earlier migrations ----------
alter table public.product_serials
  add constraint fk_serials_invoice foreign key (invoice_id)
  references public.invoices(id) on delete set null;

alter table public.customer_payments
  add constraint fk_customer_payments_invoice foreign key (invoice_id)
  references public.invoices(id) on delete set null;
