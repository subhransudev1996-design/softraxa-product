-- ============================================================
-- 0092_reversals.sql — undo supplier payments and returns (app + AI).
--
-- 1. Supplier payments now remember which purchases they paid
--    (supplier_payment_allocations, like customer payments since 0041),
--    so the owner can REVERSE one entered by mistake: the purchases are
--    unpaid again, the supplier is owed again, and the cash book shows
--    the money back on the day of the reversal (closed days don't change).
--    A payment recorded with a purchase ("Paid with purchase") is changed
--    by editing the purchase instead; older FIFO payments (before this
--    update) can't be reversed — the app never recorded where they went.
-- 2. The owner can UNDO a sale return or a purchase return entered by
--    mistake, in the same month (its GST credit / debit note isn't filed
--    yet) and while its cash day is open: stock, held goods, IMEIs, the
--    bill's credit, the customer's due / advance, the purchase's credit
--    and the supplier's due go back exactly; the return is removed. Not
--    when the returned goods were sold or moved on since, the advance it
--    gave was used, or it was part of an exchange.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Supplier payments: allocations and reversal
-- ------------------------------------------------------------
create table if not exists public.supplier_payment_allocations (
  id          uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  payment_id  uuid not null references public.supplier_payments(id) on delete cascade,
  purchase_id uuid not null references public.purchases(id) on delete cascade,
  amount      numeric(14,2) not null check (amount > 0)
);
create index if not exists idx_supplier_payment_allocations_payment
  on public.supplier_payment_allocations (payment_id);
alter table public.supplier_payment_allocations enable row level security;
revoke all on public.supplier_payment_allocations from public, anon, authenticated;

alter table public.supplier_payments add column if not exists tracked boolean not null default false;
alter table public.supplier_payments add column if not exists reversed_at timestamptz;
alter table public.supplier_payments add column if not exists reversal_reason text not null default '';
alter table public.supplier_payments add column if not exists reversed_by uuid references public.profiles(id);

-- As 0038, plus where the money went.
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
    (business_id, supplier_id, purchase_id, amount, payment_mode, payment_date, note, created_by, tracked)
  values (v_business, p_supplier_id, p_purchase_id, p_amount, p_mode, p_date, p_note, auth.uid(), true)
  returning id into v_id;

  if p_purchase_id is not null then
    update public.purchases set
      paid_amount = paid_amount + p_amount,
      payment_status = public.doc_payment_status(total, paid_amount + p_amount, credit_amount)
      where id = p_purchase_id;
    insert into public.supplier_payment_allocations (business_id, payment_id, purchase_id, amount)
      values (v_business, v_id, p_purchase_id, p_amount);
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
      insert into public.supplier_payment_allocations (business_id, payment_id, purchase_id, amount)
        values (v_business, v_id, v_pur.id, v_apply);
      v_remaining := v_remaining - v_apply;
    end loop;
  end if;

  perform public.log_audit('payment.made', 'supplier', p_supplier_id::text,
    jsonb_build_object('amount', p_amount, 'purchase_id', p_purchase_id));
  return v_id;
end $$;

-- Payments made with a purchase that were reversed don't count as paid.
create or replace function public.purchase_paid_split(p_purchase public.purchases)
returns table (initial numeric, later numeric)
language sql stable security definer set search_path = public as $$
  select i.amt, greatest(p_purchase.paid_amount - i.amt, 0)
  from (select case
                 when p_purchase.supplier_id is null then p_purchase.paid_amount
                 else coalesce((select sum(amount) from public.supplier_payments
                                 where purchase_id = p_purchase.id
                                   and note = 'Paid with purchase' and reversed_at is null), 0)
               end as amt) i;
$$;

create or replace function public.reverse_supplier_payment(p_payment_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_pay      public.supplier_payments;
  a          record;
begin
  perform public.assert_can('owner', false);
  if length(trim(coalesce(p_reason, ''))) < 3 then
    raise exception 'Give a reason for reversing this payment';
  end if;
  select * into v_pay from public.supplier_payments
    where id = p_payment_id and business_id = v_business for update;
  if v_pay.id is null then raise exception 'Payment not found'; end if;
  if v_pay.reversed_at is not null then raise exception 'This payment is already reversed'; end if;
  if v_pay.note = 'Paid with purchase' then
    raise exception 'This was paid when the purchase was entered — change what was paid by editing that purchase';
  end if;
  if not v_pay.tracked and v_pay.purchase_id is null then
    raise exception 'Payments recorded before this update can''t be reversed in the app';
  end if;

  perform 1 from public.suppliers where id = v_pay.supplier_id and business_id = v_business for update;

  if v_pay.tracked then
    for a in select * from public.supplier_payment_allocations where payment_id = p_payment_id loop
      update public.purchases set
        paid_amount = paid_amount - a.amount,
        payment_status = public.doc_payment_status(total, paid_amount - a.amount, credit_amount)
        where id = a.purchase_id;
    end loop;
  else
    update public.purchases set
      paid_amount = paid_amount - v_pay.amount,
      payment_status = public.doc_payment_status(total, paid_amount - v_pay.amount, credit_amount)
      where id = v_pay.purchase_id and business_id = v_business;
  end if;

  -- The whole payment had lowered what the shop owes.
  update public.suppliers set due_amount = due_amount + v_pay.amount
    where id = v_pay.supplier_id and business_id = v_business;

  update public.supplier_payments
     set reversed_at = now(), reversal_reason = trim(p_reason), reversed_by = auth.uid()
   where id = p_payment_id;

  perform public.log_audit('payment.reversed', 'supplier', v_pay.supplier_id::text,
    jsonb_build_object('payment_id', p_payment_id, 'amount', v_pay.amount, 'reason', trim(p_reason)));
end $$;

create or replace function public.cash_movements(p_business uuid, p_from date, p_to date)
returns table (ts timestamptz, source text, ref_id uuid, label text, mode text,
               direction integer, amount numeric)
language sql stable security definer set search_path = public as $$
  select * from (
    -- money taken on bills (split payments: each mode separately)
    select ip.created_at, 'bill_payment', ip.invoice_id, 'Bill ' || i.invoice_no,
           ip.payment_mode::text, 1, ip.amount
    from public.invoice_payments ip join public.invoices i on i.id = ip.invoice_id
    where ip.business_id = p_business and not ip.is_advance and not ip.reversed
      and ip.customer_payment_id is null and ip.sale_return_id is null
    union all
    -- customer payments and advances received
    select cp.created_at, 'customer_payment', cp.id, 'Payment — ' || c.name,
           cp.payment_mode::text, 1, cp.amount
    from public.customer_payments cp join public.customers c on c.id = cp.customer_id
    where cp.business_id = p_business
    union all
    -- a reversed payment leaves on the day it was reversed
    select cp.reversed_at, 'payment_reversal', cp.id, 'Payment reversed — ' || c.name,
           cp.payment_mode::text, -1, cp.amount
    from public.customer_payments cp join public.customers c on c.id = cp.customer_id
    where cp.business_id = p_business and cp.reversed_at is not null
    union all
    select jc.created_at, 'job_advance', jc.id, 'Advance — job ' || jc.job_no,
           jc.advance_mode::text, 1, jc.advance_amount
    from public.job_cards jc
    where jc.business_id = p_business and jc.advance_amount > 0
    union all
    select sr.created_at, 'return_refund', sr.id, 'Refund — return ' || sr.return_no,
           sr.refund_mode::text, -1, sr.refund_amount
    from public.sale_returns sr
    where sr.business_id = p_business and sr.refund_amount > 0 and sr.refund_mode <> 'credit'
    union all
    select e.created_at, 'advance_refund', e.id, 'Advance refunded — ' || c.name,
           coalesce(e.payment_mode::text, 'cash'), -1, -e.amount
    from public.customer_advance_entries e join public.customers c on c.id = e.customer_id
    where e.business_id = p_business and e.kind = 'refund'
    union all
    select sp.created_at, 'supplier_payment', sp.id, 'Paid — ' || s.name,
           sp.payment_mode::text, -1, sp.amount
    from public.supplier_payments sp join public.suppliers s on s.id = sp.supplier_id
    where sp.business_id = p_business
    union all
    -- a reversed supplier payment comes back on the day it was reversed (0092)
    select sp.reversed_at, 'supplier_payment_reversal', sp.id, 'Payment reversed — ' || s.name,
           sp.payment_mode::text, 1, sp.amount
    from public.supplier_payments sp join public.suppliers s on s.id = sp.supplier_id
    where sp.business_id = p_business and sp.reversed_at is not null
    union all
    select pr.created_at, 'supplier_refund', pr.id, 'Refund from supplier — ' || pr.return_no,
           'cash', 1, pr.received_amount
    from public.purchase_returns pr
    where pr.business_id = p_business and pr.received_amount > 0
    union all
    select x.created_at, 'expense', x.id,
           'Expense — ' || coalesce(ec.name, 'other') || case when x.note <> '' then ' (' || x.note || ')' else '' end,
           x.payment_mode::text, -1, x.amount
    from public.expenses x left join public.expense_categories ec on ec.id = x.category_id
    where x.business_id = p_business
    union all
    select ce.created_at, 'manual', ce.id,
           case ce.kind when 'owner_in' then 'Cash added by owner'
                        when 'owner_out' then 'Cash taken by owner'
                        when 'bank_deposit' then 'Deposited in bank'
                        when 'bank_withdrawal' then 'Withdrawn from bank'
                        when 'other_in' then 'Other cash in'
                        else 'Other cash out' end
             || case when ce.note <> '' then ' — ' || ce.note else '' end,
           'cash', case when ce.kind in ('owner_in', 'bank_withdrawal', 'other_in') then 1 else -1 end,
           ce.amount
    from public.cash_entries ce
    where ce.business_id = p_business
  ) m (ts, source, ref_id, label, mode, direction, amount)
  where public.ist_date(m.ts) between p_from and p_to;
$$;

-- ------------------------------------------------------------
-- 2. Undoing returns
-- ------------------------------------------------------------
-- Is the cash day of this moment closed (and not reopened)?
create or replace function public.cash_day_closed(p_business uuid, p_ts timestamptz)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select c.status <> 'reopened' from public.cash_closings c
                   where c.business_id = p_business and c.business_date = public.ist_date(p_ts)
                   order by c.version desc limit 1), false);
