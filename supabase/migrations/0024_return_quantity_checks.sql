-- Sale/purchase returns must not be able to exceed what was actually sold or
-- purchased on the original document.
--
-- create_sale_return (0008_functions.sql) and create_purchase_return
-- (0008/0019) never checked a returned item's quantity against how much of
-- that invoice/purchase line had already been returned in an earlier return.
-- Neither the client (SaleReturnFormScreen/PurchaseReturnFormScreen cap the
-- qty stepper at the original sold/purchased quantity, not
-- original-minus-already-returned) nor the server enforced this, so the same
-- invoice/purchase could be returned in full more than once — observed in
-- practice as two separate sale returns both fully returning the same
-- invoice. This reissues both functions to hard-block that: for each
-- returned line, sum how much of that exact product/variant was already
-- returned against the same invoice/purchase and reject if the new return
-- would push the total past what was originally sold/purchased. Serial-
-- tracked items get an extra exact check so the same physical unit can't be
-- returned twice even if quantities alone wouldn't have caught it.

create or replace function public.create_sale_return(payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business  uuid := public.current_business_id();
  v_return_id uuid;
  v_return_no text;
  v_total     numeric(14,2) := 0;
  v_refund    numeric(14,2) := coalesce((payload ->> 'refund_amount')::numeric, 0);
  v_customer  uuid := (payload ->> 'customer_id')::uuid;
  v_invoice   uuid := (payload ->> 'invoice_id')::uuid;
  v_item      jsonb;
  v_qty       numeric;
  v_serial    text;
  v_orig_qty  numeric;
  v_returned  numeric;
begin
  if v_business is null then raise exception 'No business for current user'; end if;

  for v_item in select * from jsonb_array_elements(payload -> 'items') loop
    v_total := v_total + (v_item ->> 'line_total')::numeric;
  end loop;
  if v_refund > v_total then v_refund := v_total; end if;

  -- validate against the original invoice before writing anything
  for v_item in select * from jsonb_array_elements(payload -> 'items') loop
    if (v_item ->> 'product_id') is not null and v_invoice is not null then
      v_qty := (v_item ->> 'quantity')::numeric;
      v_serial := coalesce(v_item ->> 'serial_no', '');

      select coalesce(sum(ii.quantity), 0) into v_orig_qty
        from public.invoice_items ii
        where ii.invoice_id = v_invoice
          and ii.product_id = (v_item ->> 'product_id')::uuid
          and ii.variant_id is not distinct from (v_item ->> 'variant_id')::uuid;

      select coalesce(sum(sri.quantity), 0) into v_returned
        from public.sale_return_items sri
        join public.sale_returns sr on sr.id = sri.sale_return_id
        where sr.invoice_id = v_invoice
          and sri.product_id = (v_item ->> 'product_id')::uuid
          and sri.variant_id is not distinct from (v_item ->> 'variant_id')::uuid;

      if v_returned + v_qty > v_orig_qty then
        raise exception 'Cannot return % of "%" — only % remaining to return on this invoice (% already returned)',
          v_qty, v_item ->> 'product_name', greatest(v_orig_qty - v_returned, 0), v_returned;
      end if;

      if v_serial <> '' and exists (
        select 1 from public.sale_return_items sri
        join public.sale_returns sr on sr.id = sri.sale_return_id
        where sr.invoice_id = v_invoice and sri.serial_no = v_serial
      ) then
        raise exception 'Serial/IMEI % has already been returned on this invoice', v_serial;
      end if;
    end if;
  end loop;

  v_return_no := public.next_doc_no(v_business, 'sale_return', 'SR');

  insert into public.sale_returns
    (business_id, return_no, invoice_id, customer_id, total, refund_amount,
     refund_mode, notes, created_by)
  values
    (v_business, v_return_no, v_invoice, v_customer, v_total,
     v_refund, coalesce((payload ->> 'refund_mode')::public.payment_mode, 'cash'),
     coalesce(payload ->> 'notes', ''), auth.uid())
  returning id into v_return_id;

  for v_item in select * from jsonb_array_elements(payload -> 'items') loop
    insert into public.sale_return_items
      (business_id, sale_return_id, product_id, variant_id, product_name,
       serial_no, quantity, unit_price, tax_amount, line_total)
    values
      (v_business, v_return_id,
       (v_item ->> 'product_id')::uuid, (v_item ->> 'variant_id')::uuid,
       v_item ->> 'product_name', coalesce(v_item ->> 'serial_no', ''),
       (v_item ->> 'quantity')::numeric, (v_item ->> 'unit_price')::numeric,
       coalesce((v_item ->> 'tax_amount')::numeric, 0),
       (v_item ->> 'line_total')::numeric);

    if (v_item ->> 'product_id') is not null then
      insert into public.stock_movements
        (business_id, product_id, variant_id, movement_type, quantity,
         reference_type, reference_id, created_by)
      values
        (v_business, (v_item ->> 'product_id')::uuid, (v_item ->> 'variant_id')::uuid,
         'sale_return', (v_item ->> 'quantity')::numeric, 'sale_return', v_return_id, auth.uid());

      if coalesce(v_item ->> 'serial_no', '') <> '' then
        update public.product_serials set status = 'returned'
          where business_id = v_business and serial_no = v_item ->> 'serial_no';
      end if;
    end if;
  end loop;

  -- credit balance beyond refund reduces the customer's due
  if v_customer is not null and (v_total - v_refund) > 0 then
    update public.customers set due_amount = due_amount - (v_total - v_refund)
      where id = v_customer and business_id = v_business;
  end if;

  perform public.log_audit('sale_return.created', 'sale_return', v_return_id::text,
    jsonb_build_object('return_no', v_return_no, 'total', v_total));
  return jsonb_build_object('id', v_return_id, 'return_no', v_return_no, 'total', v_total);
end $$;

create or replace function public.create_purchase_return(payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business      uuid := public.current_business_id();
  v_return_id     uuid;
  v_return_no     text;
  v_total         numeric(14,2) := 0;
  v_received      numeric(14,2) := coalesce((payload ->> 'received_amount')::numeric, 0);
  v_supplier      uuid := (payload ->> 'supplier_id')::uuid;
  v_purchase      uuid := (payload ->> 'purchase_id')::uuid;
  v_item          jsonb;
  v_qty           numeric;
  v_current_stock numeric;
  v_orig_qty      numeric;
  v_returned      numeric;
begin
  if v_business is null then raise exception 'No business for current user'; end if;

  for v_item in select * from jsonb_array_elements(payload -> 'items') loop
    v_total := v_total + (v_item ->> 'line_total')::numeric;
  end loop;
  if v_received > v_total then v_received := v_total; end if;

  -- validate stock availability and against the original purchase before
  -- writing anything
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

      if v_purchase is not null then
        select coalesce(sum(pi.quantity), 0) into v_orig_qty
          from public.purchase_items pi
          where pi.purchase_id = v_purchase
            and pi.product_id = (v_item ->> 'product_id')::uuid
            and pi.variant_id is not distinct from (v_item ->> 'variant_id')::uuid;

        select coalesce(sum(pri.quantity), 0) into v_returned
          from public.purchase_return_items pri
          join public.purchase_returns pr on pr.id = pri.purchase_return_id
          where pr.purchase_id = v_purchase
            and pri.product_id = (v_item ->> 'product_id')::uuid
            and pri.variant_id is not distinct from (v_item ->> 'variant_id')::uuid;

        if v_returned + v_qty > v_orig_qty then
          raise exception 'Cannot return % of "%" — only % remaining to return on this purchase (% already returned)',
            v_qty, v_item ->> 'product_name', greatest(v_orig_qty - v_returned, 0), v_returned;
        end if;
      end if;
    end if;
  end loop;

  v_return_no := public.next_doc_no(v_business, 'purchase_return', 'PR');

  insert into public.purchase_returns
    (business_id, return_no, purchase_id, supplier_id, total, received_amount, notes, created_by)
  values
    (v_business, v_return_no, v_purchase, v_supplier,
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
