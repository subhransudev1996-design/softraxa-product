-- ============================================================
-- 0007_stock_expenses.sql — stock movement ledger + expenses
-- ============================================================

-- ---------- Stock movements (single ledger, PRD 7.11) ----------
-- Every stock change is one signed row here. A trigger keeps
-- products/product_variants.current_stock in sync.
create table public.stock_movements (
  id             bigint generated always as identity primary key,
  business_id    uuid not null references public.businesses(id) on delete cascade,
  product_id     uuid not null references public.products(id) on delete cascade,
  variant_id     uuid references public.product_variants(id) on delete cascade,
  movement_type  public.movement_type not null,
  quantity       numeric(12,3) not null,       -- signed: + in, - out
  reference_type text not null default '',     -- 'invoice' | 'purchase' | 'sale_return' | ...
  reference_id   uuid,
  note           text not null default '',
  created_by     uuid references public.profiles(id),
  created_at     timestamptz not null default now()
);
create index idx_stock_movements_product on public.stock_movements(product_id, created_at desc);
create index idx_stock_movements_business on public.stock_movements(business_id, created_at desc);

create or replace function public.apply_stock_movement()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.variant_id is not null then
    update public.product_variants
      set current_stock = current_stock + new.quantity
      where id = new.variant_id;
    -- product-level stock = sum of variant stock, keep in sync
    update public.products
      set current_stock = current_stock + new.quantity
      where id = new.product_id;
  else
    update public.products
      set current_stock = current_stock + new.quantity
      where id = new.product_id;
  end if;
  return new;
end $$;

create trigger trg_apply_stock_movement
  after insert on public.stock_movements
  for each row execute function public.apply_stock_movement();

-- Opening stock: create an 'opening' movement when a product/variant is
-- inserted through the app with an opening quantity. The app passes opening
-- stock via these helper functions instead of writing current_stock directly.
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
  insert into public.stock_movements
    (business_id, product_id, variant_id, movement_type, quantity, note, created_by)
  values (v_business, p_product_id, p_variant_id, 'opening', p_quantity, 'Opening stock', auth.uid());
end $$;

-- Manual adjustment / damaged / lost entry (PRD 7.11)
create or replace function public.adjust_stock(
  p_product_id uuid,
  p_variant_id uuid,
  p_quantity   numeric,           -- signed: + add, - remove
  p_type       public.movement_type default 'adjustment',  -- 'adjustment' or 'damage'
  p_note       text default ''
) returns void language plpgsql security definer set search_path = public as $$
declare
  v_business uuid;
begin
  select business_id into v_business from public.products where id = p_product_id;
  if v_business is null or v_business <> public.current_business_id() then
    raise exception 'Product not found';
  end if;
  if p_type not in ('adjustment', 'damage') then
    raise exception 'Invalid adjustment type %', p_type;
  end if;
  if p_quantity is null or p_quantity = 0 then
    raise exception 'Quantity must not be zero';
  end if;
  insert into public.stock_movements
    (business_id, product_id, variant_id, movement_type, quantity, note, created_by)
  values (v_business, p_product_id, p_variant_id, p_type, p_quantity, p_note, auth.uid());
  perform public.log_audit('stock.adjusted', 'product', p_product_id::text,
    jsonb_build_object('quantity', p_quantity, 'type', p_type, 'note', p_note));
end $$;

-- ---------- Expenses (PRD 7.15) ----------
create table public.expense_categories (
  id          uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name        text not null,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  unique (business_id, name)
);
create index idx_expense_categories_business on public.expense_categories(business_id);

create table public.expenses (
  id           uuid primary key default gen_random_uuid(),
  business_id  uuid not null references public.businesses(id) on delete cascade,
  category_id  uuid references public.expense_categories(id) on delete set null,
  amount       numeric(12,2) not null check (amount > 0),
  expense_date date not null default current_date,
  payment_mode public.payment_mode not null default 'cash',
  note         text not null default '',
  created_by   uuid references public.profiles(id),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index idx_expenses_business_date on public.expenses(business_id, expense_date desc);
create trigger trg_expenses_updated before update on public.expenses
  for each row execute function public.set_updated_at();
