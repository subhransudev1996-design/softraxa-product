-- ============================================================
-- 0063_correct_purchases_and_bills.sql — fix wrong entries
--
-- Shops enter purchases and bills with mistakes (wrong price, quantity,
-- supplier, customer, date). Bills could already be edited and cancelled;
-- purchases could not be changed at all.
--
--   A. update_purchase(id, payload): re-enter a purchase — supplier, bill
--      no, date, items, discount, extra charges, the amount paid with it,
--      payment mode, note. Stock, product cost, serials, GST split, the
--      supplier's due and the "Paid with purchase" payment are all
--      corrected in the same transaction.
--   B. delete_purchase(id, reason): removes a purchase entered by mistake,
--      reversing its stock, serials, supplier due and its payment. A full
--      copy is kept in the audit log.
--      Both refuse when the result would be wrong: items already sold
--      (stock would go below zero), serials already sold, purchases with
--      returns (fix those through returns), opening balances, and money
--      paid to the supplier later that was counted on this purchase.
--   C. change_invoice_customer(id, customer): moves a bill to the right
--      customer (or to walk-in when it is fully paid). The bill's due moves
--      between the two khatas; GSTIN / place of supply follow the customer.
--      Refused when payments from the old customer's khata are on the bill.
--   D. A walk-in bill edited below what was paid: the extra is given back
--      to the customer, so the bill's payments are reduced by that amount
--      (customer bills already turn it into an advance, 0041).
--
-- Run AFTER 0062.
-- ============================================================

-- ------------------------------------------------------------
-- helpers
-- ------------------------------------------------------------

-- Money paid at the time of the purchase ("Paid with purchase") vs. money
-- paid later and counted on it (direct payments or oldest-first).
create or replace function public.purchase_paid_split(p_purchase public.purchases)
returns table (initial numeric, later numeric)
language sql stable security definer set search_path = public as $$
  select i.amt, greatest(p_purchase.paid_amount - i.amt, 0)
  from (select case
                 when p_purchase.supplier_id is null then p_purchase.paid_amount
                 else coalesce((select sum(amount) from public.supplier_payments
                                 where purchase_id = p_purchase.id
                                   and note = 'Paid with purchase'), 0)
               end as amt) i;
$$;

