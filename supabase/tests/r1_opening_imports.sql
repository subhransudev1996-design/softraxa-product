-- ============================================================
-- R1 opening balances and customer/supplier imports (migration 0051).
--
-- HOW TO RUN — on a STAGING copy, AFTER 0051 has been run on its own
-- (the 'opening' bill type only exists once that migration is committed):
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('bcbcbcbc-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'r1-open-owner@test.invalid'),
  ('bcbcbcbc-0000-0000-0000-00000000000c', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'r1-open-staff@test.invalid');

insert into public.businesses (id, name, state_code) values
  ('bcbcbcbc-1111-0000-0000-00000000000a', 'R1 Paper To Digital', '27');
update public.profiles set business_id = 'bcbcbcbc-1111-0000-0000-00000000000a', role = 'owner'
  where id = 'bcbcbcbc-0000-0000-0000-00000000000a';
update public.profiles set business_id = 'bcbcbcbc-1111-0000-0000-00000000000a', role = 'staff'
  where id = 'bcbcbcbc-0000-0000-0000-00000000000c';
insert into public.subscriptions (business_id, status, expiry_date) values
  ('bcbcbcbc-1111-0000-0000-00000000000a', 'active', current_date + 30);

insert into public.products (id, business_id, name, selling_price, purchase_price) values
  ('bcbcbcbc-2222-0000-0000-00000000000a', 'bcbcbcbc-1111-0000-0000-00000000000a', 'R1 Tap', 500, 300);
insert into public.stock_movements (business_id, product_id, movement_type, quantity, note) values
  ('bcbcbcbc-1111-0000-0000-00000000000a', 'bcbcbcbc-2222-0000-0000-00000000000a', 'opening', 10, 'r1 test');

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

do $$
declare
  owner  constant uuid := 'bcbcbcbc-0000-0000-0000-00000000000a';
  staff  constant uuid := 'bcbcbcbc-0000-0000-0000-00000000000c';
  as_of  constant date := public.ist_date(now()) - 10;
  v jsonb; asha uuid; bala uuid; sup uuid; ob record; bill uuid;
begin
  -- 1. Staff can't import.
  perform pg_temp.act(staff);
  begin
    perform public.import_customers('[{"name": "X"}]'::jsonb, as_of);
    raise exception 'FAIL 1: staff imported customers';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 1 (owner only)';

  -- 2. Import: 2 created, 1 duplicate skipped, 2 bad rows reported.
  perform pg_temp.act(owner);
  v := public.import_customers(jsonb_build_array(
    jsonb_build_object('name', 'R1 Asha', 'phone', '90000 00001', 'opening_balance', 1500,
                       'credit_limit', 10000),
    jsonb_build_object('name', 'R1 Bala', 'opening_balance', -200),
    jsonb_build_object('name', 'R1 Bad GST', 'gst_number', '27AAPFU0939F1ZX'),
    jsonb_build_object('name', 'R1 Asha again', 'phone', '9000000001'),
    jsonb_build_object('name', '  ', 'phone', '9000000009')), as_of);
  if (v ->> 'created')::int <> 2 or jsonb_array_length(v -> 'skipped') <> 1
     or jsonb_array_length(v -> 'errors') <> 2 then
    raise exception 'FAIL 2: %', v;
  end if;
  select id into asha from public.customers where name = 'R1 Asha';
  select id into bala from public.customers where name = 'R1 Bala';
  raise notice 'PASS 2 (2 imported, duplicate skipped, bad GSTIN and blank name reported)';

  -- 3. Opening due is an 'opening' bill due on the date + 30 days (PD20);
  --    a negative opening is an advance.
  select * into ob from public.invoices where customer_id = asha and invoice_type = 'opening';
  if (select due_amount from public.customers where id = asha) <> 1500
     or ob.total <> 1500 or ob.invoice_no not like 'OB-%' or ob.due_date <> as_of + 30
     or (select advance_amount from public.customers where id = bala) <> 200 then
    raise exception 'FAIL 3: due % bill % advance %',
      (select due_amount from public.customers where id = asha), row_to_json(ob),
      (select advance_amount from public.customers where id = bala);
  end if;
  raise notice 'PASS 3 (Asha owes 1,500 on %, due %; Bala has a 200 advance)', ob.invoice_no, ob.due_date;

  -- 4. A new credit bill, then a receipt: the opening due is settled first.
  bill := (public.create_invoice(jsonb_build_object(
    'invoice_type', 'non_gst', 'customer_id', asha, 'customer_name', 'R1 Asha',
    'paid_amount', 0, 'payment_mode', 'credit',
    'items', jsonb_build_array(jsonb_build_object(
      'product_id', 'bcbcbcbc-2222-0000-0000-00000000000a', 'product_name', 'R1 Tap',
      'quantity', 1, 'unit_price', 500, 'gst_rate', 0, 'tax_amount', 0, 'line_total', 500)))) ->> 'id')::uuid;
  perform public.record_customer_payment(asha, 1600, 'cash');
  if (select paid_amount from public.invoices where id = ob.id) <> 1500
     or (select paid_amount from public.invoices where id = bill) <> 100
     or (select due_amount from public.customers where id = asha) <> 400 then
    raise exception 'FAIL 4: opening paid %, bill paid %',
      (select paid_amount from public.invoices where id = ob.id),
      (select paid_amount from public.invoices where id = bill);
  end if;
  raise notice 'PASS 4 (receipt of 1,600 settled the opening 1,500 first, then 100 of the new bill)';

  -- 5. The sales report counts the real sale only.
  v := public.get_sales_report(as_of, public.ist_date(now()));
  if (v ->> 'total_sales')::numeric <> 500 or (v ->> 'invoice_count')::int <> 1 then
    raise exception 'FAIL 5: %', v;
  end if;
  raise notice 'PASS 5 (sales 500 — the opening balance is not a sale)';

  -- 6. An opening bill can't be edited, and a second one is refused.
  begin
    perform public.update_invoice(ob.id, '{"items": []}'::jsonb);
    raise exception 'FAIL 6a: opening bill edited';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    perform public.set_opening_balance('customer', asha, 100, as_of);
    raise exception 'FAIL 6b: second opening balance';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 6 (opening balance can''t be edited or duplicated)';

  -- 7. The opening date must be before today.
  begin
    perform public.set_opening_balance('customer', bala, 50, public.ist_date(now()));
    raise exception 'FAIL 7: opening dated today';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 7 (opening date before today)';

  -- 8. Suppliers: opening purchase owed; negative refused.
  v := public.import_suppliers(jsonb_build_array(
    jsonb_build_object('name', 'R1 Pipes Ltd', 'phone', '9100000001', 'gst_number', '29AAPFU0939F1ZR',
                       'opening_balance', 3000),
    jsonb_build_object('name', 'R1 Owes Us', 'opening_balance', -100)), as_of);
  select id into sup from public.suppliers where name = 'R1 Pipes Ltd';
  if (v ->> 'created')::int <> 1 or jsonb_array_length(v -> 'errors') <> 1
     or (select due_amount from public.suppliers where id = sup) <> 3000
     or (select state_code from public.suppliers where id = sup) <> '29'
     or not exists (select 1 from public.purchases where supplier_id = sup and is_opening
                    and total = 3000 and purchase_date = as_of) then
    raise exception 'FAIL 8: %', v;
  end if;
  raise notice 'PASS 8 (supplier owed 3,000 as an opening purchase; state 29 from GSTIN)';

  -- 9. Stored dues still match their documents (the nightly check's rule).
  if (select due_amount from public.customers where id = asha)
     <> (select sum(due_amount) from public.invoices where customer_id = asha and not is_cancelled) then
    raise exception 'FAIL 9: customer due doesn''t match its bills';
  end if;
  raise notice 'PASS 9 (customer due = its bills, opening included)';
end $$;

reset role;
do $$ begin raise notice 'ALL R1 OPENING/IMPORT CHECKS PASSED — rolling back test data'; end $$;
rollback;
