-- ============================================================
-- 0078_supplier_bill_memory.sql
-- Reading a supplier's bill (PDF / Excel) into a purchase: what the shop
-- taught the app, so the next bill from that supplier reads by itself.
--
-- * supplier_bill_items: "AMUL GHEE 1LTR TIN" on this supplier's bills is
--   the shop's "Amul Pure Ghee 1 L" (and, when the supplier bills in
--   boxes, how many of the shop's units one of theirs is). Saved when the
--   read lines are added to a purchase. A name taught for one supplier is
--   also offered for others (the same item from another distributor),
--   after that supplier's own.
-- * supplier_bill_layouts: the columns the shop corrected on this
--   supplier's bills ("Value" is the rate), by header.
--
-- The bill itself is read on the device; nothing of it is stored. The
-- tables are reached only through the functions below.
-- ============================================================

create table if not exists public.supplier_bill_items (
  id          uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  supplier_id uuid references public.suppliers(id) on delete cascade,
  item_key    text not null check (char_length(item_key) between 1 and 200),
  product_id  uuid not null references public.products(id) on delete cascade,
  variant_id  uuid references public.product_variants(id) on delete cascade,
  factor      numeric(14,4) not null default 1 check (factor > 0 and factor <= 100000),
  updated_at  timestamptz not null default now()
);
create unique index if not exists uq_supplier_bill_items
  on public.supplier_bill_items
  (business_id, coalesce(supplier_id, '00000000-0000-0000-0000-000000000000'::uuid), item_key);
create index if not exists idx_supplier_bill_items_key
  on public.supplier_bill_items (business_id, item_key);

create table if not exists public.supplier_bill_layouts (
  supplier_id uuid primary key references public.suppliers(id) on delete cascade,
  business_id uuid not null references public.businesses(id) on delete cascade,
  columns     jsonb not null default '{}'::jsonb check (jsonb_typeof(columns) = 'object'),
  updated_at  timestamptz not null default now()
);
create index if not exists idx_supplier_bill_layouts_business
  on public.supplier_bill_layouts (business_id);

alter table public.supplier_bill_items enable row level security;
alter table public.supplier_bill_layouts enable row level security;
revoke all on public.supplier_bill_items from public, anon, authenticated;
revoke all on public.supplier_bill_layouts from public, anon, authenticated;

-- What the shop taught for these item names (p_keys, as the app writes
-- them) and this supplier's columns:
--   {"items": [{"key", "product_id", "variant_id", "factor", "same_supplier"}],
--    "columns": {"header": "role", ...}}
-- Per name: this supplier's link first, then the latest from any supplier.
create or replace function public.bill_memory(p_supplier uuid, p_keys text[])
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_items    jsonb;
  v_columns  jsonb;
begin
  if v_business is null then raise exception 'No shop selected'; end if;
  perform public.assert_can('can_manage_purchases', false);
  if p_supplier is not null and not exists (
       select 1 from public.suppliers where id = p_supplier and business_id = v_business) then
    raise exception 'Supplier not found in your store';
  end if;
  if cardinality(coalesce(p_keys, '{}')) > 500 then
    raise exception 'Too many lines on one bill (500 at most)';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'key', b.item_key, 'product_id', b.product_id, 'variant_id', b.variant_id,
           'factor', b.factor, 'same_supplier', b.same)), '[]'::jsonb)
  into v_items
  from (
    select distinct on (i.item_key) i.item_key, i.product_id, i.variant_id, i.factor,
           (p_supplier is not null and i.supplier_id = p_supplier) as same
    from public.supplier_bill_items i
    join public.products p on p.id = i.product_id and p.is_active
    where i.business_id = v_business
      and i.item_key = any(coalesce(p_keys, '{}'))
    order by i.item_key,
             (p_supplier is not null and i.supplier_id = p_supplier) desc,
             i.updated_at desc
  ) b;

  select l.columns into v_columns
  from public.supplier_bill_layouts l
  where p_supplier is not null and l.supplier_id = p_supplier and l.business_id = v_business;

  return jsonb_build_object('items', v_items, 'columns', coalesce(v_columns, '{}'::jsonb));
