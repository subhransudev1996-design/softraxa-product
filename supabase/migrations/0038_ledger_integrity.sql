-- ============================================================
-- 0038_ledger_integrity.sql — launch release R0, batch 2
-- (PROJECT_ANALYSIS.md findings 8, 9, 19; LAUNCH_SPECIFICATION D27, PD21,
--  PD26, PD28)
--
--   A. Document credits: invoices/purchases get credit_amount; their due is
--      total - paid - credit. A return settles its own bill's balance first
--      (D27), so bill balances and party balances agree.
--   B. Sale returns: quantities are validated per product across the whole
--      request under a lock on the invoice; value comes from the original
--      bill (price, line discount, pro-rata bill discount), not the client;
--      serials must have been sold on that bill; the customer is the
--      invoice's customer; walk-in returns are refunded in full.
--   C. Purchase returns: same rules against the purchase and its supplier.
--   D. Bills with returns can't be edited or cancelled (that double-counted
--      stock and balances).
--   E. Payments: an invoice/purchase payment must belong to that customer /
--      supplier, be open, and not exceed its due; FIFO is oldest date then
--      document number (PD21).
--   F. Backfill credits for returns recorded before this migration.
--
-- Run AFTER 0037.
-- ============================================================

-- ============================================================
-- A. Document credits
-- ============================================================
alter table public.invoices  add column if not exists credit_amount numeric(14,2) not null default 0;
alter table public.purchases add column if not exists credit_amount numeric(14,2) not null default 0;

-- due_amount is generated; rebuild it to include credits.
alter table public.invoices drop column if exists due_amount;
alter table public.invoices add column due_amount numeric(14,2)
  generated always as (total - paid_amount - credit_amount) stored;
alter table public.purchases drop column if exists due_amount;
alter table public.purchases add column due_amount numeric(14,2)
  generated always as (total - paid_amount - credit_amount) stored;

create or replace function public.doc_payment_status(p_total numeric, p_paid numeric, p_credit numeric)
returns public.payment_status language sql immutable as $$
  select (case
    when coalesce(p_paid, 0) + coalesce(p_credit, 0) >= coalesce(p_total, 0) then 'paid'
    when coalesce(p_paid, 0) + coalesce(p_credit, 0) > 0 then 'partial'
    else 'unpaid' end)::public.payment_status;
$$;

-- Return credits are posted by the returns RPCs (returns permission), not
-- as payments. Extends guard_invoices from 0037 with that case.
create or replace function public.guard_invoices()
returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    perform public.assert_can('can_create_invoice');
    if new.invoice_type = 'gst' then
      perform public.assert_feature('gst_billing', 'GST billing');
    end if;
    if new.discount_amount > 0 and not public.has_permission('can_edit_prices') then
      raise exception 'You don''t have permission to give discounts' using errcode = '42501';
    end if;
    return new;
  end if;

  if row(new.business_id, new.invoice_no, new.invoice_type, new.invoice_date, new.customer_id,
         new.subtotal, new.discount_amount, new.tax_amount, new.round_off, new.total,
         new.is_cancelled, new.notes)
     is distinct from
     row(old.business_id, old.invoice_no, old.invoice_type, old.invoice_date, old.customer_id,
         old.subtotal, old.discount_amount, old.tax_amount, old.round_off, old.total,
         old.is_cancelled, old.notes) then
    perform public.assert_can('can_edit_invoices');
    if new.discount_amount > old.discount_amount and not public.has_permission('can_edit_prices') then
      raise exception 'You don''t have permission to give discounts' using errcode = '42501';
    end if;
    -- D. A bill with returns can't be edited or cancelled.
    if exists (select 1 from public.sale_returns where invoice_id = new.id) then
      raise exception 'This bill has returns, so it can''t be edited or cancelled — return the remaining items instead'
        using errcode = '42501';
    end if;
    if new.credit_amount is distinct from old.credit_amount then
      raise exception 'Return credits can only change through sale returns' using errcode = '42501';
    end if;
  elsif new.credit_amount is distinct from old.credit_amount then
    perform public.assert_can('can_manage_returns');
  elsif new.place_of_supply is distinct from old.place_of_supply then
    perform public.assert_can('can_create_invoice');
  elsif new.paid_amount is distinct from old.paid_amount
     or new.payment_status is distinct from old.payment_status then
    perform public.assert_can('can_record_payments', false);
  end if;
  return new;
