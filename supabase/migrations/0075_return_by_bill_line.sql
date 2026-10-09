-- ============================================================
-- 0075_return_by_bill_line.sql
-- A return is valued at the price of the bill line it came from.
--
-- Until now each returned item was valued at the AVERAGE of every line of
-- that product on the bill. With the same product sold by the box (Box of
-- 10 at Rs 95 = Rs 9.50 a piece) and loose (Rs 10 a piece) on one bill, a
-- loose piece came back at Rs 9.62 and a box at Rs 96.15, and the return
-- screen showed a different amount from what was saved.
--
-- Now the app names the bill line (invoice_item_id) for each returned item:
--   * its value is that line's own (after the line discount, then the
--     bill discount share as before);
--   * its quantity is checked against that line (sold − returned on it),
--     on top of the per-product check that also counts older returns;
--   * sale_return_items.invoice_item_id records the line.
-- An item without invoice_item_id (older app versions) is valued as before.
-- Everything else in create_sale_return is unchanged from 0042.
--
-- Run AFTER 0074.
-- ============================================================

alter table public.sale_return_items
  add column if not exists invoice_item_id uuid references public.invoice_items(id) on delete set null;
create index if not exists idx_sale_return_items_invoice_item
  on public.sale_return_items(invoice_item_id) where invoice_item_id is not null;

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
  v_advance    numeric(14,2) := 0;
  v_condition  text;
  v_exchange   boolean := coalesce((payload ->> 'exchange')::boolean, false);
  v_credit     numeric(14,2) := 0;
  v_window     integer;
  v_age        integer;
  v_override   text := trim(coalesce(payload ->> 'window_override_reason', ''));