end $$;

-- Remember a read bill: p_items [{"key", "product_id", "variant_id"?,
-- "factor"?}] for this supplier (or for no supplier), and — when
-- p_columns is given and there is a supplier — the columns the shop set
-- ('{}' forgets them). Returns how many names were saved.
create or replace function public.remember_bill(p_supplier uuid, p_items jsonb, p_columns jsonb default null)
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_item     jsonb;
  v_key      text;
  v_product  uuid;
  v_variant  uuid;
  v_factor   numeric;
  v_n        integer := 0;
  v_role     text;
begin
  if v_business is null then raise exception 'No shop selected'; end if;
  perform public.assert_can('can_manage_purchases');
  if p_supplier is not null and not exists (
       select 1 from public.suppliers where id = p_supplier and business_id = v_business) then
    raise exception 'Supplier not found in your store';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'Items must be a list';
  end if;
  if jsonb_array_length(p_items) > 500 then
    raise exception 'Too many lines on one bill (500 at most)';
  end if;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_key := lower(btrim(coalesce(v_item ->> 'key', '')));
    if char_length(v_key) < 1 or char_length(v_key) > 200 then
      raise exception 'An item name is empty or too long';
    end if;
    v_product := (v_item ->> 'product_id')::uuid;
    v_variant := nullif(v_item ->> 'variant_id', '')::uuid;
    v_factor  := coalesce((v_item ->> 'factor')::numeric, 1);
    if v_factor <= 0 or v_factor > 100000 then
      raise exception 'A pack size must be between 0 and 100000';
    end if;
    if not exists (select 1 from public.products
                   where id = v_product and business_id = v_business) then
      raise exception 'A product is not in your store';
    end if;
    if v_variant is not null and not exists (
         select 1 from public.product_variants
         where id = v_variant and product_id = v_product) then
      raise exception 'A size/colour does not belong to its product';
    end if;

    delete from public.supplier_bill_items
    where business_id = v_business
      and supplier_id is not distinct from p_supplier
      and item_key = v_key;
    insert into public.supplier_bill_items
      (business_id, supplier_id, item_key, product_id, variant_id, factor)
    values (v_business, p_supplier, v_key, v_product, v_variant, v_factor);
    v_n := v_n + 1;
  end loop;

  if p_columns is not null and p_supplier is not null then
    if jsonb_typeof(p_columns) <> 'object' then
      raise exception 'Columns must be an object';
    end if;
    if (select count(*) from jsonb_object_keys(p_columns)) > 40 then
      raise exception 'Too many columns';
    end if;
    for v_key, v_role in select key, value #>> '{}' from jsonb_each(p_columns) loop
      if char_length(v_key) > 100 or v_role not in (
           'sno', 'name', 'code', 'hsn', 'qty', 'free', 'unit', 'rate', 'rateIncl', 'mrp',
           'disc', 'discAmt', 'taxable', 'gst', 'gstPart', 'taxAmt', 'amount', 'ignore') then
        raise exception 'Unknown column choice';
      end if;
    end loop;
    if p_columns = '{}'::jsonb then
      delete from public.supplier_bill_layouts where supplier_id = p_supplier;
    else
      insert into public.supplier_bill_layouts (supplier_id, business_id, columns)
      values (p_supplier, v_business, p_columns)
      on conflict (supplier_id) do update
        set columns = excluded.columns, updated_at = now();
    end if;
  end if;
  return v_n;
end $$;

revoke execute on function public.bill_memory(uuid, text[]) from public, anon;
revoke execute on function public.remember_bill(uuid, jsonb, jsonb) from public, anon;
grant execute on function public.bill_memory(uuid, text[]) to authenticated;
grant execute on function public.remember_bill(uuid, jsonb, jsonb) to authenticated;