$$;

create or replace function public.undo_sale_return(p_return_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_ret      public.sale_returns;
  v_log      jsonb;
  v_apply    numeric := 0;
  v_advance  numeric := 0;
  v_it       record;
  v_delta    jsonb := '[]'::jsonb;
  v_held     numeric;
begin
  perform public.assert_can('owner');
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'Give a reason for undoing this return'; end if;
  select * into v_ret from public.sale_returns where id = p_return_id and business_id = v_business for update;
  if v_ret.id is null then raise exception 'Return not found'; end if;
  if to_char(public.ist_date(v_ret.return_date), 'YYYY-MM') <> to_char(public.ist_date(now()), 'YYYY-MM') then
    raise exception 'Return % is from an earlier month — its GST credit note may be filed, so it can''t be undone. Make a new sale instead.', v_ret.return_no;
  end if;
  if v_ret.refund_amount > 0 and public.cash_day_closed(v_business, v_ret.created_at) then
    raise exception 'The cash day of return % is closed — reopen it first', v_ret.return_no;
  end if;
  if exists (select 1 from public.invoice_payments where sale_return_id = v_ret.id) then
    raise exception 'Return % was part of an exchange — it can''t be undone here', v_ret.return_no;
  end if;
  select details into v_log from public.audit_logs
    where business_id = v_business and action = 'sale_return.created' and entity_id = v_ret.id::text
    order by created_at desc limit 1;
  if v_log is null then raise exception 'Return % is too old to undo safely', v_ret.return_no; end if;
  if coalesce((v_log ->> 'exchange_credit')::numeric, 0) > 0 then
    raise exception 'Return % was part of an exchange — it can''t be undone here', v_ret.return_no;
  end if;
  v_apply := coalesce((v_log ->> 'applied_to_bill')::numeric, 0);
  v_advance := coalesce((v_log ->> 'advance')::numeric, 0);

  -- Goods: sellable ones come out of stock again; held ones out of their hold.
  for v_it in select * from public.sale_return_items where sale_return_id = v_ret.id loop
    if v_it.condition = 'sellable' and v_it.product_id is not null then
      v_delta := v_delta || jsonb_build_object('pid', v_it.product_id, 'vid', v_it.variant_id,
                                               'delta', -v_it.quantity, 'name', v_it.product_name);
    elsif v_it.product_id is not null then
      select coalesce(sum(quantity), 0) into v_held from public.stock_hold_entries
        where business_id = v_business and product_id = v_it.product_id
          and variant_id is not distinct from v_it.variant_id and condition = v_it.condition;
      if v_held < v_it.quantity then
        raise exception '"%" from this return was already released or moved from %', v_it.product_name, v_it.condition;
      end if;
    end if;
    if v_it.serial_no <> '' and exists (
         select 1 from public.product_serials where business_id = v_business and serial_no = v_it.serial_no
           and status = 'sold' and invoice_id is distinct from v_ret.invoice_id) then
      raise exception 'IMEI / serial % from this return was sold again', v_it.serial_no;
    end if;
  end loop;
  perform public.assert_stock_covers(v_business, v_delta);

  for v_it in select * from public.sale_return_items where sale_return_id = v_ret.id loop
    if v_it.condition = 'sellable' and v_it.product_id is not null then
      insert into public.stock_movements
        (business_id, product_id, variant_id, movement_type, quantity, reference_type, reference_id, note, created_by)
      values (v_business, v_it.product_id, v_it.variant_id, 'adjustment', -v_it.quantity,
              'sale_return_undo', v_ret.id, 'Return ' || v_ret.return_no || ' undone', auth.uid());
    end if;
    if v_it.serial_no <> '' then
      update public.product_serials set status = 'sold', invoice_id = v_ret.invoice_id
        where business_id = v_business and serial_no = v_it.serial_no;
    end if;
  end loop;
  delete from public.stock_hold_entries where sale_return_id = v_ret.id and kind = 'return';

  -- Money: the bill's credit, the customer's due and advance.
  if v_apply > 0 and v_ret.invoice_id is not null then
    update public.invoices set
      credit_amount = credit_amount - v_apply,
      payment_status = public.doc_payment_status(total, paid_amount, credit_amount - v_apply)
      where id = v_ret.invoice_id;
    if v_ret.customer_id is not null then
      update public.customers set due_amount = due_amount + v_apply
        where id = v_ret.customer_id and business_id = v_business;
    end if;
  end if;
  if v_advance > 0 and v_ret.customer_id is not null then
    begin
      perform public.post_customer_advance(v_business, v_ret.customer_id, -v_advance, 'reversal',
        p_note => 'Return ' || v_ret.return_no || ' undone: ' || trim(p_reason));
    exception when others then
      raise exception 'The advance this return gave the customer was already used or refunded — it can''t be undone';
    end;
  end if;

  delete from public.sale_returns where id = v_ret.id;
  perform public.log_audit('sale_return.undone', 'sale_return', v_ret.id::text,
    jsonb_build_object('return_no', v_ret.return_no, 'total', v_ret.total, 'refund', v_ret.refund_amount,
                       'reason', trim(p_reason)));
  return jsonb_build_object('undone', v_ret.return_no, 'total', v_ret.total,
                            'refund_to_collect_back', v_ret.refund_amount);
end $$;

create or replace function public.undo_purchase_return(p_return_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_ret      public.purchase_returns;
  v_log      jsonb;
  v_apply    numeric := 0;
  v_it       record;
begin
  perform public.assert_can('owner');
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'Give a reason for undoing this return'; end if;
  select * into v_ret from public.purchase_returns where id = p_return_id and business_id = v_business for update;
  if v_ret.id is null then raise exception 'Return not found'; end if;
  if to_char(v_ret.return_date, 'YYYY-MM') <> to_char(public.ist_date(now()), 'YYYY-MM') then
    raise exception 'Return % is from an earlier month — its GST debit note may be filed, so it can''t be undone.', v_ret.return_no;
  end if;
  if v_ret.received_amount > 0 and public.cash_day_closed(v_business, v_ret.created_at) then
    raise exception 'The cash day of return % is closed — reopen it first', v_ret.return_no;
  end if;
  select details into v_log from public.audit_logs
    where business_id = v_business and action = 'purchase_return.created' and entity_id = v_ret.id::text
    order by created_at desc limit 1;
  if v_log is null then raise exception 'Return % is too old to undo safely', v_ret.return_no; end if;
  v_apply := coalesce((v_log ->> 'applied_to_bill')::numeric, 0);

  -- The goods come back into stock.
  for v_it in select * from public.purchase_return_items where purchase_return_id = v_ret.id loop
    if v_it.product_id is not null then
      insert into public.stock_movements
        (business_id, product_id, variant_id, movement_type, quantity, reference_type, reference_id, note, created_by)
      values (v_business, v_it.product_id, v_it.variant_id, 'adjustment', v_it.quantity,
              'purchase_return_undo', v_ret.id, 'Return ' || v_ret.return_no || ' undone', auth.uid());
    end if;
  end loop;

  if v_apply > 0 and v_ret.purchase_id is not null then
    update public.purchases set
      credit_amount = credit_amount - v_apply,
      payment_status = public.doc_payment_status(total, paid_amount, credit_amount - v_apply)
      where id = v_ret.purchase_id;
  end if;
  if v_ret.supplier_id is not null and (v_ret.total - v_ret.received_amount) > 0 then
    update public.suppliers set due_amount = due_amount + (v_ret.total - v_ret.received_amount)
      where id = v_ret.supplier_id and business_id = v_business;
  end if;

  delete from public.purchase_returns where id = v_ret.id;
  perform public.log_audit('purchase_return.undone', 'purchase_return', v_ret.id::text,
    jsonb_build_object('return_no', v_ret.return_no, 'total', v_ret.total, 'received', v_ret.received_amount,
                       'reason', trim(p_reason)));
  return jsonb_build_object('undone', v_ret.return_no, 'total', v_ret.total,
                            'refund_to_give_back', v_ret.received_amount);
end $$;

revoke execute on function public.cash_day_closed(uuid, timestamptz) from public, anon, authenticated;
revoke execute on function public.reverse_supplier_payment(uuid, text) from public, anon;
revoke execute on function public.undo_sale_return(uuid, text) from public, anon;
revoke execute on function public.undo_purchase_return(uuid, text) from public, anon;
grant execute on function public.reverse_supplier_payment(uuid, text) to authenticated;
grant execute on function public.undo_sale_return(uuid, text) to authenticated;
grant execute on function public.undo_purchase_return(uuid, text) to authenticated;
