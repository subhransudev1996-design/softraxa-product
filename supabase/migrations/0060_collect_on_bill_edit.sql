-- ============================================================
-- 0060_collect_on_bill_edit.sql — take the difference when a bill is edited
--
-- Editing a bill to a higher total left the difference as due on the
-- customer's khata even when the customer paid it on the spot; the shop
-- then had to record a separate payment. Walk-in bills (no customer) had
-- no way to record that payment at all.
--
--   * collect_invoice_payment(): records a payment against one bill.
--     With a customer it goes through record_customer_payment, so the
--     khata, allocations and receipts stay exactly as for any payment;
--     a walk-in bill gets the payment on the bill itself.
--     Permissions are the existing table guards (can_record_payments /
--     can_create_invoice on invoice_payments and customer_payments).
--
-- Run AFTER 0059.
-- ============================================================

create or replace function public.collect_invoice_payment(
  p_invoice_id uuid,
  p_amount     numeric,
  p_mode       public.payment_mode default 'cash',
  p_note       text default 'Collected when the bill was edited'
) returns void language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_inv      record;
begin
  if v_business is null then raise exception 'No shop selected'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Amount must be positive'; end if;
  if p_mode = 'credit' then raise exception 'Choose how the money was received (cash, UPI, card…)'; end if;

  select * into v_inv from public.invoices
    where id = p_invoice_id and business_id = v_business
    for update;
  if v_inv.id is null then raise exception 'Bill not found'; end if;
  if v_inv.is_cancelled then raise exception 'This bill is cancelled'; end if;
  if v_inv.invoice_type = 'estimate' then raise exception 'Estimates can''t be paid'; end if;
  if p_amount > v_inv.due_amount + 0.005 then
    raise exception 'Amount is more than the bill''s due (%)', v_inv.due_amount;
  end if;

  if v_inv.customer_id is not null then
    perform public.record_customer_payment(
      v_inv.customer_id, p_amount, p_mode, current_date, coalesce(p_note, ''), p_invoice_id);
    return;
  end if;

  -- Walk-in bill: the payment sits on the bill only.
  insert into public.invoice_payments (business_id, invoice_id, amount, payment_mode, note)
    values (v_business, p_invoice_id, p_amount, p_mode, coalesce(p_note, ''));
  update public.invoices set
    paid_amount    = paid_amount + p_amount,
    payment_status = public.doc_payment_status(total, paid_amount + p_amount, credit_amount)
    where id = p_invoice_id;
  perform public.log_audit('payment.received', 'invoice', p_invoice_id::text,
    jsonb_build_object('amount', p_amount, 'mode', p_mode, 'walk_in', true));
end $$;

revoke execute on function public.collect_invoice_payment(uuid, numeric, public.payment_mode, text) from public, anon;
grant execute on function public.collect_invoice_payment(uuid, numeric, public.payment_mode, text) to authenticated;
