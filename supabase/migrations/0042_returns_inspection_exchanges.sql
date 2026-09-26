-- ============================================================
-- 0042_returns_inspection_exchanges.sql — release R1, batch 3
-- (LAUNCH_SPECIFICATION.md D28, D29, PD25, PD29, PD30)
--
--   A. Returned goods are classified per line: sellable (back into stock),
--      awaiting inspection, damaged or scrap (held out of sale). Held goods
--      have their own ledger; releasing them to sale needs stock
--      permission (PD29), reclassifying needs returns permission.
--   B. Return window (PD25): 30 days by default, a store setting; the
--      owner can accept a late return with a reason.
--   C. Exchanges (D29): one transaction = a linked return + a new bill.
--      Return credit settles the original bill first (D27), then pays the
--      replacement; any excess is refunded or kept as advance. Requests
--      carry an id, so a retried exchange is not posted twice.
--
-- Run AFTER 0041.
-- ============================================================

-- ============================================================
-- A. Condition and held stock
-- ============================================================
alter table public.sale_return_items add column if not exists condition text not null default 'sellable';
alter table public.sale_return_items drop constraint if exists sale_return_items_condition_check;
alter table public.sale_return_items add constraint sale_return_items_condition_check
  check (condition in ('sellable', 'inspection', 'damaged', 'scrap'));

create table if not exists public.stock_hold_entries (
  id             uuid primary key default gen_random_uuid(),
  business_id    uuid not null references public.businesses(id) on delete cascade,
  product_id     uuid not null references public.products(id) on delete cascade,
  variant_id     uuid references public.product_variants(id) on delete cascade,
  condition      text not null check (condition in ('inspection', 'damaged', 'scrap')),
  quantity       numeric(12,3) not null check (quantity <> 0),   -- + into this state, − out of it
  serial_no      text not null default '',
  kind           text not null check (kind in ('return', 'reclassify', 'release', 'dispose')),
  sale_return_id uuid references public.sale_returns(id) on delete set null,
  note           text not null default '',
  created_by     uuid references public.profiles(id),
  created_at     timestamptz not null default now()
);
create index if not exists idx_stock_hold_entries_product
  on public.stock_hold_entries (business_id, product_id, variant_id, condition);

alter table public.stock_hold_entries enable row level security;
drop policy if exists "tenant read" on public.stock_hold_entries;
drop policy if exists "admin all" on public.stock_hold_entries;
create policy "tenant read" on public.stock_hold_entries for select
  using (business_id = (select public.current_business_id()));
create policy "admin all" on public.stock_hold_entries for all
  using (public.is_admin()) with check (public.is_admin());

drop trigger if exists trg_00_tenant_refs on public.stock_hold_entries;
create trigger trg_00_tenant_refs before insert or update on public.stock_hold_entries
  for each row execute function public.enforce_tenant_refs(
    'product_id=products', 'variant_id=product_variants', 'sale_return_id=sale_returns');

-- Current held quantities (RLS of the base table applies).
create or replace view public.stock_holds with (security_invoker = true) as
  select h.business_id, h.product_id, h.variant_id, h.condition, h.serial_no,
         p.name as product_name, coalesce(v.name, '') as variant_name,
         sum(h.quantity) as quantity, max(h.created_at) as last_change
  from public.stock_hold_entries h
  join public.products p on p.id = h.product_id
  left join public.product_variants v on v.id = h.variant_id
  group by h.business_id, h.product_id, h.variant_id, h.condition, h.serial_no, p.name, v.name
  having sum(h.quantity) <> 0;
grant select on public.stock_holds to authenticated;

-- Move held goods: between conditions, released to sale, or disposed of.
-- Returns what is left in the source condition.
create or replace function public.move_held_stock(
  p_product_id uuid,
  p_variant_id uuid,
  p_from       text,
  p_to         text,
  p_quantity   numeric,
  p_serial_no  text default '',
  p_note       text default ''
) returns numeric language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_serial   text := coalesce(trim(p_serial_no), '');
  v_balance  numeric;
  v_kind     text;
