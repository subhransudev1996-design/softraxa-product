-- Round-off for purchase bills — mirrors the round_off column/flow that
-- invoices already have (0005_sales.sql / 0015_split_payments.sql), applied
-- to purchases so both sales and purchase totals round to the nearest rupee.

alter table public.purchases
  add column if not exists round_off numeric(6,2) not null default 0;

-- Reissue create_purchase (previously 0014_fix_payment_status_cast.sql) with
-- round_off folded into the total, same pattern as create_invoice's v_round.
create or replace function public.create_purchase(payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business    uuid := public.current_business_id();
  v_purchase_id uuid;
  v_purchase_no text;
  v_subtotal    numeric(14,2) := 0;
  v_tax         numeric(14,2) := 0;
  v_discount    numeric(14,2) := coalesce((payload ->> 'discount_amount')::numeric, 0);
  v_extra       numeric(14,2) := coalesce((payload ->> 'extra_charges')::numeric, 0);
  v_round       numeric(6,2)  := coalesce((payload ->> 'round_off')::numeric, 0);
  v_total       numeric(14,2);
  v_paid        numeric(14,2) := coalesce((payload ->> 'paid_amount')::numeric, 0);
  v_supplier    uuid := (payload ->> 'supplier_id')::uuid;
  v_item        jsonb;
  v_qty         numeric;
  v_serial      text;
begin
  if v_business is null then raise exception 'No business for current user'; end if;

  for v_item in select * from jsonb_array_elements(payload -> 'items') loop
    v_subtotal := v_subtotal
      + (v_item ->> 'quantity')::numeric * (v_item ->> 'unit_price')::numeric
      - coalesce((v_item ->> 'discount_amount')::numeric, 0);
    v_tax := v_tax + coalesce((v_item ->> 'tax_amount')::numeric, 0);
  end loop;
  v_total := v_subtotal - v_discount + v_tax + v_extra + v_round;
  if v_paid > v_total then v_paid := v_total; end if;

  v_purchase_no := public.next_doc_no(v_business, 'purchase', 'PUR');

  insert into public.purchases
    (business_id, purchase_no, bill_no, supplier_id, supplier_name, purchase_date,
     subtotal, discount_amount, tax_amount, extra_charges, round_off, total, paid_amount,
     payment_status, payment_mode, notes, created_by)
  values
    (v_business, v_purchase_no, coalesce(payload ->> 'bill_no', ''), v_supplier,
     coalesce(payload ->> 'supplier_name', ''),
     coalesce((payload ->> 'purchase_date')::date, current_date),
     v_subtotal, v_discount, v_tax, v_extra, v_round, v_total, v_paid,
     (case when v_paid >= v_total then 'paid' when v_paid > 0 then 'partial' else 'unpaid' end)::public.payment_status,
     coalesce((payload ->> 'payment_mode')::public.payment_mode, 'cash'),
     coalesce(payload ->> 'notes', ''), auth.uid())
  returning id into v_purchase_id;

  for v_item in select * from jsonb_array_elements(payload -> 'items') loop
    v_qty := (v_item ->> 'quantity')::numeric;

    insert into public.purchase_items
      (business_id, purchase_id, product_id, variant_id, product_name, quantity,
       unit_price, discount_amount, gst_rate, tax_amount, line_total, serial_nos)
    values
      (v_business, v_purchase_id,
       (v_item ->> 'product_id')::uuid, (v_item ->> 'variant_id')::uuid,
       v_item ->> 'product_name', v_qty,
       (v_item ->> 'unit_price')::numeric,
       coalesce((v_item ->> 'discount_amount')::numeric, 0),
       coalesce((v_item ->> 'gst_rate')::numeric, 0),
       coalesce((v_item ->> 'tax_amount')::numeric, 0),
       (v_item ->> 'line_total')::numeric,
       coalesce((select array_agg(x) from jsonb_array_elements_text(v_item -> 'serial_nos') x), '{}'));

    if (v_item ->> 'product_id') is not null then
      insert into public.stock_movements
        (business_id, product_id, variant_id, movement_type, quantity,
         reference_type, reference_id, created_by)
      values
        (v_business, (v_item ->> 'product_id')::uuid, (v_item ->> 'variant_id')::uuid,
         'purchase', v_qty, 'purchase', v_purchase_id, auth.uid());

      -- update product purchase price to latest, register serials
      update public.products set purchase_price = (v_item ->> 'unit_price')::numeric
        where id = (v_item ->> 'product_id')::uuid and business_id = v_business
          and coalesce((v_item ->> 'update_cost')::boolean, true);

      for v_serial in select * from jsonb_array_elements_text(coalesce(v_item -> 'serial_nos', '[]'::jsonb)) loop
        insert into public.product_serials
          (business_id, product_id, variant_id, serial_no, status, purchase_id)
        values (v_business, (v_item ->> 'product_id')::uuid, (v_item ->> 'variant_id')::uuid,
                v_serial, 'in_stock', v_purchase_id)
        on conflict (business_id, serial_no)
        do update set status = 'in_stock', purchase_id = excluded.purchase_id;
      end loop;
    end if;
  end loop;

  if v_paid > 0 then
    insert into public.supplier_payments
      (business_id, supplier_id, purchase_id, amount, payment_mode, note, created_by)
    select v_business, v_supplier, v_purchase_id, v_paid,
           coalesce((payload ->> 'payment_mode')::public.payment_mode, 'cash'),
           'Paid with purchase', auth.uid()
    where v_supplier is not null;
  end if;
  if v_supplier is not null and (v_total - v_paid) > 0 then
    update public.suppliers set due_amount = due_amount + (v_total - v_paid)
      where id = v_supplier and business_id = v_business;
  end if;

  perform public.log_audit('purchase.created', 'purchase', v_purchase_id::text,
    jsonb_build_object('purchase_no', v_purchase_no, 'total', v_total));
  return jsonb_build_object('id', v_purchase_id, 'purchase_no', v_purchase_no, 'total', v_total);
end $$;
