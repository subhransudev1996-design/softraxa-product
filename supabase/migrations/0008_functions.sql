-- ============================================================
-- 0008_functions.sql — business onboarding, numbering,
-- transactional sale/purchase/return/payment RPCs
-- ============================================================

-- ---------- Atomic per-business document numbering ----------
create or replace function public.next_doc_no(p_business uuid, p_doc_type text, p_prefix text)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_counter bigint;
begin
  insert into public.doc_counters (business_id, doc_type, counter)
  values (p_business, p_doc_type, 1)
  on conflict (business_id, doc_type)
  do update set counter = public.doc_counters.counter + 1
  returning counter into v_counter;
  return p_prefix || '-' || lpad(v_counter::text, 5, '0');
end $$;

-- ---------- Business onboarding (PRD 7.2) ----------
-- Creates the business, links the caller's profile, seeds feature flags,
-- default units + expense categories, and a 14-day trial subscription.
create or replace function public.create_business(payload jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_business uuid;
  v_trial_plan uuid;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if (select business_id from public.profiles where id = auth.uid()) is not null then
    raise exception 'Profile already has a business';
  end if;

  insert into public.businesses
    (name, owner_name, business_type, phone, email, address, gst_number,
     invoice_prefix, tax_preference, logo_url, setup_complete)
  values (
    payload ->> 'name',
    coalesce(payload ->> 'owner_name', ''),
    coalesce((payload ->> 'business_type')::public.business_type, 'other'),
    coalesce(payload ->> 'phone', ''),
    coalesce(payload ->> 'email', ''),
    coalesce(payload ->> 'address', ''),
    coalesce(payload ->> 'gst_number', ''),
    coalesce(nullif(payload ->> 'invoice_prefix', ''), 'INV'),
    coalesce((payload ->> 'tax_preference')::public.tax_preference, 'gst'),
    payload ->> 'logo_url',
    true
  ) returning id into v_business;

  update public.profiles set business_id = v_business,
    full_name = coalesce(nullif(payload ->> 'owner_name', ''), full_name)
    where id = auth.uid();

  insert into public.feature_flags (business_id) values (v_business);

  insert into public.expense_categories (business_id, name)
  select v_business, unnest(array[
    'Rent', 'Salary', 'Electricity', 'Transport', 'Packaging', 'Repair', 'Miscellaneous']);

  insert into public.units (business_id, name, short_name, allow_decimal)
  values
    (v_business, 'Piece',  'pcs', false),
    (v_business, 'Kg',     'kg',  true),
    (v_business, 'Gram',   'g',   true),
    (v_business, 'Metre',  'm',   true),
    (v_business, 'Litre',  'L',   true),
    (v_business, 'Box',    'box', false),
    (v_business, 'Dozen',  'dz',  false),
    (v_business, 'Set',    'set', false);

  select id into v_trial_plan from public.plans where name = 'Free Trial' limit 1;
  insert into public.subscriptions (business_id, plan_id, status, start_date, expiry_date)
  values (v_business, v_trial_plan, 'trial', current_date, current_date + 14);

  perform public.log_audit('business.created', 'business', v_business::text, '{}'::jsonb);
  return v_business;
end $$;

-- ---------- Session bootstrap: everything the app needs at startup ----------
create or replace function public.get_my_context()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
begin
  return jsonb_build_object(
    'profile',  (select to_jsonb(p) from public.profiles p where p.id = auth.uid()),
    'business', (select to_jsonb(b) from public.businesses b where b.id = v_business),
    'features', (select to_jsonb(f) from public.feature_flags f where f.business_id = v_business),
    'subscription', (
      select to_jsonb(s) || jsonb_build_object('plan', to_jsonb(pl))
      from public.subscriptions s left join public.plans pl on pl.id = s.plan_id
      where s.business_id = v_business
      order by s.created_at desc limit 1)
  );
end $$;

-- ---------- Create invoice (PRD 7.7, offline-safe per 7.10) ----------
-- payload example:
-- {
--   "invoice_type": "gst", "customer_id": null, "customer_name": "Walk-in",
--   "customer_phone": "", "discount_amount": 10, "round_off": -0.5,
--   "paid_amount": 500, "payment_mode": "cash", "notes": "",
--   "local_id": "uuid-from-offline-client", "offline_created": true,
--   "invoice_date": "2026-07-02T10:00:00Z",
--   "items": [{ "product_id": "...", "variant_id": null, "product_name": "X",
--               "variant_name": "", "hsn_code": "", "serial_no": "",
--               "quantity": 2, "unit_name": "pcs", "unit_price": 100,
--               "mrp": 120, "cost_price": 80, "discount_amount": 0,
--               "gst_rate": 18, "tax_amount": 36, "line_total": 236 }]
-- }
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
  -- split payments (e.g. cash 500 + upi 500): optional `payments` array of
  -- {mode, amount} in the payload; falls back to paid_amount/payment_mode
  -- below when absent, so older/offline-queued payloads keep working.
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

-- ---------- Cancel invoice: reverse stock, dues, serials ----------
create or replace function public.cancel_invoice(p_invoice_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_inv record;
  v_item record;
begin
  select * into v_inv from public.invoices
    where id = p_invoice_id and business_id = v_business for update;
  if v_inv is null then raise exception 'Invoice not found'; end if;
  if v_inv.is_cancelled then raise exception 'Invoice already cancelled'; end if;
  if v_inv.invoice_type <> 'estimate' then
    for v_item in select * from public.invoice_items where invoice_id = p_invoice_id loop
      if v_item.product_id is not null then
        insert into public.stock_movements
          (business_id, product_id, variant_id, movement_type, quantity,
           reference_type, reference_id, note, created_by)
        values (v_business, v_item.product_id, v_item.variant_id, 'adjustment',
                v_item.quantity, 'invoice_cancel', p_invoice_id, 'Invoice cancelled', auth.uid());
        if v_item.serial_no <> '' then
          update public.product_serials set status = 'in_stock', invoice_id = null
            where business_id = v_business and serial_no = v_item.serial_no;
        end if;
      end if;
    end loop;
    if v_inv.customer_id is not null and v_inv.due_amount > 0 then
      update public.customers set due_amount = due_amount - v_inv.due_amount
        where id = v_inv.customer_id;
    end if;
  end if;
  update public.invoices set is_cancelled = true where id = p_invoice_id;
  perform public.log_audit('invoice.cancelled', 'invoice', p_invoice_id::text, '{}'::jsonb);
end $$;

-- ---------- Record customer due payment (PRD 7.13) ----------
create or replace function public.record_customer_payment(
  p_customer_id uuid, p_amount numeric, p_mode public.payment_mode default 'cash',
  p_date date default current_date, p_note text default '', p_invoice_id uuid default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_business  uuid := public.current_business_id();
  v_id        uuid;
  v_remaining numeric;
  v_inv       record;
  v_apply     numeric;
begin
  if p_amount is null or p_amount <= 0 then raise exception 'Amount must be positive'; end if;
  update public.customers set due_amount = due_amount - p_amount
    where id = p_customer_id and business_id = v_business;
  if not found then raise exception 'Customer not found'; end if;

  insert into public.customer_payments
    (business_id, customer_id, invoice_id, amount, payment_mode, payment_date, note, created_by)
  values (v_business, p_customer_id, p_invoice_id, p_amount, p_mode, p_date, p_note, auth.uid())
  returning id into v_id;

  if p_invoice_id is not null then
    update public.invoices set
      paid_amount = paid_amount + p_amount,
      payment_status = (case when paid_amount + p_amount >= total then 'paid' else 'partial' end)::public.payment_status
      where id = p_invoice_id and business_id = v_business;
    insert into public.invoice_payments (business_id, invoice_id, amount, payment_mode, note)
    values (v_business, p_invoice_id, p_amount, p_mode, p_note);
  else
    -- No specific invoice chosen: settle the oldest outstanding invoices
    -- first (FIFO) so invoice-level status stays in sync with the
    -- customer's overall due.
    v_remaining := p_amount;
    for v_inv in
      select id, due_amount from public.invoices
      where customer_id = p_customer_id and business_id = v_business
        and not is_cancelled and invoice_type <> 'estimate' and due_amount > 0
      order by invoice_date asc
    loop
      exit when v_remaining <= 0;
      v_apply := least(v_remaining, v_inv.due_amount);
      update public.invoices set
        paid_amount = paid_amount + v_apply,
        payment_status = (case when paid_amount + v_apply >= total then 'paid' else 'partial' end)::public.payment_status
        where id = v_inv.id;
      insert into public.invoice_payments (business_id, invoice_id, amount, payment_mode, note)
      values (v_business, v_inv.id, v_apply, p_mode, p_note);
      v_remaining := v_remaining - v_apply;
    end loop;
  end if;

  perform public.log_audit('payment.received', 'customer', p_customer_id::text,
    jsonb_build_object('amount', p_amount));
  return v_id;
end $$;

-- ---------- Create purchase (PRD 7.12) ----------
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
  v_total := v_subtotal - v_discount + v_tax + v_extra;
  if v_paid > v_total then v_paid := v_total; end if;

  v_purchase_no := public.next_doc_no(v_business, 'purchase', 'PUR');

  insert into public.purchases
    (business_id, purchase_no, bill_no, supplier_id, supplier_name, purchase_date,
     subtotal, discount_amount, tax_amount, extra_charges, total, paid_amount,
     payment_status, payment_mode, notes, created_by)
  values
    (v_business, v_purchase_no, coalesce(payload ->> 'bill_no', ''), v_supplier,
     coalesce(payload ->> 'supplier_name', ''),
     coalesce((payload ->> 'purchase_date')::date, current_date),
     v_subtotal, v_discount, v_tax, v_extra, v_total, v_paid,
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

-- ---------- Record supplier payment (PRD 7.14) ----------
create or replace function public.record_supplier_payment(
  p_supplier_id uuid, p_amount numeric, p_mode public.payment_mode default 'cash',
  p_date date default current_date, p_note text default '', p_purchase_id uuid default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_business  uuid := public.current_business_id();
  v_id        uuid;
  v_remaining numeric;
  v_pur       record;
  v_apply     numeric;
begin
  if p_amount is null or p_amount <= 0 then raise exception 'Amount must be positive'; end if;
  update public.suppliers set due_amount = due_amount - p_amount
    where id = p_supplier_id and business_id = v_business;
  if not found then raise exception 'Supplier not found'; end if;

  insert into public.supplier_payments
    (business_id, supplier_id, purchase_id, amount, payment_mode, payment_date, note, created_by)
  values (v_business, p_supplier_id, p_purchase_id, p_amount, p_mode, p_date, p_note, auth.uid())
  returning id into v_id;

  if p_purchase_id is not null then
    update public.purchases set
      paid_amount = paid_amount + p_amount,
      payment_status = (case when paid_amount + p_amount >= total then 'paid' else 'partial' end)::public.payment_status
      where id = p_purchase_id and business_id = v_business;
  else
    -- No specific purchase chosen: settle the oldest outstanding
    -- purchases first (FIFO) so purchase-level status stays in sync with
    -- the supplier's overall due.
    v_remaining := p_amount;
    for v_pur in
      select id, due_amount from public.purchases
      where supplier_id = p_supplier_id and business_id = v_business and due_amount > 0
      order by purchase_date asc
    loop
      exit when v_remaining <= 0;
      v_apply := least(v_remaining, v_pur.due_amount);
      update public.purchases set
        paid_amount = paid_amount + v_apply,
        payment_status = (case when paid_amount + v_apply >= total then 'paid' else 'partial' end)::public.payment_status
        where id = v_pur.id;
      v_remaining := v_remaining - v_apply;
    end loop;
  end if;

  perform public.log_audit('payment.made', 'supplier', p_supplier_id::text,
    jsonb_build_object('amount', p_amount));
  return v_id;
end $$;

-- ---------- Sale return (PRD 7.11): stock in, customer due down ----------
create or replace function public.create_sale_return(payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business  uuid := public.current_business_id();
  v_return_id uuid;
  v_return_no text;
  v_total     numeric(14,2) := 0;
  v_refund    numeric(14,2) := coalesce((payload ->> 'refund_amount')::numeric, 0);
  v_customer  uuid := (payload ->> 'customer_id')::uuid;
  v_item      jsonb;
begin
  if v_business is null then raise exception 'No business for current user'; end if;

  for v_item in select * from jsonb_array_elements(payload -> 'items') loop
    v_total := v_total + (v_item ->> 'line_total')::numeric;
  end loop;
  if v_refund > v_total then v_refund := v_total; end if;

  v_return_no := public.next_doc_no(v_business, 'sale_return', 'SR');

  insert into public.sale_returns
    (business_id, return_no, invoice_id, customer_id, total, refund_amount,
     refund_mode, notes, created_by)
  values
    (v_business, v_return_no, (payload ->> 'invoice_id')::uuid, v_customer, v_total,
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

-- ---------- Purchase return (PRD 7.12): stock out, supplier due down ----------
create or replace function public.create_purchase_return(payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business  uuid := public.current_business_id();
  v_return_id uuid;
  v_return_no text;
  v_total     numeric(14,2) := 0;
  v_received  numeric(14,2) := coalesce((payload ->> 'received_amount')::numeric, 0);
  v_supplier  uuid := (payload ->> 'supplier_id')::uuid;
  v_item      jsonb;
begin
  if v_business is null then raise exception 'No business for current user'; end if;

  for v_item in select * from jsonb_array_elements(payload -> 'items') loop
    v_total := v_total + (v_item ->> 'line_total')::numeric;
  end loop;
  if v_received > v_total then v_received := v_total; end if;

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

-- ---------- Enforce plan product limit on insert ----------
create or replace function public.check_product_limit()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_limit integer;
  v_count integer;
begin
  select pl.product_limit into v_limit
    from public.subscriptions s join public.plans pl on pl.id = s.plan_id
    where s.business_id = new.business_id order by s.created_at desc limit 1;
  if v_limit is not null then
    select count(*) into v_count from public.products where business_id = new.business_id;
    if v_count >= v_limit then
      raise exception 'Product limit (%) reached for your plan', v_limit;
    end if;
  end if;
  return new;
end $$;

create trigger trg_check_product_limit
  before insert on public.products
  for each row execute function public.check_product_limit();
