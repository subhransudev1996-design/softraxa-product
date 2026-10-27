-- ============================================================
-- Reversing supplier payments and undoing returns (migration 0092).
--
-- HOW TO RUN — on a STAGING copy, after 0087–0092:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes with "reversals tests passed". The first
-- failed check stops the run with "FAIL …".
--
-- A kirana (no GST on these items): Rice ₹100 (cost ₹80). Supplier
-- Gupta. Owner O, cashier S.
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);
select set_config('request.headers', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('92929292-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'rev-owner@test.invalid'),
  ('92929292-0000-0000-0000-0000000000a5', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'rev-staff@test.invalid');
insert into public.businesses (id, name, state_code, business_type, tax_preference) values
  ('92929292-1111-0000-0000-00000000000a', 'Reversal Kirana', '21', 'grocery', 'non_gst');
update public.profiles set business_id = '92929292-1111-0000-0000-00000000000a', role = 'owner'
  where id = '92929292-0000-0000-0000-00000000000a';
update public.profiles set business_id = '92929292-1111-0000-0000-00000000000a', role = 'staff'
  where id = '92929292-0000-0000-0000-0000000000a5';
insert into public.plans (id, name, software_id, user_limit, included_features)
select '92929292-9999-0000-0000-000000000001', 'Reversal Plan', id, 3, '[]'
from public.software_products where slug = 'dukania';
insert into public.subscriptions (business_id, plan_id, status, expiry_date) values
  ('92929292-1111-0000-0000-00000000000a', '92929292-9999-0000-0000-000000000001', 'active', current_date + 30);
insert into public.suppliers (id, business_id, name) values
  ('92929292-4444-0000-0000-000000000001', '92929292-1111-0000-0000-00000000000a', 'Rev Gupta');
insert into public.products (id, business_id, name, selling_price, purchase_price, gst_rate) values
  ('92929292-2222-0000-0000-000000000001', '92929292-1111-0000-0000-00000000000a', 'Rev Rice', 100, 80, 0);
insert into public.customers (id, business_id, name, phone, credit_unlimited) values
  ('92929292-3333-0000-0000-000000000001', '92929292-1111-0000-0000-00000000000a', 'Rev Ramesh', '9000000092', true);

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
create or replace function pg_temp.stock() returns numeric language sql as $$
  select current_stock from public.products where id = '92929292-2222-0000-0000-000000000001';
$$;
create or replace function pg_temp.owed() returns numeric language sql as $$
  select due_amount from public.suppliers where id = '92929292-4444-0000-0000-000000000001';
$$;
-- A purchase of p_qty rice at ₹80 on credit.
create or replace function pg_temp.buy(p_qty numeric) returns uuid language sql as $$
  select (public.create_purchase(jsonb_build_object(
    'supplier_id', '92929292-4444-0000-0000-000000000001', 'supplier_name', 'Rev Gupta',
    'paid_amount', 0, 'payment_mode', 'credit',
    'items', jsonb_build_array(jsonb_build_object(
      'product_id', '92929292-2222-0000-0000-000000000001', 'product_name', 'Rev Rice',
      'quantity', p_qty, 'unit_price', 80, 'gst_rate', 0, 'tax_amount', 0, 'line_total', p_qty * 80)))) ->> 'id')::uuid;
$$;
-- A cash (or credit) sale of p_qty rice.
create or replace function pg_temp.sell(p_qty numeric, p_ref text, p_credit boolean default false) returns uuid language sql as $$
  select (public.ai_create_sale(jsonb_build_object('sale_ref', p_ref,
    'lines', jsonb_build_array(jsonb_build_object('product_id', '92929292-2222-0000-0000-000000000001', 'quantity', p_qty)))
    || case when p_credit then '{"paid": "none", "customer_id": "92929292-3333-0000-0000-000000000001"}'::jsonb else '{}'::jsonb end)
    ->> 'bill_id')::uuid;
$$;

set local role authenticated;

-- 1. Supplier payment: where it went is recorded, and it can be reversed.
do $$
declare p1 uuid; p2 uuid; pay uuid;
begin
  perform pg_temp.act('92929292-0000-0000-0000-00000000000a');
  p1 := pg_temp.buy(10);   -- ₹800
  p2 := pg_temp.buy(10);   -- ₹800
  if pg_temp.owed() <> 1600 then raise exception 'FAIL 1a: owe 1600 expected, %', pg_temp.owed(); end if;
  pay := public.record_supplier_payment('92929292-4444-0000-0000-000000000001', 1000, 'cash', current_date, 'test');
  if (select paid_amount from public.purchases where id = p1) <> 800
     or (select paid_amount from public.purchases where id = p2) <> 200 or pg_temp.owed() <> 600 then
    raise exception 'FAIL 1b: oldest first: 800 + 200, owe 600';
  end if;

  perform pg_temp.act('92929292-0000-0000-0000-0000000000a5');
  begin
    perform public.reverse_supplier_payment(pay, 'staff try');
    raise exception 'FAIL 1c: staff reversed a payment';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if;
  end;

  perform pg_temp.act('92929292-0000-0000-0000-00000000000a');
  perform public.reverse_supplier_payment(pay, 'Entered twice');
  if (select paid_amount from public.purchases where id = p1) <> 0
     or (select paid_amount from public.purchases where id = p2) <> 0 or pg_temp.owed() <> 1600 then
    raise exception 'FAIL 1d: reversal should leave both unpaid and owe 1600';
  end if;
  begin
    perform public.reverse_supplier_payment(pay, 'again');
    raise exception 'FAIL 1f: reversed twice';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if;
  end;
end $$;

-- The cash book shows the ₹1000 back (cash_movements is internal: checked as the owner of the database).
reset role;
do $$
begin
  if not exists (select 1 from public.cash_movements('92929292-1111-0000-0000-00000000000a',
                   public.ist_date(now()), public.ist_date(now()))
                 where source = 'supplier_payment_reversal' and amount = 1000 and direction = 1) then
    raise exception 'FAIL 1e: the cash book should show the ₹1000 back';
  end if;
end $$;
set local role authenticated;

-- 2. Undo a sale return: stock and refund back; credit bill's credit back.
do $$
declare b uuid; r jsonb; line uuid; s numeric;
begin
  perform pg_temp.act('92929292-0000-0000-0000-00000000000a');
  b := pg_temp.sell(3, '92929292-5555-0000-0000-000000000001');
  s := pg_temp.stock();
  select id into line from public.invoice_items where invoice_id = b;
  r := public.ai_return(jsonb_build_object('bill_id', b, 'ref', '92929292-5555-0000-0000-000000000002',
         'lines', jsonb_build_array(jsonb_build_object('bill_line_id', line, 'quantity', 1))), true);
  if pg_temp.stock() <> s + 1 then raise exception 'FAIL 2a: return should add 1 to stock'; end if;
  perform public.undo_sale_return((r ->> 'return_id')::uuid, 'Customer kept it');
  if pg_temp.stock() <> s or exists (select 1 from public.sale_returns where id = (r ->> 'return_id')::uuid) then
    raise exception 'FAIL 2b: undo should remove the return and its stock';
  end if;

  -- On a credit bill the return had lowered what Ramesh owes; undo raises it back.
  b := pg_temp.sell(2, '92929292-5555-0000-0000-000000000003', true);
  select id into line from public.invoice_items where invoice_id = b;
  r := public.ai_return(jsonb_build_object('bill_id', b, 'ref', '92929292-5555-0000-0000-000000000004', 'refund', 'none',
         'lines', jsonb_build_array(jsonb_build_object('bill_line_id', line, 'quantity', 1))), true);
  if (select due_amount from public.customers where id = '92929292-3333-0000-0000-000000000001') <> 100 then
    raise exception 'FAIL 2c: Ramesh should owe 100 after the return';
  end if;
  perform public.undo_sale_return((r ->> 'return_id')::uuid, 'Wrong item');
  if (select due_amount from public.customers where id = '92929292-3333-0000-0000-000000000001') <> 200
     or (select credit_amount from public.invoices where id = b) <> 0 then
    raise exception 'FAIL 2d: undo should put the 200 due and the bill back';
  end if;
end $$;

-- 3. A returned item sold again can't have its return undone; nor an old month.
do $$
declare b uuid; r jsonb; line uuid;
begin
  perform pg_temp.act('92929292-0000-0000-0000-00000000000a');
  b := pg_temp.sell(pg_temp.stock(), '92929292-5555-0000-0000-000000000005');   -- sell all
  select id into line from public.invoice_items where invoice_id = b;
  r := public.ai_return(jsonb_build_object('bill_id', b, 'ref', '92929292-5555-0000-0000-000000000006',
         'lines', jsonb_build_array(jsonb_build_object('bill_line_id', line, 'quantity', 1))), true);
  perform pg_temp.sell(1, '92929292-5555-0000-0000-000000000007');               -- sold again
  begin
    perform public.undo_sale_return((r ->> 'return_id')::uuid, 'try');
    raise exception 'FAIL 3a: undid a return whose item was sold again';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if;
  end;
end $$;

reset role;
update public.sale_returns set return_date = now() - interval '40 days'
  where business_id = '92929292-1111-0000-0000-00000000000a';
set local role authenticated;
do $$
declare rid uuid;
begin
  perform pg_temp.act('92929292-0000-0000-0000-00000000000a');
  select id into rid from public.sale_returns where business_id = '92929292-1111-0000-0000-00000000000a' limit 1;
  begin
    perform public.undo_sale_return(rid, 'old one');
    raise exception 'FAIL 3b: undid a return from an earlier month';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if;
  end;
end $$;

-- 4. Undo a purchase return: stock back, the supplier is owed again.
do $$
declare p uuid; r jsonb; s numeric; o numeric;
begin
  perform pg_temp.act('92929292-0000-0000-0000-00000000000a');
  p := pg_temp.buy(5);   -- ₹400 on credit
  s := pg_temp.stock(); o := pg_temp.owed();
  r := public.ai_purchase_return(jsonb_build_object('purchase_id', p, 'ref', '92929292-5555-0000-0000-000000000008',
         'lines', jsonb_build_array(jsonb_build_object('product_id', '92929292-2222-0000-0000-000000000001', 'quantity', 2))), true);
  if pg_temp.stock() <> s - 2 or pg_temp.owed() <> o - 160 then raise exception 'FAIL 4a: return of 2 should be -2 stock, -160 owed'; end if;
  perform public.undo_purchase_return((r ->> 'return_id')::uuid, 'Supplier refused');
  if pg_temp.stock() <> s or pg_temp.owed() <> o or (select credit_amount from public.purchases where id = p) <> 0
     or exists (select 1 from public.purchase_returns where id = (r ->> 'return_id')::uuid) then
    raise exception 'FAIL 4b: undo should restore stock, what is owed and the purchase';
  end if;
end $$;

select 'reversals tests passed' as result;

rollback;
