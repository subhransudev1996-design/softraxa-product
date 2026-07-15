-- Purchase return must not be allowed to exceed what's actually in stock.
--
-- create_purchase_return (0008_functions.sql) inserted a negative
-- stock_movement for the returned quantity with no check at all — if some of
-- the purchased qty had already been sold (current_stock < purchased qty),
-- returning the full originally-purchased quantity to the supplier was
-- silently allowed and drove current_stock negative. Unlike POS overselling
-- (a legitimate soft-warn/backorder scenario), there is no valid business
-- case for returning more physical stock to a supplier than the shop
-- currently holds, so this is a hard block, not a warn-with-override.
create or replace function public.create_purchase_return(payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business      uuid := public.current_business_id();
  v_return_id     uuid;
  v_return_no     text;
  v_total         numeric(14,2) := 0;
  v_received      numeric(14,2) := coalesce((payload ->> 'received_amount')::numeric, 0);
  v_supplier      uuid := (payload ->> 'supplier_id')::uuid;
  v_item          jsonb;
  v_qty           numeric;
  v_current_stock numeric;
begin
  if v_business is null then raise exception 'No business for current user'; end if;

  for v_item in select * from jsonb_array_elements(payload -> 'items') loop
    v_total := v_total + (v_item ->> 'line_total')::numeric;
  end loop;
  if v_received > v_total then v_received := v_total; end if;

  -- validate stock availability before writing anything
  for v_item in select * from jsonb_array_elements(payload -> 'items') loop
    if (v_item ->> 'product_id') is not null then
      v_qty := (v_item ->> 'quantity')::numeric;
      if (v_item ->> 'variant_id') is not null then
        select current_stock into v_current_stock from public.product_variants
          where id = (v_item ->> 'variant_id')::uuid and business_id = v_business;
      else
        select current_stock into v_current_stock from public.products
          where id = (v_item ->> 'product_id')::uuid and business_id = v_business;
      end if;
      if coalesce(v_current_stock, 0) < v_qty then
        raise exception 'Cannot return % of "%" — only % in stock',
          v_qty, v_item ->> 'product_name', coalesce(v_current_stock, 0);
      end if;
    end if;
  end loop;

  v_return_no := public.next_doc_no(v_business, 'purchase_return', 'PR');

  insert into public.purchase_returns
    (business_id, return_no, purchase_id, supplier_id, total, received_amount, notes, created_by)
  values
    (v_business, v_return_no, (payload ->> 'purchase_id')::uuid, v_supplier,
     v_total, v_received, coalesce(payload ->> 'notes', ''), auth.uid())
  returning id into v_return_id;

  for v_item in select * from jsonb_array_elements(payload -> 'items') loop
    insert into public.purchase_return_items
      (business_id, purchase_return_id, product_id, variant_id, product_name,
       quantity, unit_price, tax_amount, line_total)
    values
      (v_business, v_return_id,
       (v_item ->> 'product_id')::uuid, (v_item ->> 'variant_id')::uuid,
       v_item ->> 'product_name', (v_item ->> 'quantity')::numeric,
       (v_item ->> 'unit_price')::numeric,
       coalesce((v_item ->> 'tax_amount')::numeric, 0),
       (v_item ->> 'line_total')::numeric);

    if (v_item ->> 'product_id') is not null then
      insert into public.stock_movements
        (business_id, product_id, variant_id, movement_type, quantity,
         reference_type, reference_id, created_by)
      values
        (v_business, (v_item ->> 'product_id')::uuid, (v_item ->> 'variant_id')::uuid,
         'purchase_return', -((v_item ->> 'quantity')::numeric), 'purchase_return', v_return_id, auth.uid());
    end if;
  end loop;

  if v_supplier is not null and (v_total - v_received) > 0 then
    update public.suppliers set due_amount = due_amount - (v_total - v_received)
      where id = v_supplier and business_id = v_business;
  end if;

  perform public.log_audit('purchase_return.created', 'purchase_return', v_return_id::text,
    jsonb_build_object('return_no', v_return_no, 'total', v_total));
  return jsonb_build_object('id', v_return_id, 'return_no', v_return_no, 'total', v_total);
end $$;
