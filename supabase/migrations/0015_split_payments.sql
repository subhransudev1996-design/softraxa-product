-- Split payments for POS billing: a single bill can be paid across multiple
-- modes (e.g. cash 500 + UPI 500, or cash 300 + UPI 200 + rest on credit).
--
-- No enum/schema change needed: `invoice_payments` already supports multiple
-- rows per invoice (it's a payment ledger, used the same way by
-- record_customer_payment). We just teach create_invoice to accept an
-- optional `payments` array in the payload — a list of {mode, amount} — and
-- insert one invoice_payments row per entry instead of a single row.
-- `invoices.payment_mode` (a single enum column, kept for the sales-by-mode
-- report) is set to the one mode used, or 'other' when 2+ distinct modes
-- were used. Backward compatible: if `payments` is absent, behaves exactly
-- as before (single paid_amount + payment_mode).

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