begin
  if p_from not in ('inspection', 'damaged', 'scrap') then
    raise exception 'Goods can only be moved out of inspection, damaged or scrap';
  end if;
  if p_to not in ('sellable', 'inspection', 'damaged', 'scrap', 'disposed') or p_to = p_from then
    raise exception 'Choose where the goods go';
  end if;
  if p_quantity is null or p_quantity <= 0 then raise exception 'Quantity must be positive'; end if;
  if v_serial <> '' and p_quantity <> 1 then
    raise exception 'A serial-numbered item moves one at a time';
  end if;

  -- PD29: back to sale (or written off) needs stock permission; moving
  -- between hold states is part of handling returns.
  if p_to in ('sellable', 'disposed') then
    perform public.assert_can('can_manage_stock');
  else
    perform public.assert_can('can_manage_returns');
  end if;

  perform 1 from public.products where id = p_product_id and business_id = v_business for update;
  if not found then raise exception 'Product not found'; end if;

  select coalesce(sum(quantity), 0) into v_balance from public.stock_hold_entries
    where business_id = v_business and product_id = p_product_id
      and variant_id is not distinct from p_variant_id
      and condition = p_from and serial_no = v_serial;
  if v_balance < p_quantity - 0.0005 then
    raise exception 'Only % held as %', v_balance, p_from;
  end if;

  v_kind := case p_to when 'sellable' then 'release' when 'disposed' then 'dispose' else 'reclassify' end;
  insert into public.stock_hold_entries
    (business_id, product_id, variant_id, condition, quantity, serial_no, kind, note, created_by)
  values (v_business, p_product_id, p_variant_id, p_from, -p_quantity, v_serial, v_kind,
          coalesce(p_note, ''), auth.uid());

  if p_to in ('inspection', 'damaged', 'scrap') then
    insert into public.stock_hold_entries
      (business_id, product_id, variant_id, condition, quantity, serial_no, kind, note, created_by)
    values (v_business, p_product_id, p_variant_id, p_to, p_quantity, v_serial, 'reclassify',
            coalesce(p_note, ''), auth.uid());
  elsif p_to = 'sellable' then
    -- Not a second receipt: the goods were received with the return; this
    -- only makes them available for sale.
    insert into public.stock_movements
      (business_id, product_id, variant_id, movement_type, quantity,
       reference_type, note, created_by)
    values (v_business, p_product_id, p_variant_id, 'adjustment', p_quantity,
            'return_release', coalesce(nullif(p_note, ''), 'Released after inspection'), auth.uid());
  end if;

  if v_serial <> '' then
    update public.product_serials
       set status = case p_to when 'sellable' then 'in_stock'
                              when 'inspection' then 'returned'
                              else 'damaged' end,
           invoice_id = case when p_to = 'sellable' then null else invoice_id end
     where business_id = v_business and serial_no = v_serial;
  end if;

  perform public.log_audit('stock.hold_moved', 'product', p_product_id::text,
    jsonb_build_object('from', p_from, 'to', p_to, 'quantity', p_quantity, 'serial_no', v_serial));
  return v_balance - p_quantity;
end $$;

-- ============================================================
-- B. Return window
-- ============================================================
alter table public.businesses add column if not exists return_window_days integer not null default 30;
alter table public.businesses drop constraint if exists businesses_return_window_check;
alter table public.businesses add constraint businesses_return_window_check
  check (return_window_days between 0 and 3650);          -- 0 = no limit
alter table public.sale_returns add column if not exists window_override_reason text not null default '';

