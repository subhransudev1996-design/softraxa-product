-- Cut-piece (offcut/remnant) tracking for length-goods stores — PRD Phase 3.
-- A rod store buys 12 m rods and sells cut lengths; after cutting 7 m off a
-- rod, the remaining 5 m piece is a distinct, less-sellable remnant worth
-- tracking individually.
--
-- Pieces are an AUXILIARY layer: products.current_stock (maintained by the
-- stock_movements trigger) stays the single source of truth for total
-- quantity. Piece rows only record how that total is physically split up —
-- they never write current_stock, so existing billing/stock math cannot be
-- affected. Piece updates after a sale are best-effort client-side.

alter table public.products
  add column if not exists track_pieces boolean not null default false;

comment on column public.products.track_pieces is
  'Track individual cut pieces/remnants (rods, sheets, fabric rolls). Display/pick aid only; totals stay in current_stock.';

create table public.stock_pieces (
  id          uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  product_id  uuid not null references public.products(id) on delete cascade,
  variant_id  uuid references public.product_variants(id) on delete cascade,
  label       text not null default '',            -- e.g. "Rack A", "Rod #3"
  length      numeric(12,3) not null check (length > 0),  -- in the product's base unit
  status      text not null default 'available'
                check (status in ('available', 'consumed', 'scrap')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index idx_stock_pieces_product
  on public.stock_pieces(business_id, product_id) where status = 'available';

create trigger trg_stock_pieces_updated before update on public.stock_pieces
  for each row execute function public.set_updated_at();

alter table public.stock_pieces enable row level security;
create policy "tenant all" on public.stock_pieces for all
  using (business_id = public.current_business_id() or public.is_admin())
  with check (business_id = public.current_business_id() or public.is_admin());
