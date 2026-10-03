-- ============================================================
-- 0061_pack_price.sql — sell a product loose OR by the pack, each at its
-- own price
--
-- A pan shop buys cigarettes by the box (1 Box = 10 pcs) and sells both a
-- whole box (₹95) and single pieces (₹10). Until now a box was only a
-- quantity shortcut charged at piece price × 10, so the shop couldn't bill
-- the box price — and billing it by hand looked like a discount, which the
-- price check (0043) blocks for staff.
--
--   * products.pack_price: selling price of one whole bulk unit
--     (secondary_unit_name / conversion_factor, 0020). Empty = piece price
--     × pieces, as before. Products without variants only.
--   * invoice_items.sold_as_pack: the line was sold in whole packs. Stock
--     still moves in the base unit (quantity stays in pieces); the flag
--     tells the price check to compare the line against the pack price.
--     The app sends "pack": true on such lines.
--   * create_invoice / update_invoice mark those lines before the price
--     check runs.
--
-- Run AFTER 0060.
-- ============================================================

alter table public.products
  add column if not exists pack_price numeric(12,2)
    check (pack_price is null or pack_price >= 0);
comment on column public.products.pack_price is
  'Selling price of one whole bulk unit (e.g. Box of 10). Null = selling_price × conversion_factor.';

alter table public.invoice_items
  add column if not exists sold_as_pack boolean not null default false;

