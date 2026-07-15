-- ============================================================
-- 0016_job_cards_schema.sql — Phase 2 of the PRD: Product + Service
-- Management Module. Schema foundation: service catalog, job cards
-- (repair/service orders), their line items, and status history.
--
-- Kept in its own migration (no functions using the new enum value
-- yet) so `ADD VALUE` on movement_type is never used in the same
-- transaction it's added in.
-- ============================================================

alter type public.movement_type add value if not exists 'job_card';

alter table public.feature_flags add column if not exists service_module boolean not null default true;

-- ---------- Service catalog (PRD Phase 2 §5) ----------
create table public.services (
  id                 uuid primary key default gen_random_uuid(),
  business_id        uuid not null references public.businesses(id) on delete cascade,
  name               text not null,
  category           text not null default '',
  price              numeric(12,2) not null default 0,
  gst_rate           numeric(5,2) not null default 0,
  sac_code           text not null default '',
  estimated_minutes  integer,
  warranty_days      integer,
  description        text not null default '',
  is_active          boolean not null default true,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index idx_services_business on public.services(business_id);
create trigger trg_services_updated before update on public.services
  for each row execute function public.set_updated_at();

-- ---------- Job card / service order (PRD Phase 2 §6-9) ----------
create type public.job_status as enum (
  'received', 'checking', 'estimate_given', 'waiting_approval', 'in_progress',
  'waiting_parts', 'ready', 'delivered', 'cancelled', 'returned_unrepaired'
);

create table public.job_cards (
  id                    uuid primary key default gen_random_uuid(),
  business_id           uuid not null references public.businesses(id) on delete cascade,
  job_no                text not null,
  customer_id           uuid references public.customers(id) on delete set null,
  customer_name         text not null default '',
  customer_phone        text not null default '',
  item_name             text not null default '',   -- device/product/item
  brand                 text not null default '',
  model                 text not null default '',
  serial_no             text not null default '',   -- IMEI/serial, if applicable
  issue_description     text not null default '',
  item_condition        text not null default '',
  accessories_received  text not null default '',
  technician_name       text not null default '',
  status                public.job_status not null default 'received',
  estimated_cost        numeric(12,2) not null default 0,
  advance_amount        numeric(12,2) not null default 0,
  advance_mode          public.payment_mode not null default 'cash',
  expected_delivery     date,
  delivered_at          timestamptz,
  customer_note         text not null default '',
  internal_note         text not null default '',
  warranty_days         integer,
  warranty_start        date,
  warranty_end          date,
  invoice_id            uuid references public.invoices(id) on delete set null,
  created_by            uuid references public.profiles(id),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  unique (business_id, job_no)
);
create index idx_job_cards_business on public.job_cards(business_id, created_at desc);
create index idx_job_cards_serial on public.job_cards(business_id, serial_no) where serial_no <> '';
create index idx_job_cards_customer on public.job_cards(customer_id);
create trigger trg_job_cards_updated before update on public.job_cards
  for each row execute function public.set_updated_at();

-- Unified line items: a 'part' consumes inventory (product_id set), a
-- 'labor' line is a service/labor charge (service_id optionally set,
-- free-typed labor charges are allowed with both ids null).
create table public.job_card_items (
  id              uuid primary key default gen_random_uuid(),
  business_id     uuid not null references public.businesses(id) on delete cascade,
  job_card_id     uuid not null references public.job_cards(id) on delete cascade,
  item_type       text not null check (item_type in ('part', 'labor')),
  product_id      uuid references public.products(id) on delete set null,
  variant_id      uuid references public.product_variants(id) on delete set null,
  service_id      uuid references public.services(id) on delete set null,
  name            text not null,
  hsn_code        text not null default '',
  quantity        numeric(12,3) not null default 1 check (quantity > 0),
  unit_price      numeric(12,2) not null default 0,
  cost_price      numeric(12,2) not null default 0, -- purchase-price snapshot, for profit reports
  gst_rate        numeric(5,2) not null default 0,
  line_total      numeric(14,2) not null default 0,
  stock_deducted  boolean not null default false,
  created_at      timestamptz not null default now()
);
create index idx_job_card_items_job on public.job_card_items(job_card_id);

create table public.job_status_history (
  id           uuid primary key default gen_random_uuid(),
  business_id  uuid not null references public.businesses(id) on delete cascade,
  job_card_id  uuid not null references public.job_cards(id) on delete cascade,
  status       public.job_status not null,
  note         text not null default '',
  created_by   uuid references public.profiles(id),
  created_at   timestamptz not null default now()
);
create index idx_job_status_history_job on public.job_status_history(job_card_id, created_at desc);

-- ---------- RLS: same tenant-isolation pattern as every other table ----------
do $$
declare
  t text;
begin
  foreach t in array array['services', 'job_cards', 'job_card_items', 'job_status_history'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format(
      'create policy "tenant all" on public.%I for all
         using (business_id = public.current_business_id() or public.is_admin())
         with check (business_id = public.current_business_id() or public.is_admin())', t);
  end loop;
end $$;
