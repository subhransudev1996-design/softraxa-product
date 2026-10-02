-- ============================================================
-- Collect the difference when a bill is edited (migration 0060).
--
-- HOW TO RUN — on a STAGING copy, after 0060:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('60606060-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'collect-owner@test.invalid'),
  ('60606060-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'collect-other@test.invalid');

insert into public.businesses (id, name, state_code) values
  ('60606060-1111-0000-0000-000000000001', 'Collect Shop', '27'),
  ('60606060-1111-0000-0000-000000000002', 'Other Shop', '27');
update public.profiles set business_id = '60606060-1111-0000-0000-000000000001', role = 'owner'
  where id = '60606060-0000-0000-0000-000000000001';
update public.profiles set business_id = '60606060-1111-0000-0000-000000000002', role = 'owner'
  where id = '60606060-0000-0000-0000-000000000002';
insert into public.subscriptions (business_id, status, expiry_date) values
  ('60606060-1111-0000-0000-000000000001', 'active', current_date + 30),
  ('60606060-1111-0000-0000-000000000002', 'active', current_date + 30);

insert into public.products (id, business_id, name, selling_price, purchase_price, gst_rate) values
  ('60606060-2222-0000-0000-000000000001', '60606060-1111-0000-0000-000000000001', 'Collect Fan', 500, 300, 0);
insert into public.stock_movements (business_id, product_id, movement_type, quantity, note) values
  ('60606060-1111-0000-0000-000000000001', '60606060-2222-0000-0000-000000000001', 'opening', 100, 'test');
insert into public.customers (id, business_id, name, credit_unlimited) values
  ('60606060-3333-0000-0000-000000000001', '60606060-1111-0000-0000-000000000001', 'Collect Badal', true);

create or replace function pg_temp.bill(p_customer uuid, p_qty numeric, p_paid numeric)
returns jsonb language sql as $$
  select jsonb_build_object(
    'invoice_type', 'non_gst', 'customer_id', p_customer, 'customer_name', 'x',
    'paid_amount', p_paid, 'payment_mode', case when p_paid > 0 then 'cash' else 'credit' end,
    'items', jsonb_build_array(jsonb_build_object(
      'product_id', '60606060-2222-0000-0000-000000000001', 'product_name', 'Collect Fan',
      'quantity', p_qty, 'unit_price', 500, 'gst_rate', 0, 'tax_amount', 0,
      'line_total', p_qty * 500)));
$$;

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

do $$
declare
  owner constant uuid := '60606060-0000-0000-0000-000000000001';
  other constant uuid := '60606060-0000-0000-0000-000000000002';
  badal constant uuid := '60606060-3333-0000-0000-000000000001';
  inv uuid; walk uuid; r record; due numeric; cash0 numeric; cash1 numeric;
begin
  perform pg_temp.act(owner);

  -- 1. A paid bill edited from 1 to 2 fans: ₹500 due, also on Badal's khata.
  inv := (public.create_invoice(pg_temp.bill(badal, 1, 500)) ->> 'id')::uuid;
  perform public.update_invoice(inv, pg_temp.bill(badal, 2, 0));
  select * into r from public.invoices where id = inv;
  select due_amount into due from public.customers where id = badal;
  if r.total <> 1000 or r.paid_amount <> 500 or due <> 500 then
    raise exception 'FAIL 1 setup: total % paid % khata due %', r.total, r.paid_amount, due;
  end if;

  -- 2. Collect the ₹500 on the spot: bill paid, khata back to 0, cash in.
  cash0 := (public.get_cashbook(public.ist_date(now())) ->> 'cash_in')::numeric;
  perform public.collect_invoice_payment(inv, 500, 'cash');
  select * into r from public.invoices where id = inv;
  select due_amount into due from public.customers where id = badal;
  if r.paid_amount <> 1000 or r.payment_status <> 'paid' or due <> 0 then
    raise exception 'FAIL 2: paid % status % khata due %', r.paid_amount, r.payment_status, due;
  end if;
  cash1 := (public.get_cashbook(public.ist_date(now())) ->> 'cash_in')::numeric;
  if cash1 - cash0 <> 500 then
    raise exception 'FAIL 2b: cashbook cash in moved by % instead of 500', cash1 - cash0;
  end if;
  raise notice 'PASS 2 (customer bill: paid, khata cleared, cash counted)';

  -- 3. Walk-in bill edited up, then collected by UPI.
  walk := (public.create_invoice(pg_temp.bill(null, 1, 500)) ->> 'id')::uuid;
  perform public.update_invoice(walk, pg_temp.bill(null, 3, 0));
  perform public.collect_invoice_payment(walk, 600, 'upi');
  select * into r from public.invoices where id = walk;
  if r.paid_amount <> 1100 or r.payment_status <> 'partial' then
    raise exception 'FAIL 3: walk-in paid % status %', r.paid_amount, r.payment_status;
  end if;
  if (select count(*) from public.invoice_payments where invoice_id = walk and payment_mode = 'upi' and amount = 600) <> 1 then
    raise exception 'FAIL 3b: walk-in UPI payment row missing';
  end if;
  raise notice 'PASS 3 (walk-in bill: payment recorded on the bill)';

  -- 4. Guards: more than the due, credit as a mode, another shop's bill.
  begin
    perform public.collect_invoice_payment(walk, 401, 'cash');
    raise exception 'FAIL 4a: collected more than the due';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    perform public.collect_invoice_payment(walk, 100, 'credit');
    raise exception 'FAIL 4b: "credit" accepted as money received';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform pg_temp.act(other);
  begin
    perform public.collect_invoice_payment(walk, 100, 'cash');
    raise exception 'FAIL 4c: another shop collected on this bill';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 4 (over-collection, credit mode and other shops refused)';
end $$;

rollback;
select set_config('request.jwt.claims', '', false);