end $$;

-- ============================================================
-- B. Sale returns
-- ============================================================
create or replace function public.create_sale_return(payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business   uuid := public.current_business_id();
  v_invoice_id uuid := (payload ->> 'invoice_id')::uuid;
  v_inv        record;
  v_customer   uuid := (payload ->> 'customer_id')::uuid;
  v_refund_req numeric(14,2) := greatest(coalesce((payload ->> 'refund_amount')::numeric, 0), 0);
  v_refund     numeric(14,2);
  v_total      numeric(14,2) := 0;
  v_apply      numeric(14,2) := 0;
  v_rest       numeric(14,2);
  v_return_id  uuid;
  v_return_no  text;
  v_item       jsonb;
  v_line       record;
  v_qty        numeric;
  v_serial     text;
  v_gross      numeric;
  v_factor     numeric := 1;
  v_unit_value numeric;
  v_unit_tax   numeric;
  v_unit_price numeric;
  v_value      numeric(14,2);
begin
  if v_business is null then raise exception 'No business for current user'; end if;
  if jsonb_array_length(coalesce(payload -> 'items', '[]'::jsonb)) = 0 then
    raise exception 'Add at least one item to return';
  end if;
  if exists (select 1 from jsonb_array_elements(payload -> 'items') i
             where coalesce((i ->> 'quantity')::numeric, 0) <= 0) then
    raise exception 'Return quantities must be greater than zero';
  end if;

  -- Duplicate serials inside one request.
  if exists (select 1 from jsonb_array_elements(payload -> 'items') i
             where coalesce(i ->> 'serial_no', '') <> ''
             group by i ->> 'serial_no' having count(*) > 1) then
    raise exception 'The same serial/IMEI appears twice in this return';
  end if;

  if v_invoice_id is not null then
    -- Lock the invoice: concurrent returns against it now run one at a time.
    select * into v_inv from public.invoices
      where id = v_invoice_id and business_id = v_business for update;
    if v_inv.id is null then raise exception 'Invoice not found'; end if;
    if v_inv.is_cancelled then raise exception 'Items can''t be returned from a cancelled bill'; end if;
    if v_inv.invoice_type = 'estimate' then raise exception 'Estimates can''t be returned'; end if;
    v_customer := v_inv.customer_id;       -- the bill's customer, never the client's

    select coalesce(sum(line_total), 0) into v_gross
      from public.invoice_items where invoice_id = v_invoice_id;
    if v_gross > 0 then
      v_factor := greatest(v_gross - v_inv.discount_amount, 0) / v_gross;   -- PD26 pro-rata bill discount
    end if;

    -- Quantities per product/variant across the whole request vs sold − already returned.
    for v_line in
      with req as (
        select (i ->> 'product_id')::uuid as pid, (i ->> 'variant_id')::uuid as vid,
               sum((i ->> 'quantity')::numeric) as qty, min(i ->> 'product_name') as name
        from jsonb_array_elements(payload -> 'items') i group by 1, 2),
      sold as (
        select product_id as pid, variant_id as vid, sum(quantity) as qty
        from public.invoice_items where invoice_id = v_invoice_id group by 1, 2),
      ret as (
        select sri.product_id as pid, sri.variant_id as vid, sum(sri.quantity) as qty
        from public.sale_return_items sri
        join public.sale_returns sr on sr.id = sri.sale_return_id
        where sr.invoice_id = v_invoice_id group by 1, 2)
      select req.name, req.qty, coalesce(sold.qty, 0) as sold_qty, coalesce(ret.qty, 0) as ret_qty
      from req
      left join sold on sold.pid is not distinct from req.pid and sold.vid is not distinct from req.vid
      left join ret  on ret.pid  is not distinct from req.pid and ret.vid  is not distinct from req.vid
    loop
      if v_line.sold_qty = 0 then
        raise exception '"%" is not on this bill', v_line.name;
      end if;
      if v_line.ret_qty + v_line.qty > v_line.sold_qty then
        raise exception 'Cannot return % of "%" — only % left to return on this bill (% already returned)',
          v_line.qty, v_line.name, greatest(v_line.sold_qty - v_line.ret_qty, 0), v_line.ret_qty;
      end if;
    end loop;

    -- Serials: sold on this bill, for that product, not returned yet.
    for v_item in select * from jsonb_array_elements(payload -> 'items') loop
      v_serial := coalesce(v_item ->> 'serial_no', '');
      continue when v_serial = '';
      if not exists (select 1 from public.invoice_items ii
                     where ii.invoice_id = v_invoice_id and ii.serial_no = v_serial
                       and ii.product_id is not distinct from (v_item ->> 'product_id')::uuid) then
        raise exception 'Serial/IMEI % was not sold on this bill', v_serial;
      end if;
      if exists (select 1 from public.sale_return_items sri
                 join public.sale_returns sr on sr.id = sri.sale_return_id
                 where sr.invoice_id = v_invoice_id and sri.serial_no = v_serial) then
        raise exception 'Serial/IMEI % has already been returned', v_serial;
      end if;
    end loop;
  elsif v_customer is not null
        and not exists (select 1 from public.customers where id = v_customer and business_id = v_business) then
    raise exception 'Customer not found';
  end if;

  v_return_no := public.next_doc_no(v_business, 'sale_return', 'SR');
  insert into public.sale_returns
    (business_id, return_no, invoice_id, customer_id, total, refund_amount, refund_mode, notes, created_by)
  values
    (v_business, v_return_no, v_invoice_id, v_customer, 0, 0,
     coalesce((payload ->> 'refund_mode')::public.payment_mode, 'cash'),
     coalesce(payload ->> 'notes', ''), auth.uid())
  returning id into v_return_id;

  for v_item in select * from jsonb_array_elements(payload -> 'items') loop
    v_qty := (v_item ->> 'quantity')::numeric;

    if v_invoice_id is not null then
      -- Value from the original bill (average over that product's lines).
      select sum(line_total) / sum(quantity),
             sum(tax_amount) / sum(quantity),
             sum(quantity * unit_price - discount_amount) / sum(quantity)
        into v_unit_value, v_unit_tax, v_unit_price
        from public.invoice_items
        where invoice_id = v_invoice_id
          and product_id is not distinct from (v_item ->> 'product_id')::uuid
          and variant_id is not distinct from (v_item ->> 'variant_id')::uuid;
      v_value := round(v_qty * v_unit_value * v_factor, 2);
      insert into public.sale_return_items
        (business_id, sale_return_id, product_id, variant_id, product_name,
         serial_no, quantity, unit_price, tax_amount, line_total)
      values
        (v_business, v_return_id, (v_item ->> 'product_id')::uuid, (v_item ->> 'variant_id')::uuid,
         v_item ->> 'product_name', coalesce(v_item ->> 'serial_no', ''), v_qty,
         round(v_unit_price * v_factor, 2), round(v_qty * v_unit_tax * v_factor, 2), v_value);
    else
      -- No bill to value against: the client's figures (returns permission required).
      v_value := round(coalesce((v_item ->> 'line_total')::numeric, 0), 2);
      if v_value < 0 then raise exception 'Return value can''t be negative'; end if;
      insert into public.sale_return_items
        (business_id, sale_return_id, product_id, variant_id, product_name,
         serial_no, quantity, unit_price, tax_amount, line_total)
      values
        (v_business, v_return_id, (v_item ->> 'product_id')::uuid, (v_item ->> 'variant_id')::uuid,
         v_item ->> 'product_name', coalesce(v_item ->> 'serial_no', ''), v_qty,
         coalesce((v_item ->> 'unit_price')::numeric, 0),
         coalesce((v_item ->> 'tax_amount')::numeric, 0), v_value);
    end if;
    v_total := v_total + v_value;

    if (v_item ->> 'product_id') is not null then
      insert into public.stock_movements
        (business_id, product_id, variant_id, movement_type, quantity,
         reference_type, reference_id, created_by)
      values
        (v_business, (v_item ->> 'product_id')::uuid, (v_item ->> 'variant_id')::uuid,
         'sale_return', v_qty, 'sale_return', v_return_id, auth.uid());

      v_serial := coalesce(v_item ->> 'serial_no', '');
      if v_serial <> '' then
        update public.product_serials set status = 'returned'
          where business_id = v_business and serial_no = v_serial;
      end if;
    end if;
  end loop;

  -- D27: settle the bill's own unpaid balance first; only the rest can be
  -- refunded or kept as customer credit. Walk-in customers get it refunded.
  if v_invoice_id is not null then
    v_apply := least(v_total, greatest(v_inv.total - v_inv.paid_amount - v_inv.credit_amount, 0));
  end if;
  v_rest := v_total - v_apply;
  v_refund := case when v_customer is null then v_rest else least(v_refund_req, v_rest) end;

  update public.sale_returns set total = v_total, refund_amount = v_refund where id = v_return_id;

  if v_apply > 0 then
    update public.invoices
       set credit_amount = credit_amount + v_apply,
           payment_status = public.doc_payment_status(total, paid_amount, credit_amount + v_apply)
     where id = v_invoice_id;
  end if;

  -- Customer balance: the bill credit plus any unrefunded remainder (kept
  -- as credit — a negative due — until advances arrive in R1).
  if v_customer is not null and (v_total - v_refund) > 0 then
    update public.customers set due_amount = due_amount - (v_total - v_refund)
      where id = v_customer and business_id = v_business;
  end if;

  perform public.log_audit('sale_return.created', 'sale_return', v_return_id::text,
    jsonb_build_object('return_no', v_return_no, 'total', v_total,
                       'applied_to_bill', v_apply, 'refund', v_refund));
  return jsonb_build_object('id', v_return_id, 'return_no', v_return_no, 'total', v_total,
                            'applied_to_bill', v_apply, 'refund', v_refund);
end $$;

-- ============================================================
-- C. Purchase returns
-- ============================================================
create or replace function public.create_purchase_return(payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business    uuid := public.current_business_id();
  v_purchase_id uuid := (payload ->> 'purchase_id')::uuid;
  v_pur         record;
  v_supplier    uuid := (payload ->> 'supplier_id')::uuid;
  v_recv_req    numeric(14,2) := greatest(coalesce((payload ->> 'received_amount')::numeric, 0), 0);
  v_received    numeric(14,2);
  v_total       numeric(14,2) := 0;
  v_apply       numeric(14,2) := 0;
  v_rest        numeric(14,2);
  v_return_id   uuid;
  v_return_no   text;
  v_item        jsonb;
  v_line        record;
  v_qty         numeric;
  v_stock       numeric;
  v_gross       numeric;
  v_factor      numeric := 1;
  v_unit_value  numeric;
  v_unit_tax    numeric;
  v_unit_price  numeric;
  v_value       numeric(14,2);
begin
  if v_business is null then raise exception 'No business for current user'; end if;
  if jsonb_array_length(coalesce(payload -> 'items', '[]'::jsonb)) = 0 then
    raise exception 'Add at least one item to return';
  end if;
  if exists (select 1 from jsonb_array_elements(payload -> 'items') i
             where coalesce((i ->> 'quantity')::numeric, 0) <= 0) then
    raise exception 'Return quantities must be greater than zero';
  end if;

  if v_purchase_id is not null then
    select * into v_pur from public.purchases
      where id = v_purchase_id and business_id = v_business for update;
    if v_pur.id is null then raise exception 'Purchase not found'; end if;
    v_supplier := v_pur.supplier_id;

    select coalesce(sum(line_total), 0) into v_gross
      from public.purchase_items where purchase_id = v_purchase_id;
    if v_gross > 0 then
      v_factor := greatest(v_gross - v_pur.discount_amount, 0) / v_gross;
    end if;
  elsif v_supplier is not null
        and not exists (select 1 from public.suppliers where id = v_supplier and business_id = v_business) then
    raise exception 'Supplier not found';
  end if;

  -- Per product/variant across the whole request: stock on hand and, with a
  -- purchase, purchased − already returned. Product rows are locked.
  for v_line in
    with req as (
      select (i ->> 'product_id')::uuid as pid, (i ->> 'variant_id')::uuid as vid,
             sum((i ->> 'quantity')::numeric) as qty, min(i ->> 'product_name') as name
      from jsonb_array_elements(payload -> 'items') i group by 1, 2)
    select req.*,
      (select coalesce(sum(quantity), 0) from public.purchase_items pi
        where pi.purchase_id = v_purchase_id
          and pi.product_id is not distinct from req.pid and pi.variant_id is not distinct from req.vid) as bought,
      (select coalesce(sum(pri.quantity), 0) from public.purchase_return_items pri
        join public.purchase_returns pr on pr.id = pri.purchase_return_id
        where pr.purchase_id = v_purchase_id
          and pri.product_id is not distinct from req.pid and pri.variant_id is not distinct from req.vid) as returned
    from req
  loop
    if v_line.pid is not null then
      if v_line.vid is not null then
        select current_stock into v_stock from public.product_variants
          where id = v_line.vid and product_id = v_line.pid and business_id = v_business for update;
      else
        select current_stock into v_stock from public.products
          where id = v_line.pid and business_id = v_business for update;
      end if;
      if coalesce(v_stock, 0) < v_line.qty then
        raise exception 'Cannot return % of "%" — only % in stock', v_line.qty, v_line.name, coalesce(v_stock, 0);
      end if;
    end if;
    if v_purchase_id is not null then
      if v_line.bought = 0 then
        raise exception '"%" is not on this purchase', v_line.name;
      end if;
      if v_line.returned + v_line.qty > v_line.bought then
        raise exception 'Cannot return % of "%" — only % left to return on this purchase (% already returned)',
          v_line.qty, v_line.name, greatest(v_line.bought - v_line.returned, 0), v_line.returned;
      end if;
    end if;
  end loop;

  v_return_no := public.next_doc_no(v_business, 'purchase_return', 'PR');
  insert into public.purchase_returns
    (business_id, return_no, purchase_id, supplier_id, total, received_amount, notes, created_by)
  values
    (v_business, v_return_no, v_purchase_id, v_supplier, 0, 0,
     coalesce(payload ->> 'notes', ''), auth.uid())
  returning id into v_return_id;

  for v_item in select * from jsonb_array_elements(payload -> 'items') loop
    v_qty := (v_item ->> 'quantity')::numeric;
    if v_purchase_id is not null then
      select sum(line_total) / sum(quantity),
             sum(tax_amount) / sum(quantity),
             sum(quantity * unit_price - discount_amount) / sum(quantity)
        into v_unit_value, v_unit_tax, v_unit_price
        from public.purchase_items
        where purchase_id = v_purchase_id
          and product_id is not distinct from (v_item ->> 'product_id')::uuid
          and variant_id is not distinct from (v_item ->> 'variant_id')::uuid;
      v_value := round(v_qty * v_unit_value * v_factor, 2);
      insert into public.purchase_return_items
        (business_id, purchase_return_id, product_id, variant_id, product_name,
         quantity, unit_price, tax_amount, line_total)
      values
        (v_business, v_return_id, (v_item ->> 'product_id')::uuid, (v_item ->> 'variant_id')::uuid,
         v_item ->> 'product_name', v_qty, round(v_unit_price * v_factor, 2),
         round(v_qty * v_unit_tax * v_factor, 2), v_value);
    else
      v_value := round(coalesce((v_item ->> 'line_total')::numeric, 0), 2);
      if v_value < 0 then raise exception 'Return value can''t be negative'; end if;
      insert into public.purchase_return_items
        (business_id, purchase_return_id, product_id, variant_id, product_name,
         quantity, unit_price, tax_amount, line_total)
      values
        (v_business, v_return_id, (v_item ->> 'product_id')::uuid, (v_item ->> 'variant_id')::uuid,
         v_item ->> 'product_name', v_qty, coalesce((v_item ->> 'unit_price')::numeric, 0),
         coalesce((v_item ->> 'tax_amount')::numeric, 0), v_value);
    end if;
    v_total := v_total + v_value;

    if (v_item ->> 'product_id') is not null then
      insert into public.stock_movements
        (business_id, product_id, variant_id, movement_type, quantity,
         reference_type, reference_id, created_by)
      values
        (v_business, (v_item ->> 'product_id')::uuid, (v_item ->> 'variant_id')::uuid,
         'purchase_return', -v_qty, 'purchase_return', v_return_id, auth.uid());
    end if;
  end loop;

  -- Settle the purchase's own unpaid balance first; the rest is money the
  -- supplier refunds or credit kept with the supplier.
  if v_purchase_id is not null then
    v_apply := least(v_total, greatest(v_pur.total - v_pur.paid_amount - v_pur.credit_amount, 0));
  end if;
  v_rest := v_total - v_apply;
  v_received := least(v_recv_req, v_rest);

  update public.purchase_returns set total = v_total, received_amount = v_received where id = v_return_id;

  if v_apply > 0 then
    update public.purchases
       set credit_amount = credit_amount + v_apply,
           payment_status = public.doc_payment_status(total, paid_amount, credit_amount + v_apply)
     where id = v_purchase_id;
  end if;

  if v_supplier is not null and (v_total - v_received) > 0 then
    update public.suppliers set due_amount = due_amount - (v_total - v_received)
      where id = v_supplier and business_id = v_business;
  end if;

  perform public.log_audit('purchase_return.created', 'purchase_return', v_return_id::text,
    jsonb_build_object('return_no', v_return_no, 'total', v_total,
                       'applied_to_bill', v_apply, 'received', v_received));
  return jsonb_build_object('id', v_return_id, 'return_no', v_return_no, 'total', v_total,
                            'applied_to_bill', v_apply, 'received', v_received);
end $$;

-- ============================================================
-- E. Payments
-- ============================================================
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
  if p_mode = 'credit' then raise exception 'Choose how the money was received (cash, UPI, card…)'; end if;

  -- Lock the customer first so concurrent payments apply one after another.
  perform 1 from public.customers where id = p_customer_id and business_id = v_business for update;
  if not found then raise exception 'Customer not found'; end if;

  if p_invoice_id is not null then
    select * into v_inv from public.invoices
      where id = p_invoice_id and business_id = v_business for update;
    if v_inv.id is null or v_inv.customer_id is distinct from p_customer_id then
      raise exception 'This bill does not belong to the selected customer';
    end if;
    if v_inv.is_cancelled then raise exception 'This bill is cancelled'; end if;
    if v_inv.invoice_type = 'estimate' then raise exception 'Estimates can''t be paid'; end if;
    if p_amount > v_inv.due_amount + 0.005 then
      raise exception 'Amount is more than the bill''s due (%)', v_inv.due_amount;
    end if;
  end if;

  update public.customers set due_amount = due_amount - p_amount
    where id = p_customer_id and business_id = v_business;

  insert into public.customer_payments
    (business_id, customer_id, invoice_id, amount, payment_mode, payment_date, note, created_by)
  values (v_business, p_customer_id, p_invoice_id, p_amount, p_mode, p_date, p_note, auth.uid())
  returning id into v_id;

  if p_invoice_id is not null then
    update public.invoices set
      paid_amount = paid_amount + p_amount,
      payment_status = public.doc_payment_status(total, paid_amount + p_amount, credit_amount)
      where id = p_invoice_id;
    insert into public.invoice_payments (business_id, invoice_id, amount, payment_mode, note)
    values (v_business, p_invoice_id, p_amount, p_mode, p_note);
  else
    -- FIFO: oldest bill first, document number as tie-breaker (PD21). Any
    -- excess stays as customer credit (a negative due).
    v_remaining := p_amount;
    for v_inv in
      select id, due_amount from public.invoices
      where customer_id = p_customer_id and business_id = v_business
        and not is_cancelled and invoice_type <> 'estimate' and due_amount > 0
      order by invoice_date asc, invoice_no asc
      for update
    loop
      exit when v_remaining <= 0;
      v_apply := least(v_remaining, v_inv.due_amount);
      update public.invoices set
        paid_amount = paid_amount + v_apply,
        payment_status = public.doc_payment_status(total, paid_amount + v_apply, credit_amount)
        where id = v_inv.id;
      insert into public.invoice_payments (business_id, invoice_id, amount, payment_mode, note)
      values (v_business, v_inv.id, v_apply, p_mode, p_note);
      v_remaining := v_remaining - v_apply;
    end loop;
  end if;

  perform public.log_audit('payment.received', 'customer', p_customer_id::text,
    jsonb_build_object('amount', p_amount, 'invoice_id', p_invoice_id));
  return v_id;
end $$;

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
  if p_mode = 'credit' then raise exception 'Choose how the money was paid (cash, UPI, card…)'; end if;

  perform 1 from public.suppliers where id = p_supplier_id and business_id = v_business for update;
  if not found then raise exception 'Supplier not found'; end if;

  if p_purchase_id is not null then
    select * into v_pur from public.purchases
      where id = p_purchase_id and business_id = v_business for update;
    if v_pur.id is null or v_pur.supplier_id is distinct from p_supplier_id then
      raise exception 'This purchase does not belong to the selected supplier';
    end if;
    if p_amount > v_pur.due_amount + 0.005 then
      raise exception 'Amount is more than the purchase''s due (%)', v_pur.due_amount;
    end if;
  end if;

  update public.suppliers set due_amount = due_amount - p_amount
    where id = p_supplier_id and business_id = v_business;

  insert into public.supplier_payments
    (business_id, supplier_id, purchase_id, amount, payment_mode, payment_date, note, created_by)
  values (v_business, p_supplier_id, p_purchase_id, p_amount, p_mode, p_date, p_note, auth.uid())
  returning id into v_id;

  if p_purchase_id is not null then
    update public.purchases set
      paid_amount = paid_amount + p_amount,
      payment_status = public.doc_payment_status(total, paid_amount + p_amount, credit_amount)
      where id = p_purchase_id;
  else
    v_remaining := p_amount;
    for v_pur in
      select id, due_amount from public.purchases
      where supplier_id = p_supplier_id and business_id = v_business and due_amount > 0
      order by purchase_date asc, purchase_no asc
      for update
    loop
      exit when v_remaining <= 0;
      v_apply := least(v_remaining, v_pur.due_amount);
      update public.purchases set
        paid_amount = paid_amount + v_apply,
        payment_status = public.doc_payment_status(total, paid_amount + v_apply, credit_amount)
        where id = v_pur.id;
      v_remaining := v_remaining - v_apply;
    end loop;
  end if;

  perform public.log_audit('payment.made', 'supplier', p_supplier_id::text,
    jsonb_build_object('amount', p_amount, 'purchase_id', p_purchase_id));
  return v_id;
end $$;

-- ============================================================
-- F. Backfill credits for returns made before this migration.
-- The old return functions already reduced the party balance by
-- (total − refund/received); only the bill-level credit was missing.
-- Party balances are unchanged here.
-- ============================================================
update public.invoices i
   set credit_amount = least(r.credit, greatest(i.total - i.paid_amount, 0))
  from (select invoice_id, sum(total - refund_amount) as credit
          from public.sale_returns where invoice_id is not null group by invoice_id) r
 where r.invoice_id = i.id and i.credit_amount = 0 and r.credit > 0;

update public.invoices
   set payment_status = public.doc_payment_status(total, paid_amount, credit_amount)
 where credit_amount > 0 and invoice_type <> 'estimate';

update public.purchases p
   set credit_amount = least(r.credit, greatest(p.total - p.paid_amount, 0))
  from (select purchase_id, sum(total - received_amount) as credit
          from public.purchase_returns where purchase_id is not null group by purchase_id) r
 where r.purchase_id = p.id and p.credit_amount = 0 and r.credit > 0;

update public.purchases
   set payment_status = public.doc_payment_status(total, paid_amount, credit_amount)
 where credit_amount > 0;