-- ============================================================
-- C. Exchanges
-- ============================================================
create table if not exists public.exchanges (
  id                  uuid primary key default gen_random_uuid(),
  business_id         uuid not null references public.businesses(id) on delete cascade,
  request_id          uuid not null,
  original_invoice_id uuid references public.invoices(id) on delete set null,
  sale_return_id      uuid references public.sale_returns(id) on delete set null,
  new_invoice_id      uuid references public.invoices(id) on delete set null,
  result              jsonb not null default '{}'::jsonb,
  created_by          uuid references public.profiles(id),
  created_at          timestamptz not null default now(),
  unique (business_id, request_id)
);
alter table public.exchanges enable row level security;
drop policy if exists "tenant read" on public.exchanges;
drop policy if exists "admin all" on public.exchanges;
create policy "tenant read" on public.exchanges for select
  using (business_id = (select public.current_business_id()));
create policy "admin all" on public.exchanges for all
  using (public.is_admin()) with check (public.is_admin());

drop trigger if exists trg_00_tenant_refs on public.exchanges;
create trigger trg_00_tenant_refs before insert or update on public.exchanges
  for each row execute function public.enforce_tenant_refs(
    'original_invoice_id=invoices', 'sale_return_id=sale_returns', 'new_invoice_id=invoices');

-- Exchange credit used on the replacement bill is a payment row linked to
-- the return, not a new cash receipt.
alter table public.invoice_payments add column if not exists sale_return_id uuid
  references public.sale_returns(id) on delete set null;

-- ============================================================
-- Sale returns (replaces 0041's version): per-line condition, return
-- window, and exchange mode (payload.exchange = true keeps the remaining
-- credit for create_exchange instead of refunding it or making an advance).
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
         serial_no, quantity, unit_price, tax_amount, line_total, condition)
      values
        (v_business, v_return_id, (v_item ->> 'product_id')::uuid, (v_item ->> 'variant_id')::uuid,
         v_item ->> 'product_name', coalesce(v_item ->> 'serial_no', ''), v_qty,
         round(v_unit_price * v_factor, 2), round(v_qty * v_unit_tax * v_factor, 2), v_value,
         v_condition);
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

