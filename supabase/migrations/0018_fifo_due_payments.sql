-- Fix: paying down a customer's/supplier's overall due from the Customer/
-- Supplier detail screen (which doesn't ask which invoice/purchase to pay
-- against) correctly reduced customers.due_amount / suppliers.due_amount,
-- but never touched the underlying invoices/purchases rows — so a specific
-- invoice kept showing "unpaid" with a "Record payment" button forever,
-- even though the customer's aggregate due was already cleared.
--
-- record_customer_payment / record_supplier_payment already handled this
-- correctly when called WITH an explicit invoice/purchase id (the "Record
-- payment" button on the invoice/purchase detail screen itself). The gap
-- was only the "no specific id" path used by the customer/supplier ledger
-- screens. Fix: when no id is given, settle the oldest outstanding
-- invoices/purchases first (FIFO) until the payment amount is used up.

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
