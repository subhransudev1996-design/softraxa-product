-- ============================================================
-- R1 daily cashbook and closing (migration 0045).
--
-- HOW TO RUN — on a STAGING copy, after 0045:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
--
-- Spec example (D34): opening 1,000 + cash receipts 5,000 − cash expense
-- 500 − supplier payment 1,500 − refund 200 − bank deposit 2,000
-- = expected 1,800; counted 1,750 = short by 50. A UPI receipt doesn't
-- change the drawer.
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('88888888-0000-0000-0000-000000000008', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'r1-cash-owner@test.invalid'),
  ('88888888-0000-0000-0000-0000000000c8', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'r1-cash-cashier@test.invalid'),
  ('88888888-0000-0000-0000-0000000000d8', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'r1-cash-staff@test.invalid');

insert into public.businesses (id, name, state_code) values
  ('88888888-1111-0000-0000-000000000008', 'R1 Cash Shop', '27');

update public.profiles set business_id = '88888888-1111-0000-0000-000000000008', role = 'owner'
  where id = '88888888-0000-0000-0000-000000000008';
update public.profiles set business_id = '88888888-1111-0000-0000-000000000008', role = 'staff'
  where id in ('88888888-0000-0000-0000-0000000000c8', '88888888-0000-0000-0000-0000000000d8');
-- Cashier: cash drawer + expenses. Other staff: defaults (no cash).
insert into public.staff_permissions (profile_id, business_id, can_manage_cash, can_manage_expenses)
  values ('88888888-0000-0000-0000-0000000000c8', '88888888-1111-0000-0000-000000000008', true, true);

insert into public.subscriptions (business_id, status, expiry_date) values
  ('88888888-1111-0000-0000-000000000008', 'active', current_date + 30);

insert into public.products (id, business_id, name, selling_price, purchase_price, gst_rate) values
  ('88888888-2222-0000-0000-000000000008', '88888888-1111-0000-0000-000000000008', 'R1 Fan', 500, 300, 0);
insert into public.stock_movements (business_id, product_id, movement_type, quantity, note) values
  ('88888888-1111-0000-0000-000000000008', '88888888-2222-0000-0000-000000000008', 'opening', 100, 'r1 test');

insert into public.customers (id, business_id, name, credit_unlimited) values
  ('88888888-3333-0000-0000-0000000000a1', '88888888-1111-0000-0000-000000000008', 'R1 Asha', true);
insert into public.suppliers (id, business_id, name) values
  ('88888888-4444-0000-0000-0000000000a1', '88888888-1111-0000-0000-000000000008', 'R1 Wholesaler');

-- Yesterday was closed with 1,000 counted → today's opening (PD56).
insert into public.cash_closings
  (business_id, business_date, opening_cash, cash_in, cash_out, expected_cash, counted_cash,
   variance, snapshot, status)
values ('88888888-1111-0000-0000-000000000008', public.ist_date(now()) - 1,
        0, 1000, 0, 1000, 1000, 0, '{}', 'reviewed');

create or replace function pg_temp.sale(p_customer uuid, p_qty numeric, p_paid numeric, p_payments jsonb default null)
returns jsonb language sql as $$
  select jsonb_build_object(
    'invoice_type', 'non_gst', 'customer_id', p_customer, 'customer_name', 'x',
    'paid_amount', p_paid, 'payment_mode', case when p_paid > 0 then 'cash' else 'credit' end,
    'items', jsonb_build_array(jsonb_build_object(
      'product_id', '88888888-2222-0000-0000-000000000008', 'product_name', 'R1 Fan',
      'quantity', p_qty, 'unit_price', 500, 'gst_rate', 0, 'tax_amount', 0,
      'line_total', p_qty * 500)))
    || case when p_payments is null then '{}'::jsonb else jsonb_build_object('payments', p_payments) end;
$$;

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

do $$
declare
  owner   constant uuid := '88888888-0000-0000-0000-000000000008';
  cashier constant uuid := '88888888-0000-0000-0000-0000000000c8';
  staff   constant uuid := '88888888-0000-0000-0000-0000000000d8';
  asha    constant uuid := '88888888-3333-0000-0000-0000000000a1';
  today   constant date := public.ist_date(now());
  b uuid; v jsonb; c jsonb;
