-- ============================================================
-- R1 customer advances and payment allocation (migration 0041).
--
-- HOW TO RUN — on a STAGING copy, after 0041:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
--
-- Shop D (non-GST prices to keep the arithmetic plain). Owner, cashier
-- (default staff permissions), two customers.
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('dddddddd-0000-0000-0000-00000000000d', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'r1-adv-owner@test.invalid'),
  ('dddddddd-0000-0000-0000-00000000005d', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'r1-adv-staff@test.invalid');

insert into public.businesses (id, name, state_code) values
  ('dddddddd-1111-0000-0000-00000000000d', 'R1 Advance Shop', '27');

update public.profiles set business_id = 'dddddddd-1111-0000-0000-00000000000d', role = 'owner'
  where id = 'dddddddd-0000-0000-0000-00000000000d';
update public.profiles set business_id = 'dddddddd-1111-0000-0000-00000000000d', role = 'staff'
  where id = 'dddddddd-0000-0000-0000-00000000005d';

insert into public.subscriptions (business_id, status, expiry_date) values
  ('dddddddd-1111-0000-0000-00000000000d', 'active', current_date + 30);

insert into public.products (id, business_id, name, selling_price, purchase_price, gst_rate) values
  ('dddddddd-2222-0000-0000-00000000000d', 'dddddddd-1111-0000-0000-00000000000d',
   'R1 Drill', 500, 300, 0);
insert into public.stock_movements (business_id, product_id, movement_type, quantity, note) values
  ('dddddddd-1111-0000-0000-00000000000d', 'dddddddd-2222-0000-0000-00000000000d', 'opening', 100, 'r1 test');

insert into public.customers (id, business_id, name, credit_unlimited) values
  ('dddddddd-3333-0000-0000-0000000000c1', 'dddddddd-1111-0000-0000-00000000000d', 'R1 Ravi', true),
  ('dddddddd-3333-0000-0000-0000000000c2', 'dddddddd-1111-0000-0000-00000000000d', 'R1 Other', true);

-- Bill helper: qty × ₹500, paid as given, for a customer. Runs as the
-- caller (the actor set below).
create or replace function pg_temp.bill(p_customer uuid, p_qty int, p_paid numeric, p_days_ago int default 0)
returns uuid language sql as $$
  select (public.create_invoice(jsonb_build_object(
    'invoice_type', 'non_gst', 'customer_id', p_customer, 'customer_name', 'x',
    'paid_amount', p_paid, 'payment_mode', case when p_paid > 0 then 'cash' else 'credit' end,
    'invoice_date', now() - make_interval(days => p_days_ago),
    'items', jsonb_build_array(jsonb_build_object(
      'product_id', 'dddddddd-2222-0000-0000-00000000000d', 'product_name', 'R1 Drill',
      'quantity', p_qty, 'unit_price', 500, 'gst_rate', 0, 'tax_amount', 0,
      'line_total', p_qty * 500)))) ->> 'id')::uuid;
$$;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"dddddddd-0000-0000-0000-00000000000d","role":"authenticated"}', true);

do $$
declare
  c1   constant uuid := 'dddddddd-3333-0000-0000-0000000000c1';
  c2   constant uuid := 'dddddddd-3333-0000-0000-0000000000c2';
  b1   uuid; b2 uuid; b3 uuid; b4 uuid; b5 uuid; b6 uuid; b7 uuid; bx uuid;
  pay1 uuid; pay2 uuid;
  v    jsonb;
  cust record;