-- ------------------------------------------------------------
-- Mark the pack lines of a saved bill from its payload. Lines are matched
-- on product, quantity and rate; identical lines are interchangeable, so
-- any unmarked match is the right one.
-- ------------------------------------------------------------
create or replace function public.mark_pack_lines(p_invoice uuid, p_items jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_item   jsonb;
  v_line   uuid;
  v_factor numeric;
  v_unit   text;
  v_qty    numeric;
begin
  for v_item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    continue when not coalesce((v_item ->> 'pack')::boolean, false)
               or nullif(v_item ->> 'product_id', '') is null;
    v_qty := (v_item ->> 'quantity')::numeric;

    select ii.id, ii.alt_factor, ii.alt_unit_name into v_line, v_factor, v_unit
      from public.invoice_items ii
      where ii.invoice_id = p_invoice
        and ii.product_id = (v_item ->> 'product_id')::uuid
        and ii.variant_id is not distinct from nullif(v_item ->> 'variant_id', '')::uuid
        and ii.quantity = v_qty
        and ii.unit_price = (v_item ->> 'unit_price')::numeric
        and not ii.sold_as_pack
      order by ii.id
      limit 1;
    continue when v_line is null;

    if coalesce(v_factor, 0) <= 0 then
      raise exception '% has no pack size — set its bulk unit first', v_item ->> 'product_name';
    end if;
    if mod(v_qty, v_factor) <> 0 then
      raise exception '% is sold by the % in whole packs of %',
        v_item ->> 'product_name', v_unit, v_factor;
    end if;
    update public.invoice_items set sold_as_pack = true where id = v_line;
  end loop;
end $$;
revoke execute on function public.mark_pack_lines(uuid, jsonb) from public, anon, authenticated;

-- ------------------------------------------------------------
-- Default price per line (0043) — pack lines default to the pack price
-- per base unit; wholesale doesn't apply to them, and a customer's agreed
-- price only when it is lower. Pack lines don't count towards the
-- wholesale quantity tier of the loose lines.
-- ------------------------------------------------------------
create or replace function public.invoice_price_lines(p_invoice uuid)
returns table (id uuid, quantity numeric, eff numeric, def numeric, def_source text,
               retail numeric, wholesale numeric, customer numeric)
language sql stable security definer set search_path = public as $$
  with i as (
    select inv.id, inv.invoice_type, inv.customer_id,
           coalesce((select c.is_wholesale from public.customers c where c.id = inv.customer_id), false)
             as wholesale_customer
    from public.invoices inv where inv.id = p_invoice),
  base as (
    select ii.id, ii.quantity, ii.product_id, ii.variant_id,
           (ii.quantity * ii.unit_price - ii.discount_amount) / nullif(ii.quantity, 0)
             * case when i.invoice_type = 'gst' then 1 + ii.gst_rate / 100 else 1 end as eff,
           -- a pack line: the pack price spread over its pieces
           case when ii.sold_as_pack and ii.variant_id is null
                     and coalesce(p.pack_price, 0) > 0 and coalesce(p.conversion_factor, 0) > 0
                then p.pack_price / p.conversion_factor end as pack_unit,
           ii.sold_as_pack,
           nullif(coalesce(pv.selling_price, p.selling_price), 0) as retail,
           nullif(p.wholesale_price, 0) as wholesale,
           p.wholesale_min_qty,
           cp.price as customer,
           i.wholesale_customer
    from i
    join public.invoice_items ii on ii.invoice_id = i.id
    left join public.products p on p.id = ii.product_id
    left join public.product_variants pv on pv.id = ii.variant_id
    left join public.customer_prices cp
      on cp.customer_id = i.customer_id and cp.product_id = ii.product_id
     and cp.variant_id is not distinct from ii.variant_id),
  l as (
    select b.id, b.quantity, b.eff,
           coalesce(b.pack_unit, b.retail) as retail,
           case when b.sold_as_pack then null else b.wholesale end as wholesale,
           b.wholesale_min_qty,
           case when b.pack_unit is not null and b.customer >= b.pack_unit then null
                else b.customer end as customer,
           b.wholesale_customer,
           sum(case when b.sold_as_pack then 0 else b.quantity end)
             over (partition by b.product_id, b.variant_id) as product_qty
    from base b),
  t as (
    select l.*, (l.wholesale is not null
                 and (l.wholesale_customer
                      or (l.wholesale_min_qty is not null and l.product_qty >= l.wholesale_min_qty))) as ws
    from l)
  select t.id, t.quantity, t.eff,
         case when t.customer is not null then t.customer when t.ws then t.wholesale else t.retail end,
         case when t.customer is not null then 'customer' when t.ws then 'wholesale'
              when t.retail is not null then 'retail' else '' end,
         t.retail, t.wholesale, t.customer
  from t;
$$;
revoke execute on function public.invoice_price_lines(uuid) from public, anon, authenticated;

-- ------------------------------------------------------------
-- create_invoice (as 0052) + mark pack lines before the price check
-- ------------------------------------------------------------
create or replace function public.create_invoice(payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v         jsonb;
  v_id      uuid;
  v_pricing jsonb;
  v_ex      jsonb;
  v_item    jsonb;
  v_due     date := nullif(payload ->> 'due_date', '')::date;
begin
  perform set_config('app.doc_date',
    public.ist_date(coalesce(nullif(payload ->> 'invoice_date', '')::timestamptz, now()))::text,
    true);
  v := public.create_invoice_impl(payload);
  perform set_config('app.doc_date', '', true);
  if coalesce((v ->> 'already_synced')::boolean, false) then return v; end if;
  v_id := (v ->> 'id')::uuid;

  perform public.mark_pack_lines(v_id, payload -> 'items');

  if coalesce(payload ->> 'invoice_type', '') <> 'estimate' then
    for v_item in select * from jsonb_array_elements(coalesce(payload -> 'items', '[]'::jsonb)) loop
      if nullif(v_item ->> 'piece_id', '') is not null then
        perform public.cut_piece(
          (v_item ->> 'piece_id')::uuid, (v_item ->> 'product_id')::uuid,
          (v_item ->> 'quantity')::numeric, v_id,
          (v_item ->> 'keep_remnant')::boolean, coalesce(v_item ->> 'remnant_reason', ''),
          not coalesce((payload ->> 'offline_created')::boolean, false));
      end if;
    end loop;

    if v_due is not null then
      if v_due < (select public.ist_date(invoice_date) from public.invoices where id = v_id) then
        raise exception 'The due date can''t be before the bill date';
      end if;
      update public.invoices set due_date = v_due where id = v_id;
    end if;
  end if;

  v_pricing := public.check_invoice_pricing(v_id);
  v_ex := public.sale_exceptions(v_id, v_pricing);
  perform public.settle_sale_exceptions(v_id, payload, v_ex);
  return v;
end $$;

-- ------------------------------------------------------------
-- update_invoice (as 0051) + mark pack lines before the price check
-- ------------------------------------------------------------
create or replace function public.update_invoice(p_invoice_id uuid, payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v         jsonb;
  v_pricing jsonb;
  v_ex      jsonb;
begin
  if (select invoice_type::text from public.invoices where id = p_invoice_id) = 'opening' then
    raise exception 'An opening balance can''t be edited — cancel it and enter it again';
  end if;
  v := public.update_invoice_impl(p_invoice_id, payload);
  perform public.mark_pack_lines(p_invoice_id, payload -> 'items');
  v_pricing := public.check_invoice_pricing(p_invoice_id);
  v_ex := public.sale_exceptions(p_invoice_id, v_pricing);
  perform public.settle_sale_exceptions(p_invoice_id, payload - 'approval_id' - 'offline_created', v_ex);
  return v;
end $$;