-- Stock check for a change in quantities: for every product/variant whose
-- stock goes down, current stock must cover it. p_delta rows: (pid, vid,
-- delta, name). Locks the stock rows.
create or replace function public.assert_stock_covers(p_business uuid, p_delta jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  r       record;
  v_stock numeric;
begin
  for r in
    select (d ->> 'pid')::uuid as pid, (d ->> 'vid')::uuid as vid,
           sum((d ->> 'delta')::numeric) as delta, min(d ->> 'name') as name
    from jsonb_array_elements(p_delta) d
    where d ->> 'pid' is not null
    group by 1, 2
  loop
    continue when r.delta >= 0;
    if r.vid is not null then
      select current_stock into v_stock from public.product_variants
        where id = r.vid and business_id = p_business for update;
    else
      select current_stock into v_stock from public.products
        where id = r.pid and business_id = p_business for update;
    end if;
    if coalesce(v_stock, 0) + r.delta < -0.0005 then
      raise exception '"%": only % in stock now, so % can''t be taken off — the rest is already sold. Fix it with a stock adjustment or a sale return first.',
        r.name, coalesce(v_stock, 0), -r.delta;
    end if;
  end loop;
end $$;

-- ------------------------------------------------------------
-- A. update_purchase
-- ------------------------------------------------------------
create or replace function public.update_purchase(p_purchase_id uuid, payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business   uuid := public.current_business_id();
  v_pur        public.purchases;
  v_split      record;
  v_supplier   uuid := (payload ->> 'supplier_id')::uuid;
  v_sup_id     uuid;
  v_sup_name   text := '';
  v_sup_state  text := '';
  v_item       jsonb;
  v_old        record;
  v_qty        numeric;
  v_serial     text;
  v_delta      jsonb := '[]'::jsonb;
  v_old_serials text[];
  v_new_serials text[];
  v_subtotal   numeric(14,2) := 0;
  v_tax        numeric(14,2) := 0;
  v_discount   numeric(14,2) := coalesce((payload ->> 'discount_amount')::numeric, 0);
  v_extra      numeric(14,2) := coalesce((payload ->> 'extra_charges')::numeric, 0);
  v_round      numeric(6,2)  := coalesce((payload ->> 'round_off')::numeric, 0);
  v_total      numeric(14,2);
  v_initial    numeric(14,2) := greatest(coalesce((payload ->> 'paid_amount')::numeric, 0), 0);
  v_paid       numeric(14,2);
  v_mode       public.payment_mode := coalesce((payload ->> 'payment_mode')::public.payment_mode, 'cash');
  v_date       date := coalesce((payload ->> 'purchase_date')::date, current_date);
  v_old_due    numeric(14,2);
  v_new_due    numeric(14,2);
  v_pay_id     uuid;
begin
  if v_business is null then raise exception 'No business for current user'; end if;
  perform public.assert_can('can_manage_purchases');

  select * into v_pur from public.purchases
    where id = p_purchase_id and business_id = v_business for update;
  if v_pur.id is null then raise exception 'Purchase not found'; end if;
  if v_pur.is_opening then
    raise exception 'An opening balance can''t be edited here — change it from the supplier''s opening balance';
  end if;
  if exists (select 1 from public.purchase_returns where purchase_id = p_purchase_id) then
    raise exception 'This purchase has returns, so it can''t be edited — record another return instead';
  end if;
  if jsonb_array_length(coalesce(payload -> 'items', '[]'::jsonb)) = 0 then
    raise exception 'Add at least one product';
  end if;
  if exists (select 1 from jsonb_array_elements(payload -> 'items') i
             where coalesce((i ->> 'quantity')::numeric, 0) <= 0) then
    raise exception 'Quantities must be greater than zero';
  end if;
  if exists (select 1 from jsonb_array_elements(payload -> 'items') i
             where coalesce((i ->> 'unit_price')::numeric, 0) < 0) then
    raise exception 'Prices can''t be negative';
  end if;

  if v_supplier is not null then
    select id, name, coalesce(state_code, '') into v_sup_id, v_sup_name, v_sup_state
      from public.suppliers where id = v_supplier and business_id = v_business;
    if v_sup_id is null then raise exception 'Supplier not found'; end if;
  end if;

  select * into v_split from public.purchase_paid_split(v_pur);
  if v_supplier is distinct from v_pur.supplier_id and v_split.later > 0.005 then
    raise exception '% paid to % later is counted on this purchase, so its supplier can''t be changed',
      v_split.later, coalesce(nullif(v_pur.supplier_name, ''), 'the supplier');
  end if;

  -- Quantity change per product/variant: new − old. Stock must cover drops.
  for v_old in select product_id, variant_id, quantity, product_name
               from public.purchase_items where purchase_id = p_purchase_id loop
    v_delta := v_delta || jsonb_build_object('pid', v_old.product_id, 'vid', v_old.variant_id,
                                             'delta', -v_old.quantity, 'name', v_old.product_name);
  end loop;
  for v_item in select * from jsonb_array_elements(payload -> 'items') loop
    v_delta := v_delta || jsonb_build_object('pid', v_item ->> 'product_id', 'vid', v_item ->> 'variant_id',
                                             'delta', (v_item ->> 'quantity')::numeric,
                                             'name', v_item ->> 'product_name');
  end loop;
  perform public.assert_stock_covers(v_business, v_delta);

  -- Serials: ones taken off this purchase must still be in stock.
  select coalesce(array_agg(distinct s.v), '{}') into v_old_serials
    from public.purchase_items pi, unnest(pi.serial_nos) as s(v) where pi.purchase_id = p_purchase_id;
  select coalesce(array_agg(distinct s.v), '{}') into v_new_serials
    from jsonb_array_elements(payload -> 'items') as i(item),
         jsonb_array_elements_text(coalesce(i.item -> 'serial_nos', '[]'::jsonb)) as s(v);
  for v_serial in select unnest(v_old_serials) except select unnest(v_new_serials) loop
    if exists (select 1 from public.product_serials
               where business_id = v_business and serial_no = v_serial and status <> 'in_stock') then
      raise exception 'Serial/IMEI % is already sold, so it can''t be removed from this purchase', v_serial;
    end if;
    delete from public.product_serials
      where business_id = v_business and serial_no = v_serial and purchase_id = p_purchase_id;
  end loop;

  -- Undo the old lines' stock.
  for v_old in select * from public.purchase_items where purchase_id = p_purchase_id loop
    if v_old.product_id is not null then
      insert into public.stock_movements
        (business_id, product_id, variant_id, movement_type, quantity,
         reference_type, reference_id, note, created_by)
      values (v_business, v_old.product_id, v_old.variant_id, 'adjustment', -v_old.quantity,
              'purchase_edit', p_purchase_id, 'Purchase ' || v_pur.purchase_no || ' edited — original line reversed',
              auth.uid());
    end if;
  end loop;
  delete from public.purchase_items where purchase_id = p_purchase_id;

  -- Totals, the same way create_purchase works them out.
  for v_item in select * from jsonb_array_elements(payload -> 'items') loop
    v_subtotal := v_subtotal
      + (v_item ->> 'quantity')::numeric * (v_item ->> 'unit_price')::numeric
      - coalesce((v_item ->> 'discount_amount')::numeric, 0);
    v_tax := v_tax + coalesce((v_item ->> 'tax_amount')::numeric, 0);
  end loop;
  v_total := v_subtotal - v_discount + v_tax + v_extra + v_round;
  v_round := v_round + (round(v_total) - v_total);
  v_total := round(v_total);
  if v_total < 0 then raise exception 'The total can''t be below zero'; end if;
  if v_total + 0.005 < v_split.later then
    raise exception '% was paid later against this purchase, so its total can''t be less than that',
      v_split.later;
  end if;
  if v_mode = 'credit' then v_initial := 0; end if;
  v_initial := least(v_initial, v_total - v_split.later);
  v_paid := v_split.later + v_initial;

  -- Header first: the GST split of the new lines reads supplier_state.
  update public.purchases set
    supplier_id     = v_supplier,
    supplier_name   = case when v_supplier is null then coalesce(payload ->> 'supplier_name', '') else v_sup_name end,
    supplier_state  = case when v_supplier is null then ''
                           when v_supplier is distinct from v_pur.supplier_id then v_sup_state
                           else supplier_state end,
    bill_no         = coalesce(payload ->> 'bill_no', ''),
    purchase_date   = v_date,
    subtotal        = v_subtotal,
    discount_amount = v_discount,
    tax_amount      = v_tax,
    extra_charges   = v_extra,
    round_off       = v_round,
    total           = v_total,
    paid_amount     = v_paid,
    payment_status  = public.doc_payment_status(v_total, v_paid, credit_amount),
    payment_mode    = v_mode,
    notes           = coalesce(payload ->> 'notes', ''),
    updated_at      = now()
  where id = p_purchase_id;

  for v_item in select * from jsonb_array_elements(payload -> 'items') loop
    v_qty := (v_item ->> 'quantity')::numeric;
    insert into public.purchase_items
      (business_id, purchase_id, product_id, variant_id, product_name, quantity,
       unit_price, discount_amount, gst_rate, tax_amount, line_total, serial_nos)
    values
      (v_business, p_purchase_id,
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
         'purchase', v_qty, 'purchase', p_purchase_id, auth.uid());

      -- A wrong price here also went into the product's cost: correct it,
      -- unless a later purchase has set the cost since.
      update public.products set purchase_price = (v_item ->> 'unit_price')::numeric
        where id = (v_item ->> 'product_id')::uuid and business_id = v_business
          and coalesce((v_item ->> 'update_cost')::boolean, true)
          and not exists (
            select 1 from public.purchase_items pi join public.purchases p on p.id = pi.purchase_id
            where pi.product_id = (v_item ->> 'product_id')::uuid and p.id <> p_purchase_id
              and (p.purchase_date > v_date
                   or (p.purchase_date = v_date and p.created_at > v_pur.created_at)));

      -- Serials already on this purchase keep their row (and status — some
      -- may be sold); new ones are registered as create_purchase does.
      for v_serial in select * from jsonb_array_elements_text(coalesce(v_item -> 'serial_nos', '[]'::jsonb)) loop
        continue when v_serial = any(v_old_serials);
        insert into public.product_serials
          (business_id, product_id, variant_id, serial_no, status, purchase_id)
        values (v_business, (v_item ->> 'product_id')::uuid, (v_item ->> 'variant_id')::uuid,
                v_serial, 'in_stock', p_purchase_id)
        on conflict (business_id, serial_no)
        do update set status = 'in_stock', purchase_id = excluded.purchase_id;
      end loop;
    end if;
  end loop;

  -- The payment made with the purchase: corrected in place.
  if v_supplier is not null then
    select id into v_pay_id from public.supplier_payments
      where purchase_id = p_purchase_id and note = 'Paid with purchase'
      order by created_at limit 1;
    delete from public.supplier_payments
      where purchase_id = p_purchase_id and note = 'Paid with purchase'
        and id is distinct from v_pay_id;
    if v_initial > 0 then
      if v_pay_id is not null then
        update public.supplier_payments
          set amount = v_initial, payment_mode = v_mode, supplier_id = v_supplier
          where id = v_pay_id;
      else
        insert into public.supplier_payments
          (business_id, supplier_id, purchase_id, amount, payment_mode, payment_date, note, created_by)
        values (v_business, v_supplier, p_purchase_id, v_initial, v_mode, v_date,
                'Paid with purchase', auth.uid());
      end if;
    elsif v_pay_id is not null then
      delete from public.supplier_payments where id = v_pay_id;
    end if;
  elsif v_pur.supplier_id is not null then
    -- Supplier removed (only possible with nothing paid later): its payment goes too.
    delete from public.supplier_payments
      where purchase_id = p_purchase_id and note = 'Paid with purchase';
  end if;

  -- Supplier dues: take the old purchase's unpaid part off, put the new one on.
  v_old_due := greatest(v_pur.total - v_pur.paid_amount - v_pur.credit_amount, 0);
  v_new_due := greatest(v_total - v_paid - v_pur.credit_amount, 0);
  if v_pur.supplier_id is not null and v_old_due <> 0 then
    update public.suppliers set due_amount = due_amount - v_old_due
      where id = v_pur.supplier_id and business_id = v_business;
  end if;
  if v_supplier is not null and v_new_due <> 0 then
    update public.suppliers set due_amount = due_amount + v_new_due
      where id = v_supplier and business_id = v_business;
  end if;

  perform public.log_audit('purchase.updated', 'purchase', p_purchase_id::text,
    jsonb_build_object('purchase_no', v_pur.purchase_no,
                       'before', jsonb_build_object('total', v_pur.total, 'paid', v_pur.paid_amount,
                                                    'supplier', v_pur.supplier_name, 'date', v_pur.purchase_date),
                       'after', jsonb_build_object('total', v_total, 'paid', v_paid,
                                                   'supplier_id', v_supplier, 'date', v_date)));
  return jsonb_build_object('id', p_purchase_id, 'purchase_no', v_pur.purchase_no,
                            'total', v_total, 'paid', v_paid);
end $$;

-- ------------------------------------------------------------
-- B. delete_purchase
-- ------------------------------------------------------------
create or replace function public.delete_purchase(p_purchase_id uuid, p_reason text default '')
returns void language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_pur      public.purchases;
  v_split    record;
  v_item     record;
  v_delta    jsonb := '[]'::jsonb;
  v_serial   text;
  v_snapshot jsonb;
begin
  if v_business is null then raise exception 'No business for current user'; end if;
  perform public.assert_can('can_manage_purchases');

  select * into v_pur from public.purchases
    where id = p_purchase_id and business_id = v_business for update;
  if v_pur.id is null then raise exception 'Purchase not found'; end if;
  if v_pur.is_opening then
    raise exception 'An opening balance can''t be deleted here — change it from the supplier''s opening balance';
  end if;
  if exists (select 1 from public.purchase_returns where purchase_id = p_purchase_id) then
    raise exception 'This purchase has returns, so it can''t be deleted';
  end if;
  select * into v_split from public.purchase_paid_split(v_pur);
  if v_split.later > 0.005 then
    raise exception '% paid to % later is counted on this purchase, so it can''t be deleted — edit it instead',
      v_split.later, coalesce(nullif(v_pur.supplier_name, ''), 'the supplier');
  end if;

  for v_item in select * from public.purchase_items where purchase_id = p_purchase_id loop
    v_delta := v_delta || jsonb_build_object('pid', v_item.product_id, 'vid', v_item.variant_id,
                                             'delta', -v_item.quantity, 'name', v_item.product_name);
  end loop;
  perform public.assert_stock_covers(v_business, v_delta);

  for v_serial in select distinct unnest(serial_nos) from public.purchase_items where purchase_id = p_purchase_id loop
    if exists (select 1 from public.product_serials
               where business_id = v_business and serial_no = v_serial and status <> 'in_stock') then
      raise exception 'Serial/IMEI % from this purchase is already sold, so it can''t be deleted', v_serial;
    end if;
    delete from public.product_serials
      where business_id = v_business and serial_no = v_serial and purchase_id = p_purchase_id;
  end loop;

  select jsonb_build_object(
           'purchase', to_jsonb(v_pur),
           'items', coalesce((select jsonb_agg(to_jsonb(pi)) from public.purchase_items pi
                              where pi.purchase_id = p_purchase_id), '[]'::jsonb),
           'reason', coalesce(p_reason, ''))
    into v_snapshot;

  for v_item in select * from public.purchase_items where purchase_id = p_purchase_id loop
    if v_item.product_id is not null then
      insert into public.stock_movements
        (business_id, product_id, variant_id, movement_type, quantity,
         reference_type, reference_id, note, created_by)
      values (v_business, v_item.product_id, v_item.variant_id, 'adjustment', -v_item.quantity,
              'purchase_delete', p_purchase_id, 'Purchase ' || v_pur.purchase_no || ' deleted', auth.uid());
    end if;
  end loop;

  if v_pur.supplier_id is not null then
    update public.suppliers
      set due_amount = due_amount - greatest(v_pur.total - v_pur.paid_amount - v_pur.credit_amount, 0)
      where id = v_pur.supplier_id and business_id = v_business;
    delete from public.supplier_payments
      where purchase_id = p_purchase_id and note = 'Paid with purchase';
  end if;

  delete from public.purchases where id = p_purchase_id;   -- items cascade

  perform public.log_audit('purchase.deleted', 'purchase', p_purchase_id::text, v_snapshot);
end $$;

-- ------------------------------------------------------------
-- C. change_invoice_customer
-- ------------------------------------------------------------
create or replace function public.change_invoice_customer(p_invoice_id uuid, p_customer_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_inv      record;
  v_new_id    uuid;
  v_new_name  text := '';
  v_new_phone text := '';
  v_new_state text := '';
  v_due      numeric(14,2);
  v_pos      text;
begin
  if v_business is null then raise exception 'No business for current user'; end if;
  perform public.assert_can('can_edit_invoices');

  select * into v_inv from public.invoices
    where id = p_invoice_id and business_id = v_business for update;
  if v_inv.id is null then raise exception 'Bill not found'; end if;
  if v_inv.is_cancelled then raise exception 'This bill is cancelled'; end if;
  if v_inv.invoice_type = 'opening' then raise exception 'An opening balance can''t be moved to another customer'; end if;
  if v_inv.customer_id is not distinct from p_customer_id then
    return jsonb_build_object('id', p_invoice_id, 'changed', false);
  end if;
  if exists (select 1 from public.sale_returns where invoice_id = p_invoice_id) then
    raise exception 'This bill has returns, so its customer can''t be changed';
  end if;
  -- Payments taken through the old customer's khata stay with that customer.
  if exists (select 1 from public.invoice_payments
             where invoice_id = p_invoice_id and not reversed
               and (customer_payment_id is not null or is_advance))
     or exists (select 1 from public.customer_payment_allocations where invoice_id = p_invoice_id)
     or exists (select 1 from public.customer_payments
                where invoice_id = p_invoice_id and reversed_at is null) then
    raise exception 'Payments from %''s khata are on this bill. Reverse those payments first, or cancel the bill and make a new one.',
      coalesce(nullif(v_inv.customer_name, ''), 'the customer');
  end if;

  if p_customer_id is not null then
    select id, name, coalesce(phone, ''), coalesce(state_code, '')
      into v_new_id, v_new_name, v_new_phone, v_new_state
      from public.customers where id = p_customer_id and business_id = v_business;
    if v_new_id is null then raise exception 'Customer not found'; end if;
  end if;

  v_due := case when v_inv.invoice_type = 'estimate' then 0
                else greatest(v_inv.total - v_inv.paid_amount - v_inv.credit_amount, 0) end;
  if p_customer_id is null and v_due > 0.005 then
    raise exception 'A walk-in bill must be fully paid. Choose a customer, or collect the % due first.', v_due;
  end if;

  -- Place of supply follows the buyer (their state, else the shop's).
  select coalesce(nullif(v_new_state, ''), b.state_code, '') into v_pos
    from public.businesses b where b.id = v_business;

  if v_due > 0 then
    if v_inv.customer_id is not null then
      update public.customers set due_amount = due_amount - v_due
        where id = v_inv.customer_id and business_id = v_business;
    end if;
    update public.customers set due_amount = due_amount + v_due
      where id = p_customer_id and business_id = v_business;
  end if;

  update public.invoices set
    customer_id     = p_customer_id,
    customer_name   = v_new_name,
    customer_phone  = v_new_phone,
    place_of_supply = coalesce(v_pos, place_of_supply),
    updated_at      = now()
  where id = p_invoice_id;

  perform public.log_audit('invoice.customer_changed', 'invoice', p_invoice_id::text,
    jsonb_build_object('invoice_no', v_inv.invoice_no,
                       'from', v_inv.customer_name, 'to', coalesce(nullif(v_new_name, ''), 'Walk-in'),
                       'due_moved', v_due));
  return jsonb_build_object('id', p_invoice_id, 'changed', true, 'due_moved', v_due);
end $$;

-- ------------------------------------------------------------
-- D. Overpaid bills after an edit (replaces 0041's version):
--    customer bills — the extra becomes an advance (unchanged);
--    walk-in bills  — the extra is handed back, so the bill's payments are
--                     reduced by it, newest first.
-- ------------------------------------------------------------
create or replace function public.settle_overpaid_invoice()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_move numeric(14,2);
  v_left numeric(14,2);
  v_pay  record;
begin
  if new.is_cancelled or new.invoice_type = 'estimate' then
    return new;
  end if;
  v_move := least(-(new.total - new.paid_amount - new.credit_amount), new.paid_amount);
  if v_move <= 0.005 then return new; end if;

  if new.customer_id is not null then
    update public.invoices set
      paid_amount = paid_amount - v_move,
      payment_status = public.doc_payment_status(total, paid_amount - v_move, credit_amount)
      where id = new.id;
    update public.customers set due_amount = due_amount + v_move
      where id = new.customer_id and business_id = new.business_id;
    perform public.post_customer_advance(new.business_id, new.customer_id, v_move, 'overpaid_bill',
      p_invoice_id => new.id, p_note => 'Bill ' || new.invoice_no || ' reduced below the amount paid');
    return new;
  end if;

  v_left := v_move;
  for v_pay in
    select id, amount from public.invoice_payments
    where invoice_id = new.id and not reversed and not is_advance
    order by created_at desc, id desc
  loop
    exit when v_left <= 0;
    if v_pay.amount <= v_left then
      delete from public.invoice_payments where id = v_pay.id;
      v_left := v_left - v_pay.amount;
    else
      update public.invoice_payments set amount = amount - v_left where id = v_pay.id;
      v_left := 0;
    end if;
  end loop;
  update public.invoices set
    paid_amount = paid_amount - v_move,
    payment_status = public.doc_payment_status(total, paid_amount - v_move, credit_amount)
    where id = new.id;
  perform public.log_audit('invoice.change_returned', 'invoice', new.id::text,
    jsonb_build_object('invoice_no', new.invoice_no, 'given_back', v_move));
  return new;
end $$;

-- ------------------------------------------------------------
-- Grants
-- ------------------------------------------------------------
revoke execute on function public.purchase_paid_split(public.purchases) from public, anon, authenticated;
revoke execute on function public.assert_stock_covers(uuid, jsonb) from public, anon, authenticated;
revoke execute on function public.settle_overpaid_invoice() from public, anon, authenticated;
revoke execute on function public.update_purchase(uuid, jsonb) from public, anon;
revoke execute on function public.delete_purchase(uuid, text) from public, anon;
revoke execute on function public.change_invoice_customer(uuid, uuid) from public, anon;
grant execute on function public.update_purchase(uuid, jsonb) to authenticated;
grant execute on function public.delete_purchase(uuid, text) to authenticated;
grant execute on function public.change_invoice_customer(uuid, uuid) to authenticated;