begin
  -- Spec example (D26): oldest bill owes 1,000, the next 500.
  b1 := pg_temp.bill(c1, 2, 0, 2);
  b2 := pg_temp.bill(c1, 1, 0, 1);

  -- 1. Preview of 1,200: 1,000 to the oldest, 200 to the next, no advance.
  v := public.preview_customer_payment(c1, 1200);
  if (v ->> 'advance')::numeric <> 0
     or (v -> 'allocations' -> 0 ->> 'invoice_id')::uuid <> b1
     or (v -> 'allocations' -> 0 ->> 'apply')::numeric <> 1000
     or (v -> 'allocations' -> 1 ->> 'apply')::numeric <> 200 then
    raise exception 'FAIL 1: preview %', v;
  end if;
  raise notice 'PASS 1 (preview: oldest first)';

  -- 2. A payment of 1,700 clears both and leaves 200 as advance.
  pay1 := public.record_customer_payment(c1, 1700, 'cash');
  select due_amount, advance_amount into cust from public.customers where id = c1;
  if cust.due_amount <> 0 or cust.advance_amount <> 200
     or (select due_amount from public.invoices where id = b1) <> 0
     or (select due_amount from public.invoices where id = b2) <> 0
     or (select unapplied_amount from public.customer_payments where id = pay1) <> 200
     or (select sum(amount) from public.customer_payment_allocations where payment_id = pay1) <> 1500 then
    raise exception 'FAIL 2: due % advance %', cust.due_amount, cust.advance_amount;
  end if;
  raise notice 'PASS 2 (excess becomes advance, not a negative due)';

  -- 3. Advance used on a new 500 credit bill: 200 applied, 300 still due.
  b3 := pg_temp.bill(c1, 1, 0);
  v := public.apply_customer_advance(b3);
  select due_amount, advance_amount into cust from public.customers where id = c1;
  if (v ->> 'applied')::numeric <> 200 or cust.advance_amount <> 0 or cust.due_amount <> 300
     or (select due_amount from public.invoices where id = b3) <> 300
     or not exists (select 1 from public.invoice_payments where invoice_id = b3 and is_advance) then
    raise exception 'FAIL 3: applied % advance % due %', v ->> 'applied', cust.advance_amount, cust.due_amount;
  end if;
  raise notice 'PASS 3 (advance applied on request, not a new receipt)';

  -- 3b. That payment's advance is now used, so it can't be reversed.
  begin
    perform public.reverse_customer_payment(pay1, 'bounced cheque');
    raise exception 'FAIL 3b: reversed a payment whose advance was used';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 3b (reversal blocked while its advance is used): %', sqlerrm;
  end;
  if (select due_amount from public.invoices where id = b1) <> 0 then
    raise exception 'FAIL 3c: failed reversal left changes behind';
  end if;

  -- 4. Manual allocation: pay the newer bill, not the oldest.
  b4 := pg_temp.bill(c1, 1, 0);
  pay2 := public.record_customer_payment(c1, 100, 'upi', p_invoice_ids => array[b4]);
  if (select due_amount from public.invoices where id = b4) <> 400
     or (select due_amount from public.invoices where id = b3) <> 300 then
    raise exception 'FAIL 4: manual allocation went to the wrong bill';
  end if;
  raise notice 'PASS 4 (manual bill selection)';

  -- 5. Another customer's bill can't be chosen.
  bx := pg_temp.bill(c2, 1, 0);
  begin
    perform public.record_customer_payment(c1, 100, 'cash', p_invoice_ids => array[bx]);
    raise exception 'FAIL 5: paid another customer''s bill';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 5 (only this customer''s bills): %', sqlerrm;
  end;

  -- 6. A return on a fully paid bill, not refunded, becomes advance.
  b5 := pg_temp.bill(c1, 1, 500);
  v := public.create_sale_return(jsonb_build_object(
    'invoice_id', b5, 'refund_amount', 0,
    'items', jsonb_build_array(jsonb_build_object(
      'product_id', 'dddddddd-2222-0000-0000-00000000000d', 'product_name', 'R1 Drill', 'quantity', 1))));
  select due_amount, advance_amount into cust from public.customers where id = c1;
  if (v ->> 'advance')::numeric <> 500 or cust.advance_amount <> 500 or cust.due_amount <> 700 then
    raise exception 'FAIL 6: return advance % customer advance % due %', v ->> 'advance', cust.advance_amount, cust.due_amount;
  end if;
  raise notice 'PASS 6 (return credit → advance, due unchanged)';

  -- 7. Cancelling a paid bill keeps the money as advance.
  b6 := pg_temp.bill(c1, 1, 500);
  perform public.cancel_invoice(b6);
  if (select advance_amount from public.customers where id = c1) <> 1000 then
    raise exception 'FAIL 7: cancelled bill''s payment was lost';
  end if;
  raise notice 'PASS 7 (cancelled paid bill → advance)';

  -- 8. Editing a paid bill below what was paid moves the excess to advance.
  b7 := pg_temp.bill(c1, 2, 1000);
  perform public.update_invoice(b7, jsonb_build_object(
    'items', jsonb_build_array(jsonb_build_object(
      'product_id', 'dddddddd-2222-0000-0000-00000000000d', 'product_name', 'R1 Drill',
      'quantity', 1, 'unit_price', 500, 'gst_rate', 0, 'tax_amount', 0, 'line_total', 500))));
  select due_amount, advance_amount into cust from public.customers where id = c1;
  if (select due_amount from public.invoices where id = b7) <> 0
     or (select paid_amount from public.invoices where id = b7) <> 500
     or cust.advance_amount <> 1500 or cust.due_amount <> 700 then
    raise exception 'FAIL 8: bill due % paid % advance % customer due %',
      (select due_amount from public.invoices where id = b7),
      (select paid_amount from public.invoices where id = b7), cust.advance_amount, cust.due_amount;
  end if;
  raise notice 'PASS 8 (overpaid bill → advance)';

  -- 9. Owner refunds part of the advance.
  perform public.refund_customer_advance(c1, 500, 'cash', 'r1 test');
  if (select advance_amount from public.customers where id = c1) <> 1000 then
    raise exception 'FAIL 9: refund';
  end if;
  raise notice 'PASS 9 (owner refund)';

  -- 10. The 100 payment reverses cleanly: its bill is due again and the
  --     receipt stays in history, marked reversed.
  perform public.reverse_customer_payment(pay2, 'entered twice');
  if (select due_amount from public.invoices where id = b4) <> 500
     or (select due_amount from public.customers where id = c1) <> 800
     or (select reversed_at from public.customer_payments where id = pay2) is null
     or not (select bool_and(reversed) from public.invoice_payments where customer_payment_id = pay2) then
    raise exception 'FAIL 10c: reversal did not restore the bill';
  end if;
  raise notice 'PASS 10 (reversal restores balances, keeps history)';

  -- 11. Balances reconcile: due = open bill dues; advance = its ledger.
  if (select due_amount from public.customers where id = c1) <>
     (select coalesce(sum(due_amount), 0) from public.invoices
      where customer_id = c1 and not is_cancelled and invoice_type <> 'estimate')
     or (select advance_amount from public.customers where id = c1) <>
     (select coalesce(sum(amount), 0) from public.customer_advance_entries where customer_id = c1) then
    raise exception 'FAIL 11: balances don''t reconcile';
  end if;
  raise notice 'PASS 11 (due and advance reconcile with bills and ledger)';

  -- 12. Balances can't be edited directly.
  begin
    update public.customers set advance_amount = 99999 where id = c1;
    raise exception 'FAIL 12: advance edited directly';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 12 (advance not directly editable): %', sqlerrm;
  end;
end $$;

-- Cashier: can receive payments, can't refund or reverse.
select set_config('request.jwt.claims',
  '{"sub":"dddddddd-0000-0000-0000-00000000005d","role":"authenticated"}', true);

do $$ begin
  perform public.record_customer_payment('dddddddd-3333-0000-0000-0000000000c1', 50, 'cash');
  raise notice 'PASS 13a (cashier receives a payment)';
  begin
    perform public.refund_customer_advance('dddddddd-3333-0000-0000-0000000000c1', 10, 'cash', '');
    raise exception 'FAIL 13b: cashier refunded an advance';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 13b (refund is owner-only): %', sqlerrm;
  end;
  begin
    perform public.reverse_customer_payment(
      (select id from public.customer_payments
       where customer_id = 'dddddddd-3333-0000-0000-0000000000c1' and reversed_at is null
       order by created_at desc limit 1), 'mistake');
    raise exception 'FAIL 13c: cashier reversed a payment';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 13c (reversal is owner-only): %', sqlerrm;
  end;
end $$;

reset role;
do $$ begin raise notice 'ALL R1 ADVANCE CHECKS PASSED — rolling back test data'; end $$;
rollback;