-- One exchange = a return on the original bill + a replacement bill, in
-- one transaction (D29, PD30).
--   payload.request_id : client id; a retry returns the first result
--   payload.return     : create_sale_return payload (original invoice_id,
--                        items with condition)
--   payload.sale       : create_invoice payload for the replacement;
--                        paid_amount / payments = money collected now
--   payload.excess     : 'advance' (default) or 'refund' — credit left
--                        after paying the replacement. Walk-in customers
--                        are always refunded (PD28).
--   payload.refund_mode: how an excess refund is paid
create or replace function public.create_exchange(payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business    uuid := public.current_business_id();
  v_request     uuid := (payload ->> 'request_id')::uuid;
  v_prior       jsonb;
  v_orig        record;
  v_customer    uuid;
  v_ret         jsonb;
  v_return_id   uuid;
  v_credit      numeric(14,2);
  v_sale        jsonb := payload -> 'sale';
  v_new         jsonb;
  v_new_id      uuid;
  v_new_due     numeric(14,2);
  v_use         numeric(14,2) := 0;
  v_left        numeric(14,2);
  v_refund      numeric(14,2) := 0;
  v_advance     numeric(14,2) := 0;
  v_excess      text := coalesce(payload ->> 'excess', 'advance');
  v_refund_mode public.payment_mode := coalesce((payload ->> 'refund_mode')::public.payment_mode, 'cash');
  v_result      jsonb;
begin
  if v_business is null then raise exception 'No business for current user'; end if;
  if v_request is null then raise exception 'Missing exchange request id'; end if;

  -- Idempotent: a retried request gets the first result back.
  select result into v_prior from public.exchanges
    where business_id = v_business and request_id = v_request;
  if v_prior is not null then
    return v_prior || jsonb_build_object('already_done', true);
  end if;

  perform public.assert_can('can_manage_returns');
  perform public.assert_can('can_create_invoice');

  select * into v_orig from public.invoices
    where id = (payload -> 'return' ->> 'invoice_id')::uuid and business_id = v_business;
  if v_orig.id is null then raise exception 'An exchange starts from the original bill'; end if;
  v_customer := v_orig.customer_id;

  if v_sale is null or jsonb_array_length(coalesce(v_sale -> 'items', '[]'::jsonb)) = 0 then
    raise exception 'Add the replacement items';
  end if;
  if coalesce(v_sale ->> 'invoice_type', 'gst') = 'estimate' then
    raise exception 'The replacement must be a bill, not an estimate';
  end if;
  if v_refund_mode = 'credit' then v_refund_mode := 'cash'; end if;

  -- 1. The return (credit kept for the replacement).
  v_ret := public.create_sale_return(
    (payload -> 'return') || jsonb_build_object('exchange', true, 'refund_amount', 0));
  v_return_id := (v_ret ->> 'id')::uuid;
  v_credit := coalesce((v_ret ->> 'exchange_credit')::numeric, 0);

  -- 2. The replacement bill, for the same customer as the original.
  v_sale := (v_sale - 'local_id' - 'offline_created')
            || jsonb_build_object('customer_id', v_customer);
  if v_customer is not null then
    v_sale := v_sale || jsonb_build_object('customer_name',
      (select name from public.customers where id = v_customer));
  end if;
  v_new := public.create_invoice(v_sale);
  v_new_id := (v_new ->> 'id')::uuid;

  -- 3. Return credit pays the replacement.
  select due_amount into v_new_due from public.invoices where id = v_new_id for update;
  v_use := least(v_credit, greatest(v_new_due, 0));
  if v_use > 0 then
    update public.invoices set
      paid_amount = paid_amount + v_use,
      payment_status = public.doc_payment_status(total, paid_amount + v_use, credit_amount)
      where id = v_new_id;
    insert into public.invoice_payments
      (business_id, invoice_id, amount, payment_mode, note, sale_return_id)
    values (v_business, v_new_id, v_use, 'other', 'Exchange credit from ' || (v_ret ->> 'return_no'),
            v_return_id);
    if v_customer is not null then
      update public.customers set due_amount = due_amount - v_use
        where id = v_customer and business_id = v_business;
    end if;
  end if;

  if v_customer is null and v_new_due - v_use > 0.005 then
    raise exception 'Collect the full difference (%) for a walk-in exchange', v_new_due - v_use;
  end if;

  -- 4. Credit left over: refund now, or keep as the customer's advance.
  v_left := v_credit - v_use;
  if v_left > 0.005 then
    if v_customer is not null and v_excess = 'advance' then
      perform public.post_customer_advance(v_business, v_customer, v_left, 'return_credit',
        p_sale_return_id => v_return_id, p_invoice_id => v_orig.id,
        p_note => 'Exchange ' || (v_ret ->> 'return_no'));
      v_advance := v_left;
    else
      update public.sale_returns set refund_amount = v_left, refund_mode = v_refund_mode
        where id = v_return_id;
      v_refund := v_left;
    end if;
  end if;

  v_result := jsonb_build_object(
    'return_id', v_return_id, 'return_no', v_ret ->> 'return_no',
    'invoice_id', v_new_id, 'invoice_no', v_new ->> 'invoice_no',
    'return_value', (v_ret ->> 'total')::numeric,
    'applied_to_original', (v_ret ->> 'applied_to_bill')::numeric,
    'credit', v_credit, 'credit_used', v_use,
    'replacement_total', (v_new ->> 'total')::numeric,
    'refund', v_refund, 'advance', v_advance);

  insert into public.exchanges
    (business_id, request_id, original_invoice_id, sale_return_id, new_invoice_id, result, created_by)
  values (v_business, v_request, v_orig.id, v_return_id, v_new_id, v_result, auth.uid());

  perform public.log_audit('exchange.created', 'invoice', v_orig.id::text, v_result);
  return v_result;
end $$;

-- ============================================================
-- Grants
-- ============================================================
revoke execute on function public.move_held_stock(uuid, uuid, text, text, numeric, text, text) from public, anon;
revoke execute on function public.create_exchange(jsonb) from public, anon;
grant execute on function public.move_held_stock(uuid, uuid, text, text, numeric, text, text) to authenticated;
grant execute on function public.create_exchange(jsonb) to authenticated;
