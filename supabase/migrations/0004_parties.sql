-- ============================================================
-- 0004_parties.sql — customers, suppliers, their due payments
-- ============================================================

-- ---------- Customers (PRD 7.13) ----------
create table public.customers (
  id          uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name        text not null,
  phone       text not null default '',
  address     text not null default '',
  gst_number  text not null default '',
  due_amount  numeric(14,2) not null default 0,  -- maintained by sale/payment/return functions
  notes       text not null default '',
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index idx_customers_business on public.customers(business_id);
create index idx_customers_phone on public.customers(business_id, phone) where phone <> '';
create trigger trg_customers_updated before update on public.customers
  for each row execute function public.set_updated_at();

-- Due payments received from customers (against overall due, PRD 7.13)
create table public.customer_payments (
  id           uuid primary key default gen_random_uuid(),
  business_id  uuid not null references public.businesses(id) on delete cascade,
  customer_id  uuid not null references public.customers(id) on delete cascade,
  invoice_id   uuid,                       -- optional link to a specific invoice (FK added in 0005)
  amount       numeric(12,2) not null check (amount > 0),
  payment_mode public.payment_mode not null default 'cash',
  payment_date date not null default current_date,
  note         text not null default '',
  created_by   uuid references public.profiles(id),
  created_at   timestamptz not null default now()
);
create index idx_customer_payments_cust on public.customer_payments(customer_id);
create index idx_customer_payments_business_date on public.customer_payments(business_id, payment_date);

-- ---------- Suppliers (PRD 7.14) ----------
create table public.suppliers (
  id          uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name        text not null,
  phone       text not null default '',
  address     text not null default '',
  gst_number  text not null default '',
  due_amount  numeric(14,2) not null default 0,  -- what we owe the supplier
  notes       text not null default '',
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index idx_suppliers_business on public.suppliers(business_id);
create trigger trg_suppliers_updated before update on public.suppliers
  for each row execute function public.set_updated_at();

-- Payments made to suppliers (PRD 7.14)
create table public.supplier_payments (
  id           uuid primary key default gen_random_uuid(),
  business_id  uuid not null references public.businesses(id) on delete cascade,
  supplier_id  uuid not null references public.suppliers(id) on delete cascade,
  purchase_id  uuid,                       -- optional link to a specific purchase (FK added in 0006)
  amount       numeric(12,2) not null check (amount > 0),
  payment_mode public.payment_mode not null default 'cash',
  payment_date date not null default current_date,
  note         text not null default '',
  created_by   uuid references public.profiles(id),
  created_at   timestamptz not null default now()
);
create index idx_supplier_payments_sup on public.supplier_payments(supplier_id);
create index idx_supplier_payments_business_date on public.supplier_payments(business_id, payment_date);