begin
  if v_business is null then raise exception 'No business for current user'; end if;
  if jsonb_array_length(coalesce(payload -> 'items', '[]'::jsonb)) = 0 then
    raise exception 'Add at least one item to return';
  end if;
  -- D28: each returned line has a condition; only sellable goes back to stock.
  if exists (select 1 from jsonb_array_elements(payload -> 'items') i
             where coalesce(i ->> 'condition', 'sellable')
                   not in ('sellable', 'inspection', 'damaged', 'scrap')) then
    raise exception 'Unknown condition for a returned item';
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

    -- PD25: return window from the invoice date (0 = no limit). The owner
    -- can accept a late return with a reason.
    select return_window_days into v_window from public.businesses where id = v_business;
    v_age := public.ist_date(now()) - public.ist_date(v_inv.invoice_date);
    if coalesce(v_window, 0) > 0 and v_age > v_window then
      if v_override = '' then
        raise exception 'This bill is % days old; returns are accepted within % days. The owner can accept it with a reason.',
          v_age, v_window;
      end if;
      if not public.has_permission('owner') then
        raise exception 'Only the owner can accept a return after % days', v_window
          using errcode = '42501';
      end if;
    else
      v_override := '';
    end if;

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

    -- 0075: lines the app names (invoice_item_id) are also checked one by
    -- one, so a box line and a loose line of the same product stay apart.
    for v_line in
      with req as (
        select (i ->> 'invoice_item_id')::uuid as lid,
               (i ->> 'product_id')::uuid as pid, (i ->> 'variant_id')::uuid as vid,
               sum((i ->> 'quantity')::numeric) as qty, min(i ->> 'product_name') as name
        from jsonb_array_elements(payload -> 'items') i
        where nullif(i ->> 'invoice_item_id', '') is not null
        group by 1, 2, 3),
      ret as (
        select sri.invoice_item_id as lid, sum(sri.quantity) as qty
        from public.sale_return_items sri
        join public.sale_returns sr on sr.id = sri.sale_return_id
        where sr.invoice_id = v_invoice_id and sri.invoice_item_id is not null
        group by 1)
      select req.name, req.qty, ii.id as line_id, coalesce(ii.quantity, 0) as sold_qty,
             coalesce(ret.qty, 0) as ret_qty
      from req
      left join public.invoice_items ii
        on ii.id = req.lid and ii.invoice_id = v_invoice_id
       and ii.product_id is not distinct from req.pid and ii.variant_id is not distinct from req.vid
      left join ret on ret.lid = req.lid
    loop
      if v_line.line_id is null then
        raise exception '"%" is not on this bill', v_line.name;
      end if;
      if v_line.ret_qty + v_line.qty > v_line.sold_qty then
        raise exception 'Cannot return % of "%" from that line — only % left to return on it',
          v_line.qty, v_line.name, greatest(v_line.sold_qty - v_line.ret_qty, 0);
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
  else
    v_override := '';
    if v_customer is not null
       and not exists (select 1 from public.customers where id = v_customer and business_id = v_business) then
      raise exception 'Customer not found';
    end if;
  end if;

  v_return_no := public.next_doc_no(v_business, 'sale_return', 'SR');
  insert into public.sale_returns
    (business_id, return_no, invoice_id, customer_id, total, refund_amount, refund_mode, notes,
     created_by, window_override_reason)
  values
    (v_business, v_return_no, v_invoice_id, v_customer, 0, 0,
     coalesce((payload ->> 'refund_mode')::public.payment_mode, 'cash'),
     coalesce(payload ->> 'notes', ''), auth.uid(), v_override)
  returning id into v_return_id;

  for v_item in select * from jsonb_array_elements(payload -> 'items') loop
    v_qty := (v_item ->> 'quantity')::numeric;
    v_condition := coalesce(v_item ->> 'condition', 'sellable');

    if v_invoice_id is not null then
      if nullif(v_item ->> 'invoice_item_id', '') is not null then
        -- 0075: the value of the bill line it came from — a box returned at
        -- the box price, a loose piece at the loose price, after the line's
        -- own discount.
        select line_total / quantity, tax_amount / quantity,
               (quantity * unit_price - discount_amount) / quantity
          into v_unit_value, v_unit_tax, v_unit_price
          from public.invoice_items
          where id = (v_item ->> 'invoice_item_id')::uuid and invoice_id = v_invoice_id
            and quantity > 0;
      else
        -- Older apps: the average over that product's lines on the bill.
        select sum(line_total) / sum(quantity),
               sum(tax_amount) / sum(quantity),
               sum(quantity * unit_price - discount_amount) / sum(quantity)
          into v_unit_value, v_unit_tax, v_unit_price
          from public.invoice_items
          where invoice_id = v_invoice_id
            and product_id is not distinct from (v_item ->> 'product_id')::uuid
            and variant_id is not distinct from (v_item ->> 'variant_id')::uuid;
      end if;
      v_value := round(v_qty * v_unit_value * v_factor, 2);
      insert into public.sale_return_items
        (business_id, sale_return_id, product_id, variant_id, product_name,
         serial_no, quantity, unit_price, tax_amount, line_total, condition, invoice_item_id)
      values
        (v_business, v_return_id, (v_item ->> 'product_id')::uuid, (v_item ->> 'variant_id')::uuid,
         v_item ->> 'product_name', coalesce(v_item ->> 'serial_no', ''), v_qty,
         round(v_unit_price * v_factor, 2), round(v_qty * v_unit_tax * v_factor, 2), v_value,
         v_condition, nullif(v_item ->> 'invoice_item_id', '')::uuid);
    else
      -- No bill to value against: the client's figures (returns permission required).
      v_value := round(coalesce((v_item ->> 'line_total')::numeric, 0), 2);
      if v_value < 0 then raise exception 'Return value can''t be negative'; end if;
      insert into public.sale_return_items
        (business_id, sale_return_id, product_id, variant_id, product_name,
         serial_no, quantity, unit_price, tax_amount, line_total, condition)
      values
        (v_business, v_return_id, (v_item ->> 'product_id')::uuid, (v_item ->> 'variant_id')::uuid,
         v_item ->> 'product_name', coalesce(v_item ->> 'serial_no', ''), v_qty,
         coalesce((v_item ->> 'unit_price')::numeric, 0),
         coalesce((v_item ->> 'tax_amount')::numeric, 0), v_value, v_condition);
    end if;
    v_total := v_total + v_value;

    if (v_item ->> 'product_id') is not null then
      v_serial := coalesce(v_item ->> 'serial_no', '');
      if v_condition = 'sellable' then
        -- Back into sellable stock.
        insert into public.stock_movements
          (business_id, product_id, variant_id, movement_type, quantity,
           reference_type, reference_id, created_by)
        values
          (v_business, (v_item ->> 'product_id')::uuid, (v_item ->> 'variant_id')::uuid,
           'sale_return', v_qty, 'sale_return', v_return_id, auth.uid());
      else
        -- Received but held out of sale (D28): awaiting inspection, damaged or scrap.
        insert into public.stock_hold_entries
          (business_id, product_id, variant_id, condition, quantity, serial_no, kind,
           sale_return_id, note, created_by)
        values
          (v_business, (v_item ->> 'product_id')::uuid, (v_item ->> 'variant_id')::uuid,
           v_condition, v_qty, v_serial, 'return', v_return_id, 'Return ' || v_return_no, auth.uid());
      end if;

      if v_serial <> '' then
        update public.product_serials
           set status = case v_condition when 'sellable' then 'in_stock'
                                         when 'inspection' then 'returned'
                                         else 'damaged' end,
               invoice_id = case when v_condition = 'sellable' then null else invoice_id end
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
  if v_exchange then
    -- D29: the remainder is credit for the replacement sale; create_exchange
    -- settles it (used, refunded or kept) in the same transaction.
    v_refund := 0;
    v_credit := v_rest;
  else
    v_refund := case when v_customer is null then v_rest else least(v_refund_req, v_rest) end;
  end if;

  update public.sale_returns set total = v_total, refund_amount = v_refund where id = v_return_id;

  if v_apply > 0 then
    update public.invoices
       set credit_amount = credit_amount + v_apply,
           payment_status = public.doc_payment_status(total, paid_amount, credit_amount + v_apply)
     where id = v_invoice_id;
  end if;

  -- Customer balance (0041): the bill credit lowers their due; whatever is
  -- neither applied to the bill nor refunded becomes an advance.
  if v_customer is not null and v_apply > 0 then
    update public.customers set due_amount = due_amount - v_apply
      where id = v_customer and business_id = v_business;
  end if;
  v_advance := v_rest - v_refund - v_credit;
  if v_customer is not null and v_advance > 0 then
    perform public.post_customer_advance(v_business, v_customer, v_advance, 'return_credit',
      p_sale_return_id => v_return_id, p_invoice_id => v_invoice_id,
      p_note => 'Return ' || v_return_no);
  end if;

  perform public.log_audit('sale_return.created', 'sale_return', v_return_id::text,
    jsonb_build_object('return_no', v_return_no, 'total', v_total,
                       'applied_to_bill', v_apply, 'refund', v_refund, 'advance', v_advance,
                       'exchange_credit', v_credit, 'window_override', v_override));
  return jsonb_build_object('id', v_return_id, 'return_no', v_return_no, 'total', v_total,
                            'applied_to_bill', v_apply, 'refund', v_refund, 'advance', v_advance,
                            'exchange_credit', v_credit);
end $$;

