-- ============================================================
-- Fixing wrong entries: edit / delete purchases, change a bill's
-- customer, walk-in bills edited below what was paid (migration 0063).
--
-- HOW TO RUN — on a STAGING copy, after 0063:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('63636363-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'fix-owner@test.invalid'),
  ('63636363-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'fix-staff@test.invalid');

insert into public.businesses (id, name, state_code) values
  ('63636363-1111-0000-0000-000000000001', 'Fix Shop', '27');
update public.profiles set business_id = '63636363-1111-0000-0000-000000000001', role = 'owner'
  where id = '63636363-0000-0000-0000-000000000001';
update public.profiles set business_id = '63636363-1111-0000-0000-000000000001', role = 'staff'
  where id = '63636363-0000-0000-0000-000000000002';
insert into public.plans (id, name, software_id, user_limit, included_features)
select '63636363-9999-0000-0000-000000000001', 'Fix Two Users', id, 2, '[]'
from public.software_products where slug = 'dukania';
insert into public.subscriptions (business_id, plan_id, status, expiry_date) values
  ('63636363-1111-0000-0000-000000000001', '63636363-9999-0000-0000-000000000001',
   'active', current_date + 30);

insert into public.products (id, business_id, name, selling_price, purchase_price, gst_rate, track_serial) values
  ('63636363-2222-0000-0000-000000000001', '63636363-1111-0000-0000-000000000001', 'Fix Fan', 500, 300, 0, false),
  ('63636363-2222-0000-0000-000000000002', '63636363-1111-0000-0000-000000000001', 'Fix Phone', 9000, 8000, 0, true);
insert into public.stock_movements (business_id, product_id, movement_type, quantity, note) values
  ('63636363-1111-0000-0000-000000000001', '63636363-2222-0000-0000-000000000001', 'opening', 10, 'test');
insert into public.suppliers (id, business_id, name) values
  ('63636363-4444-0000-0000-000000000001', '63636363-1111-0000-0000-000000000001', 'Fix Supplier A'),
  ('63636363-4444-0000-0000-000000000002', '63636363-1111-0000-0000-000000000001', 'Fix Supplier B');
insert into public.customers (id, business_id, name, credit_unlimited) values
  ('63636363-3333-0000-0000-000000000001', '63636363-1111-0000-0000-000000000001', 'Fix Asha', true),
  ('63636363-3333-0000-0000-000000000002', '63636363-1111-0000-0000-000000000001', 'Fix Bilal', true);

-- A purchase payload: fans at a rate, paid, from a supplier (or null).
create or replace function pg_temp.pur(p_supplier uuid, p_qty numeric, p_rate numeric, p_paid numeric,
                                       p_mode text default 'cash')
returns jsonb language sql as $$
  select jsonb_build_object(
    'supplier_id', p_supplier, 'supplier_name', '', 'purchase_date', current_date,
    'paid_amount', p_paid, 'payment_mode', p_mode, 'bill_no', 'B-1',
    'items', jsonb_build_array(jsonb_build_object(
      'product_id', '63636363-2222-0000-0000-000000000001', 'product_name', 'Fix Fan',
      'quantity', p_qty, 'unit_price', p_rate, 'gst_rate', 0, 'tax_amount', 0,
      'line_total', p_qty * p_rate)));
$$;

create or replace function pg_temp.phones(p_serials text[]) returns jsonb language sql as $$
  select jsonb_build_object(
    'supplier_id', '63636363-4444-0000-0000-000000000001', 'purchase_date', current_date,
    'paid_amount', 0, 'payment_mode', 'credit',
    'items', jsonb_build_array(jsonb_build_object(
      'product_id', '63636363-2222-0000-0000-000000000002', 'product_name', 'Fix Phone',
      'quantity', cardinality(p_serials), 'unit_price', 8000, 'gst_rate', 0, 'tax_amount', 0,
      'line_total', cardinality(p_serials) * 8000, 'serial_nos', to_jsonb(p_serials))));
$$;

-- A bill: fans at ₹500, for a customer (or walk-in), paid.
create or replace function pg_temp.bill(p_customer uuid, p_qty numeric, p_paid numeric)
returns jsonb language sql as $$
  select jsonb_build_object(
    'invoice_type', 'non_gst', 'customer_id', p_customer, 'customer_name', '',
    'payment_mode', case when p_paid > 0 then 'cash' else 'credit' end, 'paid_amount', p_paid,
    'items', jsonb_build_array(jsonb_build_object(
      'product_id', '63636363-2222-0000-0000-000000000001', 'product_name', 'Fix Fan',
      'quantity', p_qty, 'unit_name', 'pcs', 'unit_price', 500, 'gst_rate', 0, 'tax_amount', 0,
      'line_total', p_qty * 500)));
$$;

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

do $$
declare
  owner constant uuid := '63636363-0000-0000-0000-000000000001';
  staff constant uuid := '63636363-0000-0000-0000-000000000002';
  fan   constant uuid := '63636363-2222-0000-0000-000000000001';
  supa  constant uuid := '63636363-4444-0000-0000-000000000001';
  supb  constant uuid := '63636363-4444-0000-0000-000000000002';
  asha  constant uuid := '63636363-3333-0000-0000-000000000001';
  bilal constant uuid := '63636363-3333-0000-0000-000000000002';
  p1 uuid; p2 uuid; p3 uuid; p4 uuid; inv uuid; inv2 uuid;
  r record; n numeric; ok boolean;
begin
  perform pg_temp.act(owner);

  -- 1. Wrong rate on a cash purchase (₹500 instead of ₹50), fully paid.
  --    Edit: rate, total, payment, product cost corrected; stock unchanged.
  p1 := (public.create_purchase(pg_temp.pur(supa, 5, 500, 2500)) ->> 'id')::uuid;
  perform public.update_purchase(p1, pg_temp.pur(supa, 5, 50, 250));
  select * into r from public.purchases where id = p1;
  if r.total <> 250 or r.paid_amount <> 250 or r.payment_status <> 'paid' then
    raise exception 'FAIL 1: total % paid % status %', r.total, r.paid_amount, r.payment_status;
  end if;
  if (select current_stock from public.products where id = fan) <> 15
     or (select purchase_price from public.products where id = fan) <> 50 then
    raise exception 'FAIL 1b: stock/cost not right';
  end if;
  if (select count(*) || ':' || sum(amount) from public.supplier_payments where purchase_id = p1) <> '1:250.00'
     or (select due_amount from public.suppliers where id = supa) <> 0 then
    raise exception 'FAIL 1c: payment row or supplier due wrong';
  end if;
  raise notice 'PASS 1 (wrong rate fixed: total, payment, cost)';

  -- 2. Credit purchase on the wrong supplier and quantity: fixed.
  p2 := (public.create_purchase(pg_temp.pur(supa, 10, 40, 0, 'credit')) ->> 'id')::uuid;
  if (select due_amount from public.suppliers where id = supa) <> 400 then raise exception 'FAIL 2a'; end if;
  perform public.update_purchase(p2, pg_temp.pur(supb, 8, 40, 0, 'credit'));
  if (select due_amount from public.suppliers where id = supa) <> 0
     or (select due_amount from public.suppliers where id = supb) <> 320
     or (select current_stock from public.products where id = fan) <> 23
     or (select supplier_name from public.purchases where id = p2) <> 'Fix Supplier B' then
    raise exception 'FAIL 2: dues/stock/supplier not moved';
  end if;
  raise notice 'PASS 2 (supplier and quantity fixed, due moved A → B)';

  -- 3. A later payment counted on it: supplier can't change, total can't go
  --    below it, delete refused; a smaller edit keeps that payment.
  perform public.record_supplier_payment(supb, 100, 'cash');
  begin
    perform public.update_purchase(p2, pg_temp.pur(supa, 8, 40, 0, 'credit'));
    raise exception 'FAIL 3a: supplier changed despite a later payment';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  begin
    perform public.update_purchase(p2, pg_temp.pur(supb, 1, 50, 0, 'credit'));
    raise exception 'FAIL 3b: total went below the later payment';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  begin
    perform public.delete_purchase(p2, 'test');
    raise exception 'FAIL 3c: deleted despite a later payment';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  perform public.update_purchase(p2, pg_temp.pur(supb, 5, 40, 0, 'credit'));
  select * into r from public.purchases where id = p2;
  if r.total <> 200 or r.paid_amount <> 100
     or (select due_amount from public.suppliers where id = supb) <> 100 then
    raise exception 'FAIL 3d: total % paid % due %', r.total, r.paid_amount,
      (select due_amount from public.suppliers where id = supb);
  end if;
  raise notice 'PASS 3 (later payments protected)';

  -- 4. Items already sold: the purchase can't be cut below stock.
  inv := (public.create_invoice(pg_temp.bill(null, 18, 9000)) ->> 'id')::uuid;   -- stock 20 → 2
  if (select current_stock from public.products where id = fan) <> 2 then raise exception 'FAIL 4a'; end if;
  begin
    perform public.delete_purchase(p1, 'test');
    raise exception 'FAIL 4b: deleted 5 fans with only 2 in stock';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  begin
    perform public.update_purchase(p1, pg_temp.pur(supa, 1, 50, 50));
    raise exception 'FAIL 4c: cut 5 → 1 with only 2 in stock';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  perform public.update_purchase(p1, pg_temp.pur(supa, 4, 50, 200));          -- −1 is fine
  if (select current_stock from public.products where id = fan) <> 1 then raise exception 'FAIL 4d'; end if;
  raise notice 'PASS 4 (stock already sold is protected)';

  -- 5. Delete a purchase entered by mistake: stock, due and payment undone.
  p3 := (public.create_purchase(pg_temp.pur(supa, 2, 60, 20)) ->> 'id')::uuid;   -- due 100
  if (select due_amount from public.suppliers where id = supa) <> 100 then raise exception 'FAIL 5a'; end if;
  perform public.delete_purchase(p3, 'entered twice');
  if exists (select 1 from public.purchases where id = p3)
     or exists (select 1 from public.supplier_payments where purchase_id = p3)
     or (select due_amount from public.suppliers where id = supa) <> 0
     or (select current_stock from public.products where id = fan) <> 1 then
    raise exception 'FAIL 5: delete did not undo everything';
  end if;
  raise notice 'PASS 5 (delete undoes stock, due and payment)';

  -- 6. Serials: a sold serial can't be taken off; an unsold one can.
  p4 := (public.create_purchase(pg_temp.phones(array['FIX-S1', 'FIX-S2'])) ->> 'id')::uuid;
  perform public.create_invoice(jsonb_build_object(
    'invoice_type', 'non_gst', 'customer_name', '', 'payment_mode', 'cash', 'paid_amount', 9000,
    'items', jsonb_build_array(jsonb_build_object(
      'product_id', '63636363-2222-0000-0000-000000000002', 'product_name', 'Fix Phone',
      'serial_no', 'FIX-S1', 'quantity', 1, 'unit_name', 'pcs', 'unit_price', 9000,
      'gst_rate', 0, 'tax_amount', 0, 'line_total', 9000))));
  begin
    perform public.update_purchase(p4, pg_temp.phones(array['FIX-S2']));
    raise exception 'FAIL 6a: sold serial removed';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  perform public.update_purchase(p4, pg_temp.phones(array['FIX-S1']));
  if exists (select 1 from public.product_serials where serial_no = 'FIX-S2')
     or (select status::text from public.product_serials where serial_no = 'FIX-S1') <> 'sold' then
    raise exception 'FAIL 6b: serials not as expected';
  end if;
  raise notice 'PASS 6 (serials: sold ones kept, unsold one removed)';

  -- 7. A purchase with a return can't be edited.
  perform public.create_purchase_return(jsonb_build_object('purchase_id', p1,
    'items', jsonb_build_array(jsonb_build_object('product_id', fan, 'product_name', 'Fix Fan', 'quantity', 1))));
  begin
    perform public.update_purchase(p1, pg_temp.pur(supa, 4, 45, 180));
    raise exception 'FAIL 7: edited a purchase with a return';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  raise notice 'PASS 7 (purchases with returns are locked)';

  -- 8. Staff without purchase permission can't edit or delete.
  perform pg_temp.act(staff);
  begin
    perform public.update_purchase(p2, pg_temp.pur(supb, 5, 40, 0, 'credit'));
    raise exception 'FAIL 8a: staff edited a purchase';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  begin
    perform public.delete_purchase(p2, 'x');
    raise exception 'FAIL 8b: staff deleted a purchase';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  perform pg_temp.act(owner);
  raise notice 'PASS 8 (permission needed)';

  -- 9. Bill on the wrong khata: moved with its due.
  perform public.create_purchase(pg_temp.pur(supa, 10, 50, 500));               -- stock for bills
  inv := (public.create_invoice(pg_temp.bill(asha, 1, 0)) ->> 'id')::uuid;
  if (select due_amount from public.customers where id = asha) <> 500 then raise exception 'FAIL 9a'; end if;
  perform public.change_invoice_customer(inv, bilal);
  if (select due_amount from public.customers where id = asha) <> 0
     or (select due_amount from public.customers where id = bilal) <> 500
     or (select customer_name from public.invoices where id = inv) <> 'Fix Bilal' then
    raise exception 'FAIL 9b: due/name not moved';
  end if;
  begin
    perform public.change_invoice_customer(inv, null);
    raise exception 'FAIL 9c: unpaid bill made walk-in';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  -- A khata payment on the bill locks the customer.
  perform public.collect_invoice_payment(inv, 200, 'cash');
  begin
    perform public.change_invoice_customer(inv, asha);
    raise exception 'FAIL 9d: moved a bill with a khata payment';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  -- Paid at the counter: can become walk-in, no khata change.
  inv2 := (public.create_invoice(pg_temp.bill(asha, 1, 500)) ->> 'id')::uuid;
  perform public.change_invoice_customer(inv2, null);
  if (select customer_id from public.invoices where id = inv2) is not null
     or (select due_amount from public.customers where id = asha) <> 0 then
    raise exception 'FAIL 9e: paid bill not moved to walk-in';
  end if;
  raise notice 'PASS 9 (bill moved to the right customer)';

  -- 10. Walk-in bill edited below what was paid: the extra is given back.
  inv := (public.create_invoice(pg_temp.bill(null, 2, 1000)) ->> 'id')::uuid;
  perform public.update_invoice(inv, pg_temp.bill(null, 1, 1000));
  select * into r from public.invoices where id = inv;
  select sum(amount) into n from public.invoice_payments where invoice_id = inv and not reversed;
  if r.total <> 500 or r.paid_amount <> 500 or r.due_amount <> 0 or n <> 500 then
    raise exception 'FAIL 10: total % paid % due % payments %', r.total, r.paid_amount, r.due_amount, n;
  end if;
  raise notice 'PASS 10 (walk-in overpayment handed back)';
end $$;

rollback;
