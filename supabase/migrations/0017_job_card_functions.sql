-- ============================================================
-- 0017_job_card_functions.sql — Job card lifecycle RPCs (PRD Phase 2).
-- Mirrors the atomic-RPC pattern used everywhere else (create_invoice,
-- create_purchase, ...): security definer, current_business_id() scoping,
-- log_audit, stock via stock_movements inserts (trigger keeps
-- current_stock in sync).
-- ============================================================

-- ---------- Create job card (PRD Phase 2 §6-7) ----------
create or replace function public.create_job_card(payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_job_id   uuid;
  v_job_no   text;
begin
  if v_business is null then raise exception 'No business for current user'; end if;
  v_job_no := public.next_doc_no(v_business, 'job_card', 'JOB');

  insert into public.job_cards
    (business_id, job_no, customer_id, customer_name, customer_phone, item_name, brand, model,
     serial_no, issue_description, item_condition, accessories_received, technician_name,
     estimated_cost, advance_amount, advance_mode, expected_delivery, customer_note,
     internal_note, warranty_days, created_by)
  values
    (v_business, v_job_no, (payload ->> 'customer_id')::uuid,
     coalesce(payload ->> 'customer_name', ''), coalesce(payload ->> 'customer_phone', ''),
     coalesce(payload ->> 'item_name', ''), coalesce(payload ->> 'brand', ''),
     coalesce(payload ->> 'model', ''), coalesce(payload ->> 'serial_no', ''),
     coalesce(payload ->> 'issue_description', ''), coalesce(payload ->> 'item_condition', ''),
     coalesce(payload ->> 'accessories_received', ''), coalesce(payload ->> 'technician_name', ''),
     coalesce((payload ->> 'estimated_cost')::numeric, 0),
     coalesce((payload ->> 'advance_amount')::numeric, 0),
     coalesce((payload ->> 'advance_mode')::public.payment_mode, 'cash'),
     nullif(payload ->> 'expected_delivery', '')::date,
     coalesce(payload ->> 'customer_note', ''), coalesce(payload ->> 'internal_note', ''),
     (payload ->> 'warranty_days')::integer, auth.uid())
  returning id into v_job_id;

  insert into public.job_status_history (business_id, job_card_id, status, note, created_by)
  values (v_business, v_job_id, 'received', 'Job card created', auth.uid());

  perform public.log_audit('job_card.created', 'job_card', v_job_id::text,
    jsonb_build_object('job_no', v_job_no));
  return jsonb_build_object('id', v_job_id, 'job_no', v_job_no);
end $$;

-- ---------- Update status + history (PRD Phase 2 §8) ----------
create or replace function public.update_job_status(
  p_job_id uuid, p_status public.job_status, p_note text default ''
) returns void language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
begin
  update public.job_cards set
    status = p_status,
    delivered_at = case when p_status = 'delivered' then now() else delivered_at end
  where id = p_job_id and business_id = v_business;
  if not found then raise exception 'Job card not found'; end if;

  insert into public.job_status_history (business_id, job_card_id, status, note, created_by)
  values (v_business, p_job_id, p_status, coalesce(p_note, ''), auth.uid());

  perform public.log_audit('job_card.status_changed', 'job_card', p_job_id::text,
    jsonb_build_object('status', p_status));
end $$;

-- ---------- Add a spare-part or labor line (PRD Phase 2 §10-11) ----------
create or replace function public.add_job_card_item(payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_job      record;
  v_item_id  uuid;
  v_type     text := payload ->> 'item_type';
  v_qty      numeric := coalesce((payload ->> 'quantity')::numeric, 1);
  v_price    numeric := coalesce((payload ->> 'unit_price')::numeric, 0);
  v_gst      numeric := coalesce((payload ->> 'gst_rate')::numeric, 0);
  v_product  uuid := (payload ->> 'product_id')::uuid;
  v_variant  uuid := (payload ->> 'variant_id')::uuid;
  v_deduct   boolean;
  v_total    numeric;
begin
  if v_type not in ('part', 'labor') then raise exception 'Invalid item_type'; end if;
  select * into v_job from public.job_cards
    where id = (payload ->> 'job_card_id')::uuid and business_id = v_business for update;
  if v_job is null then raise exception 'Job card not found'; end if;

  v_total := round(v_qty * v_price * (1 + v_gst / 100), 2);
  v_deduct := v_type = 'part' and v_product is not null;

  insert into public.job_card_items
    (business_id, job_card_id, item_type, product_id, variant_id, service_id, name, hsn_code,
     quantity, unit_price, cost_price, gst_rate, line_total, stock_deducted)
  values
    (v_business, v_job.id, v_type, v_product, v_variant, (payload ->> 'service_id')::uuid,
     payload ->> 'name', coalesce(payload ->> 'hsn_code', ''), v_qty, v_price,
     coalesce((payload ->> 'cost_price')::numeric, 0), v_gst, v_total, v_deduct)
  returning id into v_item_id;

  if v_deduct then
    insert into public.stock_movements
      (business_id, product_id, variant_id, movement_type, quantity,
       reference_type, reference_id, created_by)
    values (v_business, v_product, v_variant, 'job_card', -v_qty, 'job_card', v_job.id, auth.uid());
  end if;

  perform public.log_audit('job_card.item_added', 'job_card', v_job.id::text,
    jsonb_build_object('item_type', v_type, 'name', payload ->> 'name'));
  return jsonb_build_object('id', v_item_id, 'line_total', v_total);
end $$;

-- ---------- Remove a line (reverses stock if it was a deducted part) ----------
create or replace function public.remove_job_card_item(p_item_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_item     record;
begin
  select * into v_item from public.job_card_items
    where id = p_item_id and business_id = v_business;
  if v_item is null then raise exception 'Item not found'; end if;

  if v_item.stock_deducted and v_item.product_id is not null then
    insert into public.stock_movements
      (business_id, product_id, variant_id, movement_type, quantity,
       reference_type, reference_id, created_by)
    values (v_business, v_item.product_id, v_item.variant_id, 'job_card', v_item.quantity,
            'job_card', v_item.job_card_id, auth.uid());
  end if;

  delete from public.job_card_items where id = p_item_id;
end $$;

-- ---------- Close job card: build the final product+service invoice ----------
-- (PRD Phase 2 §12-14, §18 "Estimate to Invoice Flow" endpoint). Parts were
-- already deducted from stock when added via add_job_card_item, so this
-- does NOT touch stock again — it only turns the accumulated line items
-- into a normal invoices/invoice_items row (prints/shares like any bill)
-- and applies the advance already collected.
create or replace function public.close_job_card(p_job_id uuid, payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business      uuid := public.current_business_id();
  v_job           record;
  v_item          record;
  v_subtotal      numeric(14,2) := 0;
  v_tax           numeric(14,2) := 0;
  v_total         numeric(14,2);
  v_paid_now      numeric(14,2) := coalesce((payload ->> 'paid_amount')::numeric, 0);
  v_paid_raw      numeric(14,2);
  v_paid          numeric(14,2);
  v_scale         numeric;
  v_mode          public.payment_mode := coalesce((payload ->> 'payment_mode')::public.payment_mode, 'cash');
  v_invoice_id    uuid;
  v_invoice_no    text;
  v_prefix        text;
  v_status        public.payment_status;
  v_warranty_days integer := (payload ->> 'warranty_days')::integer;
  v_item_count    integer;
begin
  select * into v_job from public.job_cards
    where id = p_job_id and business_id = v_business for update;
  if v_job is null then raise exception 'Job card not found'; end if;
  if v_job.invoice_id is not null then raise exception 'Job card already closed'; end if;

  select count(*) into v_item_count from public.job_card_items where job_card_id = p_job_id;
  if v_item_count = 0 then
    raise exception 'Add at least one part or labor line before closing';
  end if;

  for v_item in select * from public.job_card_items where job_card_id = p_job_id loop
    v_subtotal := v_subtotal + (v_item.quantity * v_item.unit_price);
    v_tax := v_tax + (v_item.line_total - v_item.quantity * v_item.unit_price);
  end loop;
  v_total := v_subtotal + v_tax;
  v_paid_raw := v_job.advance_amount + v_paid_now;
  v_paid := least(v_paid_raw, v_total);
  v_scale := case when v_paid_raw > 0 then v_paid / v_paid_raw else 1 end;

  v_status := case when v_paid >= v_total then 'paid' when v_paid > 0 then 'partial' else 'unpaid' end;
  select invoice_prefix into v_prefix from public.businesses where id = v_business;
  v_invoice_no := public.next_doc_no(v_business, 'invoice', v_prefix);

  insert into public.invoices
    (business_id, invoice_no, invoice_type, invoice_date, customer_id, customer_name,
     customer_phone, subtotal, discount_amount, tax_amount, round_off, total,
     paid_amount, payment_status, payment_mode, notes, created_by)
  values
    (v_business, v_invoice_no, coalesce((payload ->> 'invoice_type')::public.invoice_type, 'gst'),
     now(), v_job.customer_id, v_job.customer_name, v_job.customer_phone,
     v_subtotal, 0, v_tax, 0, v_total, v_paid, v_status, v_mode,
     'Job card ' || v_job.job_no, auth.uid())
  returning id into v_invoice_id;

  for v_item in select * from public.job_card_items where job_card_id = p_job_id loop
    insert into public.invoice_items
      (business_id, invoice_id, product_id, variant_id, product_name, variant_name,
       hsn_code, serial_no, quantity, unit_name, unit_price, mrp, cost_price,
       discount_amount, gst_rate, tax_amount, line_total)
    values
      (v_business, v_invoice_id, v_item.product_id, v_item.variant_id, v_item.name, '',
       v_item.hsn_code, case when v_item.item_type = 'part' then v_job.serial_no else '' end,
       v_item.quantity, '', v_item.unit_price, 0, v_item.cost_price, 0, v_item.gst_rate,
       v_item.line_total - v_item.quantity * v_item.unit_price, v_item.line_total);
  end loop;

  if v_job.advance_amount > 0 then
    insert into public.invoice_payments (business_id, invoice_id, amount, payment_mode)
    values (v_business, v_invoice_id, round(v_job.advance_amount * v_scale, 2), v_job.advance_mode);
  end if;
  if v_paid_now > 0 then
    insert into public.invoice_payments (business_id, invoice_id, amount, payment_mode)
    values (v_business, v_invoice_id, round(v_paid_now * v_scale, 2), v_mode);
  end if;
  if v_job.customer_id is not null and (v_total - v_paid) > 0 then
    update public.customers set due_amount = due_amount + (v_total - v_paid)
      where id = v_job.customer_id and business_id = v_business;
  end if;

  update public.job_cards set
    invoice_id = v_invoice_id,
    warranty_days = coalesce(v_warranty_days, warranty_days),
    warranty_start = case when coalesce(v_warranty_days, warranty_days) is not null
                       then current_date else warranty_start end,
    warranty_end = case when coalesce(v_warranty_days, warranty_days) is not null
                     then current_date + coalesce(v_warranty_days, warranty_days)
                     else warranty_end end
  where id = p_job_id;

  perform public.log_audit('job_card.closed', 'job_card', p_job_id::text,
    jsonb_build_object('invoice_id', v_invoice_id, 'invoice_no', v_invoice_no, 'total', v_total));

  return jsonb_build_object('invoice_id', v_invoice_id, 'invoice_no', v_invoice_no, 'total', v_total);
end $$;
