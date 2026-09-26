-- ============================================================
-- R0 verification: security, tenant isolation and ledger integrity
-- (migrations 0036–0039; PROJECT_ANALYSIS findings 1–4, 8, 9, 13–16, 18, 19)
--
-- HOW TO RUN — on a STAGING copy of the database, never production:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- Everything runs in one transaction that ends in ROLLBACK, so no test
-- data is left behind. Read the output messages:
--   every check prints "PASS …"; the first failure aborts with "FAIL …".
--
-- Actors: owner A (shop A), cashier S (staff of shop A, default
-- permissions), owner B (shop B). Requests are simulated the way
-- PostgREST makes them: role `authenticated` + JWT claims.
-- ============================================================

begin;

-- ---------- fixtures (as the database owner, no JWT) ----------
select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('aaaaaaaa-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'r0-owner-a@test.invalid'),
  ('aaaaaaaa-0000-0000-0000-00000000005a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'r0-staff-a@test.invalid'),
  ('bbbbbbbb-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'r0-owner-b@test.invalid');

insert into public.businesses (id, name, state_code) values
  ('aaaaaaaa-1111-0000-0000-00000000000a', 'R0 Shop A', '27'),
  ('bbbbbbbb-1111-0000-0000-00000000000b', 'R0 Shop B', '27');

update public.profiles set business_id = 'aaaaaaaa-1111-0000-0000-00000000000a', role = 'owner'
  where id = 'aaaaaaaa-0000-0000-0000-00000000000a';
update public.profiles set business_id = 'aaaaaaaa-1111-0000-0000-00000000000a', role = 'staff'
  where id = 'aaaaaaaa-0000-0000-0000-00000000005a';
update public.profiles set business_id = 'bbbbbbbb-1111-0000-0000-00000000000b', role = 'owner'
  where id = 'bbbbbbbb-0000-0000-0000-00000000000b';

insert into public.subscriptions (business_id, status, expiry_date) values
  ('aaaaaaaa-1111-0000-0000-00000000000a', 'active', current_date + 30),
  ('bbbbbbbb-1111-0000-0000-00000000000b', 'active', current_date + 30);

insert into public.products (id, business_id, name, selling_price, purchase_price, gst_rate, track_serial) values
  ('aaaaaaaa-2222-0000-0000-00000000000a', 'aaaaaaaa-1111-0000-0000-00000000000a', 'R0 Phone A', 118, 80, 18, false),
  ('bbbbbbbb-2222-0000-0000-00000000000b', 'bbbbbbbb-1111-0000-0000-00000000000b', 'R0 Phone B', 118, 80, 18, false);
insert into public.stock_movements (business_id, product_id, movement_type, quantity, note) values
  ('aaaaaaaa-1111-0000-0000-00000000000a', 'aaaaaaaa-2222-0000-0000-00000000000a', 'opening', 20, 'r0 test'),
  ('bbbbbbbb-1111-0000-0000-00000000000b', 'bbbbbbbb-2222-0000-0000-00000000000b', 'opening', 20, 'r0 test');

insert into public.customers (id, business_id, name, state_code, credit_unlimited) values
  ('aaaaaaaa-3333-0000-0000-0000000000c1', 'aaaaaaaa-1111-0000-0000-00000000000a', 'R0 Local customer', '27', true),
  ('aaaaaaaa-3333-0000-0000-0000000000c2', 'aaaaaaaa-1111-0000-0000-00000000000a', 'R0 Karnataka customer', '29', true);

-- ============================================================
-- Owner A
-- ============================================================
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-0000-0000-0000-00000000000a","role":"authenticated"}', true);

do $$ begin
  -- 1. Finding 1: no self-promotion to admin, no switching business.
  begin
    update public.profiles set role = 'admin' where id = auth.uid();
    raise exception 'FAIL 1: owner promoted themselves to admin';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 1 (no self-promotion): %', sqlerrm;
  end;
  begin
    update public.profiles set business_id = 'bbbbbbbb-1111-0000-0000-00000000000b' where id = auth.uid();
    raise exception 'FAIL 2: owner moved into another business';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 2 (no business switching): %', sqlerrm;
  end;

  -- 3. Tenant isolation: shop B's rows are invisible.
  if (select count(*) from public.products where business_id = 'bbbbbbbb-1111-0000-0000-00000000000b') <> 0 then
    raise exception 'FAIL 3: owner A can read shop B products';
  end if;
  raise notice 'PASS 3 (cannot read another shop)';

  -- 4. Finding 2: an invoice may not reference another shop's product.
  begin
    perform public.create_invoice(jsonb_build_object(
      'invoice_type', 'gst', 'paid_amount', 118, 'payment_mode', 'cash',
      'items', jsonb_build_array(jsonb_build_object(
        'product_id', 'bbbbbbbb-2222-0000-0000-00000000000b', 'product_name', 'x',
        'quantity', 1, 'unit_price', 100, 'gst_rate', 18, 'tax_amount', 18, 'line_total', 118))));
    raise exception 'FAIL 4: invoice used shop B''s product';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 4 (cross-shop product refused): %', sqlerrm;
  end;

  -- 5. Finding 18: the stock ledger and stock totals can't be written directly.
  begin
    insert into public.stock_movements (business_id, product_id, movement_type, quantity)
    values ('aaaaaaaa-1111-0000-0000-00000000000a', 'aaaaaaaa-2222-0000-0000-00000000000a', 'adjustment', 999);
    raise exception 'FAIL 5a: direct stock movement insert allowed';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 5a (ledger not directly writable): %', sqlerrm;
  end;
  begin
    update public.products set current_stock = 999 where id = 'aaaaaaaa-2222-0000-0000-00000000000a';
    raise exception 'FAIL 5b: direct current_stock change allowed';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 5b (stock total protected): %', sqlerrm;
  end;

  -- 6. Finding 3: plan RPCs are admin-only.
  begin
    perform public.apply_plan_features('aaaaaaaa-1111-0000-0000-00000000000a', null);
    raise exception 'FAIL 6: owner ran apply_plan_features';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 6 (plan RPC admin-only): %', sqlerrm;
  end;

  -- 7. Finding 13: the owner can list their staff.
  if (select count(*) from public.profiles where business_id = 'aaaaaaaa-1111-0000-0000-00000000000a') <> 2 then
    raise exception 'FAIL 7: owner cannot see both profiles of their shop';
  end if;
  raise notice 'PASS 7 (owner lists staff)';
end $$;

-- 8. GST (0036): Karnataka customer from a Maharashtra shop → IGST.
do $$
declare v jsonb;
begin
  v := public.create_invoice(jsonb_build_object(
    'invoice_type', 'gst', 'customer_id', 'aaaaaaaa-3333-0000-0000-0000000000c2',
    'customer_name', 'R0 Karnataka customer', 'paid_amount', 118, 'payment_mode', 'cash',
    'items', jsonb_build_array(jsonb_build_object(
      'product_id', 'aaaaaaaa-2222-0000-0000-00000000000a', 'product_name', 'R0 Phone A',
      'quantity', 1, 'unit_price', 100, 'gst_rate', 18, 'tax_amount', 18, 'line_total', 118))));
  if (select igst_amount from public.invoice_items where invoice_id = (v ->> 'id')::uuid) <> 18 then
    raise exception 'FAIL 8: inter-state invoice line is not IGST';
  end if;
  raise notice 'PASS 8 (inter-state → IGST)';
end $$;

-- 9–11. Findings 8, 9, 19: returns and payments.
do $$
declare
  v_inv uuid;
  v_ret jsonb;
begin
  -- Credit sale of 1 unit (unpaid) to the local customer.
  v_inv := (public.create_invoice(jsonb_build_object(
    'invoice_type', 'gst', 'customer_id', 'aaaaaaaa-3333-0000-0000-0000000000c1',
    'customer_name', 'R0 Local customer', 'paid_amount', 0, 'payment_mode', 'credit',
    'items', jsonb_build_array(jsonb_build_object(
      'product_id', 'aaaaaaaa-2222-0000-0000-00000000000a', 'product_name', 'R0 Phone A',
      'quantity', 1, 'unit_price', 100, 'gst_rate', 18, 'tax_amount', 18, 'line_total', 118)))) ->> 'id')::uuid;

  -- 9. Two lines of 1 against 1 sold must be refused as a whole.
  begin
    perform public.create_sale_return(jsonb_build_object(
      'invoice_id', v_inv, 'refund_amount', 0,
      'items', jsonb_build_array(
        jsonb_build_object('product_id', 'aaaaaaaa-2222-0000-0000-00000000000a', 'product_name', 'R0 Phone A', 'quantity', 1, 'line_total', 118),
        jsonb_build_object('product_id', 'aaaaaaaa-2222-0000-0000-00000000000a', 'product_name', 'R0 Phone A', 'quantity', 1, 'line_total', 118))));
    raise exception 'FAIL 9: duplicate return lines exceeded the sold quantity';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 9 (return quantity aggregated): %', sqlerrm;
  end;

  -- 10. A full return of an unpaid bill clears the bill's own due (D27),
  --     valued from the bill even if the client sends a bigger figure.
  v_ret := public.create_sale_return(jsonb_build_object(
    'invoice_id', v_inv, 'refund_amount', 500,
    'items', jsonb_build_array(
      jsonb_build_object('product_id', 'aaaaaaaa-2222-0000-0000-00000000000a', 'product_name', 'R0 Phone A', 'quantity', 1, 'line_total', 9999))));
  if (v_ret ->> 'total')::numeric <> 118 or (v_ret ->> 'refund')::numeric <> 0 then
    raise exception 'FAIL 10a: return valued % / refund % (expected 118 / 0)', v_ret ->> 'total', v_ret ->> 'refund';
  end if;
  if (select due_amount from public.invoices where id = v_inv) <> 0 then
    raise exception 'FAIL 10b: invoice still shows a due after full return';
  end if;
  if (select due_amount from public.customers where id = 'aaaaaaaa-3333-0000-0000-0000000000c1') <> 0 then
    raise exception 'FAIL 10c: customer balance disagrees with bills';
  end if;
  raise notice 'PASS 10 (return settles the bill; balances agree)';

  -- 11. Finding 9: a bill with returns can't be cancelled.
  begin
    perform public.cancel_invoice(v_inv);
    raise exception 'FAIL 11: cancelled a bill that has returns';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 11 (no cancel after return): %', sqlerrm;
  end;

  -- 12. Finding 19: a payment can't target another customer's bill.
  begin
    perform public.record_customer_payment('aaaaaaaa-3333-0000-0000-0000000000c2', 10, 'cash', current_date, '', v_inv);
    raise exception 'FAIL 12: payment applied to another customer''s bill';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 12 (payment must match the bill''s customer): %', sqlerrm;
  end;
end $$;

-- ============================================================
-- Cashier S (staff, default permissions)
-- ============================================================
select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-0000-0000-0000-00000000005a","role":"authenticated"}', true);

do $$ begin
  -- 13. Finding 4: reports need permission.
  begin
    perform public.get_profit_report(current_date - 30, current_date);
    raise exception 'FAIL 13: cashier opened the profit report';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 13 (reports need permission): %', sqlerrm;
  end;

  -- 14. Below-list price without price permission is refused …
  begin
    perform public.create_invoice(jsonb_build_object(
      'invoice_type', 'gst', 'paid_amount', 94.4, 'payment_mode', 'cash',
      'items', jsonb_build_array(jsonb_build_object(
        'product_id', 'aaaaaaaa-2222-0000-0000-00000000000a', 'product_name', 'R0 Phone A',
        'quantity', 1, 'unit_price', 80, 'gst_rate', 18, 'tax_amount', 14.4, 'line_total', 94.4))));
    raise exception 'FAIL 14a: cashier sold below list price';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 14a (price permission enforced): %', sqlerrm;
  end;
  -- … and the list price works.
  perform public.create_invoice(jsonb_build_object(
    'invoice_type', 'gst', 'paid_amount', 118, 'payment_mode', 'cash',
    'items', jsonb_build_array(jsonb_build_object(
      'product_id', 'aaaaaaaa-2222-0000-0000-00000000000a', 'product_name', 'R0 Phone A',
      'quantity', 1, 'unit_price', 100, 'gst_rate', 18, 'tax_amount', 18, 'line_total', 118))));
  raise notice 'PASS 14b (cashier bills at list price)';

  -- 15. Purchases need purchase permission.
  begin
    perform public.create_purchase(jsonb_build_object(
      'items', jsonb_build_array(jsonb_build_object(
        'product_id', 'aaaaaaaa-2222-0000-0000-00000000000a', 'product_name', 'R0 Phone A',
        'quantity', 5, 'unit_price', 80, 'line_total', 400))));
    raise exception 'FAIL 15: cashier created a purchase';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 15 (purchases need permission): %', sqlerrm;
  end;

  -- 16. Credit limits and balances are protected.
  begin
    update public.customers set credit_limit = 100000, credit_unlimited = false
      where id = 'aaaaaaaa-3333-0000-0000-0000000000c1';
    raise exception 'FAIL 16a: cashier changed a credit limit';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 16a (credit limits owner-only): %', sqlerrm;
  end;
  begin
    -- (c1's balance is 0 after check 10, so try a real change, not a no-op)
    update public.customers set due_amount = due_amount + 5000
      where id = 'aaaaaaaa-3333-0000-0000-0000000000c1';
    raise exception 'FAIL 16b: cashier edited a customer balance';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 16b (balances not directly editable): %', sqlerrm;
  end;

  -- 17. Staff see only their own profile.
  if (select count(*) from public.profiles) <> 1 then
    raise exception 'FAIL 17: cashier can see other profiles';
  end if;
  raise notice 'PASS 17 (staff see only themselves)';
end $$;

-- ============================================================
-- Finding 16: an expired shop is read-only, but can still collect money.
-- ============================================================
reset role;
select set_config('request.jwt.claims', '', true);
do $$
declare v_inv uuid;
begin
  -- a credit bill while still active …
  perform set_config('request.jwt.claims',
    '{"sub":"aaaaaaaa-0000-0000-0000-00000000000a","role":"authenticated"}', true);
  v_inv := (public.create_invoice(jsonb_build_object(
    'invoice_type', 'gst', 'customer_id', 'aaaaaaaa-3333-0000-0000-0000000000c1',
    'customer_name', 'R0 Local customer', 'paid_amount', 0, 'payment_mode', 'credit',
    'items', jsonb_build_array(jsonb_build_object(
      'product_id', 'aaaaaaaa-2222-0000-0000-00000000000a', 'product_name', 'R0 Phone A',
      'quantity', 1, 'unit_price', 100, 'gst_rate', 18, 'tax_amount', 18, 'line_total', 118)))) ->> 'id')::uuid;
  perform set_config('r0.inv', v_inv::text, true);
  perform set_config('request.jwt.claims', '', true);
  -- … then the subscription lapses.
  update public.subscriptions set expiry_date = current_date - 30
    where business_id = 'aaaaaaaa-1111-0000-0000-00000000000a';
end $$;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-0000-0000-0000-00000000000a","role":"authenticated"}', true);

do $$ begin
  begin
    perform public.create_invoice(jsonb_build_object(
      'invoice_type', 'gst', 'paid_amount', 118, 'payment_mode', 'cash',
      'items', jsonb_build_array(jsonb_build_object(
        'product_id', 'aaaaaaaa-2222-0000-0000-00000000000a', 'product_name', 'R0 Phone A',
        'quantity', 1, 'unit_price', 100, 'gst_rate', 18, 'tax_amount', 18, 'line_total', 118))));
    raise exception 'FAIL 18a: expired shop created a bill';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 18a (expired shop is read-only): %', sqlerrm;
  end;
  perform public.record_customer_payment('aaaaaaaa-3333-0000-0000-0000000000c1', 118, 'cash',
    current_date, 'r0', current_setting('r0.inv')::uuid);
  raise notice 'PASS 18b (expired shop can still receive payments)';
end $$;

reset role;
do $$ begin raise notice 'ALL R0 CHECKS PASSED — rolling back test data'; end $$;
rollback;
