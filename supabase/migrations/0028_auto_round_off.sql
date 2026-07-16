-- ============================================================
-- 0028_auto_round_off.sql — whole-rupee totals everywhere.
--
-- Problem (INV-00037): POS prices are GST-inclusive, but line prices are
-- stored pre-tax rounded to 2 decimals; recomputing the total from them
-- drifts by a paisa (2 x ₹35,000 became ₹70,000.01), leaving a ₹0.01 due
-- after full payment. Fix: create_invoice / update_invoice /
-- create_purchase now fold any paise residual into round_off and round
-- the stored total to the nearest rupee. Plus a one-time cleanup that
-- settles existing sub-5-paise ghost dues (and the matching customer /
-- supplier aggregate balances).
-- ============================================================

create or replace function public.create_invoice(payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business    uuid := public.current_business_id();
  v_type        public.invoice_type := coalesce((payload ->> 'invoice_type')::public.invoice_type, 'gst');
  v_local_id    uuid := (payload ->> 'local_id')::uuid;
  v_invoice_id  uuid;
  v_invoice_no  text;
  v_prefix      text;
  v_subtotal    numeric(14,2) := 0;
  v_tax         numeric(14,2) := 0;
  v_discount    numeric(14,2) := coalesce((payload ->> 'discount_amount')::numeric, 0);
  v_round       numeric(6,2)  := coalesce((payload ->> 'round_off')::numeric, 0);
  v_total       numeric(14,2);
  v_payments    jsonb := payload -> 'payments';
  v_paid        numeric(14,2);
  v_paid_raw    numeric(14,2);
  v_mode        public.payment_mode;
  v_distinct    integer;
  v_status      public.payment_status;
  v_customer    uuid := (payload ->> 'customer_id')::uuid;
  v_item        jsonb;
  v_pay_item    jsonb;
  v_qty         numeric;
  v_serial      text;
  v_limit       integer;
  v_this_month  integer;
begin
  if v_business is null then raise exception 'No business for current user'; end if;

  -- idempotent offline sync: if this local_id already synced, return it
  if v_local_id is not null then
    select id, invoice_no into v_invoice_id, v_invoice_no
      from public.invoices where business_id = v_business and local_id = v_local_id;
    if v_invoice_id is not null then
      return jsonb_build_object('id', v_invoice_id, 'invoice_no', v_invoice_no, 'already_synced', true);
    end if;
  end if;

  -- plan invoice limit (per calendar month), estimates excluded
  if v_type <> 'estimate' then
    select pl.invoice_limit into v_limit
      from public.subscriptions s join public.plans pl on pl.id = s.plan_id
      where s.business_id = v_business order by s.created_at desc limit 1;
    if v_limit is not null then
      select count(*) into v_this_month from public.invoices
        where business_id = v_business and invoice_type <> 'estimate'
          and invoice_date >= date_trunc('month', now());
      if v_this_month >= v_limit then
        raise exception 'Monthly invoice limit (%) reached for your plan', v_limit;
      end if;
    end if;
  end if;

  -- compute totals from items (server is the source of truth)
  for v_item in select * from jsonb_array_elements(payload -> 'items') loop
    v_subtotal := v_subtotal
      + (v_item ->> 'quantity')::numeric * (v_item ->> 'unit_price')::numeric
      - coalesce((v_item ->> 'discount_amount')::numeric, 0);
    v_tax := v_tax + coalesce((v_item ->> 'tax_amount')::numeric, 0);
  end loop;
  v_total := v_subtotal - v_discount + v_tax + v_round;
  -- Auto round-off (0028): totals are always whole rupees. The client's
  -- tax-inclusive prices survive a pre-tax round-trip with paise drift
  -- (e.g. 2 x 35,000 arriving as 70,000.01) — that drift previously became
  -- a ghost 1-paisa due. Any residual now lands in round_off instead.
  v_round := v_round + (round(v_total) - v_total);
  v_total := round(v_total);


  -- resolve paid amount + payment mode: split payments (if given) win
  if v_payments is not null and jsonb_array_length(v_payments) > 0 then
    select coalesce(sum(greatest(coalesce((p ->> 'amount')::numeric, 0), 0)), 0)
      into v_paid_raw from jsonb_array_elements(v_payments) p;
    v_paid := least(v_paid_raw, v_total);

    select count(distinct (p ->> 'mode')) into v_distinct
      from jsonb_array_elements(v_payments) p
      where coalesce((p ->> 'amount')::numeric, 0) > 0;
    if v_distinct > 1 then
      v_mode := 'other';
    elsif v_distinct = 1 then
      select (p ->> 'mode')::public.payment_mode into v_mode
        from jsonb_array_elements(v_payments) p
        where coalesce((p ->> 'amount')::numeric, 0) > 0
        limit 1;
    else
      v_mode := 'cash';
    end if;
  else
    v_paid := coalesce((payload ->> 'paid_amount')::numeric, 0);
    if v_paid > v_total then v_paid := v_total; end if;
    v_mode := coalesce((payload ->> 'payment_mode')::public.payment_mode, 'cash');
  end if;

  v_status := case
    when v_type = 'estimate' then 'unpaid'
    when v_paid >= v_total then 'paid'
    when v_paid > 0 then 'partial'
    else 'unpaid' end;

  v_prefix := case v_type
    when 'estimate'  then 'EST'
    when 'cash_memo' then 'CM'
    else (select invoice_prefix from public.businesses where id = v_business) end;
  v_invoice_no := public.next_doc_no(
    v_business,
    case when v_type = 'estimate' then 'estimate'
         when v_type = 'cash_memo' then 'cash_memo'
         else 'invoice' end,
    v_prefix);

  insert into public.invoices
    (business_id, invoice_no, invoice_type, invoice_date, customer_id, customer_name,
     customer_phone, subtotal, discount_amount, tax_amount, round_off, total,
     paid_amount, payment_status, payment_mode, notes, local_id, offline_created, created_by)
  values
    (v_business, v_invoice_no, v_type,
     coalesce((payload ->> 'invoice_date')::timestamptz, now()),
     v_customer,
     coalesce(payload ->> 'customer_name', ''),
     coalesce(payload ->> 'customer_phone', ''),
     v_subtotal, v_discount, v_tax, v_round, v_total, v_paid, v_status, v_mode,
     coalesce(payload ->> 'notes', ''),
     v_local_id, coalesce((payload ->> 'offline_created')::boolean, false),
     auth.uid())
  returning id into v_invoice_id;

  for v_item in select * from jsonb_array_elements(payload -> 'items') loop
    v_qty := (v_item ->> 'quantity')::numeric;

    insert into public.invoice_items
      (business_id, invoice_id, product_id, variant_id, product_name, variant_name,
       hsn_code, serial_no, quantity, unit_name, unit_price, mrp, cost_price,
       discount_amount, gst_rate, tax_amount, line_total)
    values
      (v_business, v_invoice_id,
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

    -- stock deduction + serial handling (estimates don't move stock)
    if v_type <> 'estimate' and (v_item ->> 'product_id') is not null then
      insert into public.stock_movements
        (business_id, product_id, variant_id, movement_type, quantity,
         reference_type, reference_id, created_by)
      values
        (v_business, (v_item ->> 'product_id')::uuid, (v_item ->> 'variant_id')::uuid,
         'sale', -v_qty, 'invoice', v_invoice_id, auth.uid());

      v_serial := nullif(v_item ->> 'serial_no', '');
      if v_serial is not null then
        update public.product_serials
          set status = 'sold', invoice_id = v_invoice_id
          where business_id = v_business and serial_no = v_serial;
      end if;
    end if;
  end loop;

  -- payment record(s) + customer due
  if v_type <> 'estimate' then
    if v_payments is not null and jsonb_array_length(v_payments) > 0 then
      for v_pay_item in select * from jsonb_array_elements(v_payments) loop
        if coalesce((v_pay_item ->> 'amount')::numeric, 0) > 0 then
          insert into public.invoice_payments (business_id, invoice_id, amount, payment_mode)
          values (v_business, v_invoice_id,
                  round((v_pay_item ->> 'amount')::numeric *
                        (case when v_paid_raw > 0 then v_paid / v_paid_raw else 1 end), 2),
                  coalesce((v_pay_item ->> 'mode')::public.payment_mode, 'cash'));
        end if;
      end loop;
    elsif v_paid > 0 then
      insert into public.invoice_payments (business_id, invoice_id, amount, payment_mode)
      values (v_business, v_invoice_id, v_paid, v_mode);
    end if;
  end if;
  if v_type <> 'estimate' and v_customer is not null and (v_total - v_paid) > 0 then
    update public.customers set due_amount = due_amount + (v_total - v_paid)
      where id = v_customer and business_id = v_business;
  end if;

  perform public.log_audit('invoice.created', 'invoice', v_invoice_id::text,
    jsonb_build_object('invoice_no', v_invoice_no, 'total', v_total, 'offline',
                       coalesce((payload ->> 'offline_created')::boolean, false)));

  return jsonb_build_object('id', v_invoice_id, 'invoice_no', v_invoice_no, 'total', v_total);
end $$;

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
  -- Auto round-off (0028): totals are always whole rupees. The client's
  -- tax-inclusive prices survive a pre-tax round-trip with paise drift
  -- (e.g. 2 x 35,000 arriving as 70,000.01) — that drift previously became
  -- a ghost 1-paisa due. Any residual now lands in round_off instead.
  v_round := v_round + (round(v_total) - v_total);
  v_total := round(v_total);

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
  -- Auto round-off (0028): totals are always whole rupees. The client's
  -- tax-inclusive prices survive a pre-tax round-trip with paise drift
  -- (e.g. 2 x 35,000 arriving as 70,000.01) — that drift previously became
  -- a ghost 1-paisa due. Any residual now lands in round_off instead.
  v_round := v_round + (round(v_total) - v_total);
  v_total := round(v_total);

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

-- ---------- one-time cleanup of existing paise-drift dues ----------
do $do$
begin
  -- invoices: settle residual dues < ₹0.05
  create temp table _inv_fix on commit drop as
    select id, customer_id, (total - paid_amount) as residual
    from public.invoices
    where not is_cancelled and invoice_type <> 'estimate'
      and (total - paid_amount) > 0 and (total - paid_amount) < 0.05;

  update public.customers c
     set due_amount = greatest(0, c.due_amount - r.sum_res)
    from (select customer_id, sum(residual) as sum_res
            from _inv_fix where customer_id is not null
           group by customer_id) r
   where c.id = r.customer_id;

  update public.invoices i
     set round_off = round_off - f.residual,
         total = i.total - f.residual,
         payment_status = 'paid'
    from _inv_fix f
   where i.id = f.id;

  -- purchases: same treatment for supplier-side paise dues
  create temp table _pur_fix on commit drop as
    select id, supplier_id, (total - paid_amount) as residual
    from public.purchases
    where (total - paid_amount) > 0 and (total - paid_amount) < 0.05;

  update public.suppliers s
     set due_amount = greatest(0, s.due_amount - r.sum_res)
    from (select supplier_id, sum(residual) as sum_res
            from _pur_fix where supplier_id is not null
           group by supplier_id) r
   where s.id = r.supplier_id;

  update public.purchases p
     set round_off = round_off - f.residual,
         total = p.total - f.residual,
         payment_status = 'paid'
    from _pur_fix f
   where p.id = f.id;
end
$do$;