begin
  perform pg_temp.act(owner);
  -- cash in 5,000: 8 units cash (4,000) + split 500 cash / 500 UPI + Asha 500 cash
  perform public.create_invoice(pg_temp.sale(null, 8, 4000));
  perform public.create_invoice(pg_temp.sale(null, 2, 1000,
    '[{"mode": "cash", "amount": 500}, {"mode": "upi", "amount": 500}]'::jsonb));
  b := (public.create_invoice(pg_temp.sale(asha, 1, 500)) ->> 'id')::uuid;
  -- a credit sale is not cash
  perform public.create_invoice(pg_temp.sale(asha, 1, 0));
  -- cash out: expense 500, supplier 1,500, refund 200, bank deposit 2,000
  insert into public.expenses (business_id, amount, payment_mode, note)
    values ('88888888-1111-0000-0000-000000000008', 500, 'cash', 'r1 tea');
  perform public.record_supplier_payment('88888888-4444-0000-0000-0000000000a1', 1500, 'cash');
  perform public.create_sale_return(jsonb_build_object('invoice_id', b, 'refund_amount', 200,
    'refund_mode', 'cash', 'items', jsonb_build_array(jsonb_build_object(
      'product_id', '88888888-2222-0000-0000-000000000008', 'product_name', 'R1 Fan', 'quantity', 1))));
  perform public.add_cash_entry('bank_deposit', 2000, 'SBI');

  -- 1. Expected cash (D34 example).
  v := public.get_cashbook(today);
  if (v ->> 'opening')::numeric <> 1000 or (v ->> 'cash_in')::numeric <> 5000
     or (v ->> 'cash_out')::numeric <> 4200 or (v ->> 'expected')::numeric <> 1800 then
    raise exception 'FAIL 1: opening % in % out % expected %',
      v ->> 'opening', v ->> 'cash_in', v ->> 'cash_out', v ->> 'expected';
  end if;
  if (select (e ->> 'in')::numeric from jsonb_array_elements(v -> 'non_cash') e where e ->> 'mode' = 'upi') <> 500 then
    raise exception 'FAIL 1b: UPI not shown separately: %', v -> 'non_cash';
  end if;
  raise notice 'PASS 1 (expected 1,800; UPI 500 kept out of the drawer)';

  -- 2. Staff without the cash permission can't see it.
  perform pg_temp.act(staff);
  begin
    perform public.get_cashbook(today);
    raise exception 'FAIL 2: staff without cash permission opened the cashbook';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 2 (cash permission needed): %', sqlerrm;
  end;

  -- 3. Closing: a difference needs a reason; 1,750 counted = short by 50.
  perform pg_temp.act(cashier);
  begin
    perform public.submit_cash_closing(today, 1750);
    raise exception 'FAIL 3a: closed with a difference and no reason';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  c := public.submit_cash_closing(today, 1750, 'one 50 note missing');
  if (c ->> 'variance')::numeric <> -50 or (c ->> 'expected_cash')::numeric <> 1800 then
    raise exception 'FAIL 3b: %', c;
  end if;
  raise notice 'PASS 3 (closed: expected 1,800, counted 1,750, short 50)';

  -- 4. Can't close the same day twice.
  begin
    perform public.submit_cash_closing(today, 1800, 'again');
    raise exception 'FAIL 4: day closed twice';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 4 (one closing per day)';
  end;

  -- A sale made after the closing (its time is moved a minute later below:
  -- inside one test transaction every row gets the same timestamp).
  perform pg_temp.act(owner);
  perform set_config('r1.late', public.create_invoice(pg_temp.sale(null, 1, 500)) ->> 'id', true);
  perform set_config('r1.closing', c ->> 'id', true);
end $$;

reset role;
update public.invoice_payments set created_at = now() + interval '1 minute'
  where invoice_id = current_setting('r1.late')::uuid;
set local role authenticated;

do $$
declare
  owner   constant uuid := '88888888-0000-0000-0000-000000000008';
  cashier constant uuid := '88888888-0000-0000-0000-0000000000c8';
  today   constant date := public.ist_date(now());
  v jsonb;
  c jsonb := jsonb_build_object('id', current_setting('r1.closing'));
begin
  -- 5. Cash taken after closing goes to the next day; the closed day doesn't change (PD57).
  perform pg_temp.act(cashier);
  if (public.get_cashbook(today) ->> 'expected')::numeric <> 1800 then
    raise exception 'FAIL 5a: closed day changed';
  end if;
  v := public.get_cashbook(today + 1);
  if (v ->> 'opening')::numeric <> 1750 or (v ->> 'cash_in')::numeric <> 500 then
    raise exception 'FAIL 5b: next day opening % in %', v ->> 'opening', v ->> 'cash_in';
  end if;
  raise notice 'PASS 5 (late cash rolls to the next day; opening = counted 1,750)';

  -- 6. A closed day's cash expense can't be changed by staff (D36).
  begin
    update public.expenses set amount = 50 where note = 'r1 tea';
    raise exception 'FAIL 6: staff edited an expense in a closed day';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 6 (closed day locked): %', sqlerrm;
  end;

  -- 7. Only the owner reopens, with a reason; the old closing is kept.
  begin
    perform public.reopen_cash_closing((c ->> 'id')::uuid, 'recount');
    raise exception 'FAIL 7a: staff reopened a closing';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform pg_temp.act(owner);
  perform public.reopen_cash_closing((c ->> 'id')::uuid, 'found the 50 in the other drawer');
  v := public.get_cashbook(today);
  if v -> 'closing' <> 'null'::jsonb or jsonb_array_length(v -> 'history') <> 1
     or (v ->> 'cash_in')::numeric <> 5500 then
    raise exception 'FAIL 7b: closing % history % in %', v -> 'closing', v -> 'history', v ->> 'cash_in';
  end if;
  raise notice 'PASS 7 (owner reopened; history kept; the late sale is back in today)';

  -- 8. Closed again as version 2.
  perform pg_temp.act(cashier);
  c := public.submit_cash_closing(today, 2300);
  if (c ->> 'version')::int <> 2 or (c ->> 'variance')::numeric <> 0 then
    raise exception 'FAIL 8: %', c;
  end if;
  raise notice 'PASS 8 (re-closed as version 2, no difference)';

  -- 9. Owner reviews.
  perform pg_temp.act(owner);
  perform public.review_cash_closing((c ->> 'id')::uuid, 'ok');
  if (public.get_cashbook(today) -> 'closing' ->> 'status') <> 'reviewed' then
    raise exception 'FAIL 9: review not recorded';
  end if;
  raise notice 'PASS 9 (owner reviewed the closing)';
end $$;

reset role;
do $$ begin raise notice 'ALL R1 CASHBOOK CHECKS PASSED — rolling back test data'; end $$;
rollback;
