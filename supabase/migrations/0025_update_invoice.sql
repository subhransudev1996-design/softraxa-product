-- Edit an existing invoice in place (store owner corrects/adds/removes items
-- on a bill already given to a customer, then reissues it under the SAME
-- invoice number) — mirrors create_invoice's item/total computation exactly,
-- but:
--   * never touches payments already recorded (invoice_payments, paid_amount,
--     payment_mode) — only items/totals change; due_amount (a generated
--     column: total - paid_amount) and payment_status are recomputed against
--     the unchanged paid_amount
--   * never touches customer_id/customer_name/customer_phone/invoice_type/
--     invoice_date — editing changes what was billed, not who it was billed
--     to or what kind of document it is
--   * reverses every old line's stock/serial effect and reapplies fresh ones
--     for the new items, instead of diffing old vs new line-by-line — net
--     stock effect is identical, and it's far simpler/safer to reason about
--     (same reversal pattern cancel_invoice already uses)
create or replace function public.update_invoice(p_invoice_id uuid, payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business   uuid := public.current_business_id();
  v_inv        record;
  v_old_item   record;
  v_item       jsonb;
  v_qty        numeric;
  v_serial     text;
  v_subtotal   numeric(14,2) := 0;
  v_tax        numeric(14,2) := 0;
  v_discount   numeric(14,2) := coalesce((payload ->> 'discount_amount')::numeric, 0);
  v_round      numeric(6,2)  := coalesce((payload ->> 'round_off')::numeric, 0);
  v_total      numeric(14,2);
  v_status     public.payment_status;
  v_due_delta  numeric(14,2);
begin
  if v_business is null then raise exception 'No business for current user'; end if;

  select * into v_inv from public.invoices
    where id = p_invoice_id and business_id = v_business for update;
  if v_inv is null then raise exception 'Invoice not found'; end if;
  if v_inv.is_cancelled then raise exception 'Cannot edit a cancelled invoice'; end if;

  -- reverse every existing line's stock/serial effect
  if v_inv.invoice_type <> 'estimate' then
    for v_old_item in select * from public.invoice_items where invoice_id = p_invoice_id loop
      if v_old_item.product_id is not null then
        insert into public.stock_movements
          (business_id, product_id, variant_id, movement_type, quantity,
           reference_type, reference_id, note, created_by)
        values (v_business, v_old_item.product_id, v_old_item.variant_id, 'adjustment',
                v_old_item.quantity, 'invoice_edit', p_invoice_id, 'Invoice edited — original line reversed', auth.uid());
        if v_old_item.serial_no <> '' then
          update public.product_serials set status = 'in_stock', invoice_id = null
            where business_id = v_business and serial_no = v_old_item.serial_no;
        end if;
      end if;
    end loop;
  end if;

  delete from public.invoice_items where invoice_id = p_invoice_id;

  -- insert new items, computing totals the same way create_invoice does
  for v_item in select * from jsonb_array_elements(payload -> 'items') loop
    v_qty := (v_item ->> 'quantity')::numeric;
    v_subtotal := v_subtotal
      + v_qty * (v_item ->> 'unit_price')::numeric
      - coalesce((v_item ->> 'discount_amount')::numeric, 0);
    v_tax := v_tax + coalesce((v_item ->> 'tax_amount')::numeric, 0);

    insert into public.invoice_items
      (business_id, invoice_id, product_id, variant_id, product_name, variant_name,
       hsn_code, serial_no, quantity, unit_name, unit_price, mrp, cost_price,
       discount_amount, gst_rate, tax_amount, line_total)
    values
      (v_business, p_invoice_id,
       (v_item ->> 'product_id')::uuid, (v_item ->> 'variant_id')::uuid,
       v_item ->> 'product_name', coalesce(v_item ->> 'variant_name', ''),
       coalesce(v_item ->> 'hsn_code', ''), coalesce(v_item ->> 'serial_no', ''),
       v_qty, coalesce(v_item ->> 'unit_name', ''),
       (v_item ->> 'unit_price')::numeric,
       coalesce((v_item ->> 'mrp')::numeric, 0),
       coalesce((v_item ->> 'cost_price')::numeric, 0),
       coalesce((v_item ->> 'discount_amount')::numeric, 0),
       coalesce((v_item ->> 'gst_rate')::numeric, 0),
       coalesce((v_item ->> 'tax_amount')::numeric, 0),
       (v_item ->> 'line_total')::numeric);

    if v_inv.invoice_type <> 'estimate' and (v_item ->> 'product_id') is not null then
      insert into public.stock_movements
        (business_id, product_id, variant_id, movement_type, quantity,
         reference_type, reference_id, created_by)
      values
        (v_business, (v_item ->> 'product_id')::uuid, (v_item ->> 'variant_id')::uuid,
         'sale', -v_qty, 'invoice', p_invoice_id, auth.uid());

      v_serial := nullif(v_item ->> 'serial_no', '');
      if v_serial is not null then
        update public.product_serials
          set status = 'sold', invoice_id = p_invoice_id
          where business_id = v_business and serial_no = v_serial;
      end if;
    end if;
  end loop;

  v_total := v_subtotal - v_discount + v_tax + v_round;
  v_status := case
    when v_inv.invoice_type = 'estimate' then 'unpaid'
    when v_inv.paid_amount >= v_total then 'paid'
    when v_inv.paid_amount > 0 then 'partial'
    else 'unpaid' end;

  update public.invoices set
    subtotal = v_subtotal,
    discount_amount = v_discount,
    tax_amount = v_tax,
    round_off = v_round,
    total = v_total,
    payment_status = v_status,
    notes = coalesce(payload ->> 'notes', v_inv.notes),
    updated_at = now()
  where id = p_invoice_id;

  -- customer due only ever reflects (total - paid); shift it by exactly how
  -- much the total changed, since paid_amount itself is untouched here
  if v_inv.invoice_type <> 'estimate' and v_inv.customer_id is not null then
    v_due_delta := v_total - v_inv.total;
    if v_due_delta <> 0 then
      update public.customers set due_amount = due_amount + v_due_delta
        where id = v_inv.customer_id and business_id = v_business;
    end if;
  end if;

  perform public.log_audit('invoice.updated', 'invoice', p_invoice_id::text,
    jsonb_build_object('invoice_no', v_inv.invoice_no, 'total', v_total));
  return jsonb_build_object('id', p_invoice_id, 'invoice_no', v_inv.invoice_no, 'total', v_total);
end $$;
