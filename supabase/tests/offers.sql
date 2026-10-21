-- ============================================================
-- Offers & coupons (migration 0084).
--
-- HOW TO RUN — on a STAGING copy, after 0084:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
--
-- A shop selling a ₹500 item and a ₹2000 item. The cashier has default
-- rights (no discounts at all). Offers:
--   Scratch & Win  — prizes ₹20/50/100, no code, bill ≥ ₹200, needs the
--                    customer's name and phone;
--   Diwali 10%     — shared code DIWALI10, at most ₹100, once per customer;
--   Voucher ₹100   — its own codes, each used once.
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('84848484-0000-0000-0000-00000000000f', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'offer-owner@test.invalid'),
  ('84848484-0000-0000-0000-0000000000b5', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'offer-cashier@test.invalid');

insert into public.businesses (id, name, state_code) values
  ('84848484-1111-0000-0000-00000000000f', 'Offer Test Shop', '21');
update public.profiles set business_id = '84848484-1111-0000-0000-00000000000f', role = 'owner'
  where id = '84848484-0000-0000-0000-00000000000f';
update public.profiles set business_id = '84848484-1111-0000-0000-00000000000f', role = 'staff'
  where id = '84848484-0000-0000-0000-0000000000b5';

insert into public.plans (id, name, software_id, user_limit, included_features)
select '84848484-9999-0000-0000-000000000001', 'Offer Two Users', id, 2, '[]'
from public.software_products where slug = 'dukania';
insert into public.subscriptions (business_id, plan_id, status, expiry_date) values
  ('84848484-1111-0000-0000-00000000000f', '84848484-9999-0000-0000-000000000001',
   'active', current_date + 30);

insert into public.products (id, business_id, name, selling_price, purchase_price, gst_rate) values
  ('84848484-2222-0000-0000-000000000500', '84848484-1111-0000-0000-00000000000f', 'Offer Item 500', 500, 300, 0),
  ('84848484-2222-0000-0000-000000002000', '84848484-1111-0000-0000-00000000000f', 'Offer Item 2000', 2000, 1200, 0);
insert into public.stock_movements (business_id, product_id, movement_type, quantity, note) values
  ('84848484-1111-0000-0000-00000000000f', '84848484-2222-0000-0000-000000000500', 'opening', 100, 'offer test'),
  ('84848484-1111-0000-0000-00000000000f', '84848484-2222-0000-0000-000000002000', 'opening', 100, 'offer test');

insert into public.customers (id, business_id, name, phone, credit_unlimited) values
  ('84848484-3333-0000-0000-0000000000a1', '84848484-1111-0000-0000-00000000000f', 'Offer Asha', '9876500001', true),
  ('84848484-3333-0000-0000-0000000000a2', '84848484-1111-0000-0000-00000000000f', 'Offer No Phone', '', true);

-- One-item cash bill with a bill discount and an offer.
create or replace function pg_temp.bill(p_price numeric, p_customer uuid, p_disc numeric,
                                        p_offer uuid, p_code text, p_offer_amount numeric)
returns uuid language sql as $$
  select (public.create_invoice(jsonb_build_object(
    'invoice_type', 'non_gst', 'customer_id', p_customer, 'customer_name', 'x',
    'paid_amount', p_price - p_disc, 'payment_mode', 'cash', 'discount_amount', p_disc,
    'offer_id', p_offer, 'offer_code', p_code, 'offer_amount', p_offer_amount,
    'items', jsonb_build_array(jsonb_build_object(
      'product_id', case when p_price = 2000 then '84848484-2222-0000-0000-000000002000'::uuid
                         else '84848484-2222-0000-0000-000000000500'::uuid end,
      'product_name', 'x', 'quantity', 1, 'unit_price', p_price, 'discount_amount', 0,
      'gst_rate', 0, 'tax_amount', 0, 'line_total', p_price)))) ->> 'id')::uuid;
$$;

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

-- Expects the statement to fail; raises FAIL with [label] if it doesn't.
create or replace function pg_temp.must_fail(p_sql text, p_label text) returns void
language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    return;
  end;
  raise exception 'FAIL %', p_label;
end $$;

set local role authenticated;

do $$
declare
  owner   constant uuid := '84848484-0000-0000-0000-00000000000f';
  cashier constant uuid := '84848484-0000-0000-0000-0000000000b5';
  asha    constant uuid := '84848484-3333-0000-0000-0000000000a1';
  nophone constant uuid := '84848484-3333-0000-0000-0000000000a2';
  scratch uuid; diwali uuid; voucher uuid; b uuid; n integer; v jsonb; o jsonb; r record;
begin
  -- 1. Offers: owner only, rules checked.
  perform pg_temp.act(owner);
  scratch := public.save_offer(null, jsonb_build_object(
    'name', 'Scratch & Win', 'kind', 'amount', 'amounts', jsonb_build_array(20, 50, 100),
    'min_bill', 200, 'code_mode', 'none', 'needs_customer', true));
  diwali := public.save_offer(null, jsonb_build_object(
    'name', 'Diwali 10%', 'kind', 'percent', 'percent', 10, 'max_discount', 100,
    'code_mode', 'shared', 'shared_code', 'diwali 10', 'uses_per_customer', 1));
  voucher := public.save_offer(null, jsonb_build_object(
    'name', 'Voucher 100', 'kind', 'amount', 'amounts', jsonb_build_array(100), 'code_mode', 'unique'));
  perform pg_temp.must_fail(format(
    'select public.save_offer(null, %L)', jsonb_build_object('name', 'Bad', 'kind', 'amount')),
    '1a: offer without an amount saved');
  perform pg_temp.act(cashier);
  perform pg_temp.must_fail(format(
    'select public.save_offer(null, %L)', jsonb_build_object('name', 'X', 'amounts', '[10]'::jsonb)),
    '1b: cashier made an offer');
  raise notice 'PASS 1 (offers: owner only, rules checked)';

  -- 2. Voucher codes: generated and pasted; no duplicates.
  perform pg_temp.act(owner);
  n := public.add_offer_codes(voucher, 5, 'tbw', '["SC-0001", "SC-0002"]'::jsonb);
  if n <> 7 or (select count(*) from public.offer_codes where offer_id = voucher) <> 7
     or (select count(*) from public.offer_codes where offer_id = voucher and code like 'TBW-______') <> 5 then
    raise exception 'FAIL 2a: % codes', n;
  end if;
  perform pg_temp.must_fail(format('select public.add_offer_codes(%L, 0, %L, %L)',
    voucher, '', '["sc 0001"]'), '2b: duplicate code added');
  perform pg_temp.must_fail(format('select public.add_offer_codes(%L, 0, %L, %L)',
    voucher, '', '["DIWALI10"]'), '2c: voucher code same as a shared code');
  raise notice 'PASS 2 (codes generated and pasted, no duplicates)';

  -- 3. Finding codes.
  perform pg_temp.act(cashier);
  v := public.find_offer_code('Diwali-10');
  if (v ->> 'offer_id')::uuid is distinct from diwali or not (v ->> 'usable')::boolean then
    raise exception 'FAIL 3a: %', v;
  end if;
  v := public.find_offer_code('sc0001');
  if (v ->> 'offer_id')::uuid is distinct from voucher or v ->> 'code' <> 'SC-0001' then
    raise exception 'FAIL 3b: %', v;
  end if;
  if (public.find_offer_code('NOPE123') ->> 'found')::boolean then
    raise exception 'FAIL 3c: unknown code found';
  end if;
  if jsonb_array_length(public.counter_offers()) <> 1 then
    raise exception 'FAIL 3d: counter offers %', public.counter_offers();
  end if;
  raise notice 'PASS 3 (codes found in any spacing; counter offers listed)';

  -- 4. Scratch card: the cashier (no discount rights) gives the ₹50 prize.
  b := pg_temp.bill(500, asha, 50, scratch, null, 50);
  select * into r from public.invoices where id = b;
  if r.offer_id is distinct from scratch or r.offer_amount <> 50 or r.offer_name <> 'Scratch & Win' then
    raise exception 'FAIL 4: % % %', r.offer_id, r.offer_amount, r.offer_name;
  end if;
  raise notice 'PASS 4 (scratch prize given by a cashier with no discount rights)';

  -- 5. Scratch rules: only the prizes, customer with phone, minimum bill.
  perform pg_temp.must_fail(format('select pg_temp.bill(500, %L, 70, %L, null, 70)', asha, scratch),
    '5a: ₹70 is not a prize');
  perform pg_temp.must_fail(format('select pg_temp.bill(500, null, 50, %L, null, 50)', scratch),
    '5b: no customer');
  perform pg_temp.must_fail(format('select pg_temp.bill(500, %L, 50, %L, null, 50)', nophone, scratch),
    '5c: customer without a phone');
  -- (as the owner: no discount limit, so only the minimum can refuse it)
  perform pg_temp.act(owner);
  perform pg_temp.must_fail(format('select pg_temp.bill(150, %L, 20, %L, null, 20)', asha, scratch),
    '5d: bill under the minimum');
  perform pg_temp.act(cashier);
  raise notice 'PASS 5 (prizes only; customer and phone; minimum bill)';

  -- 6. Shared code: 10% up to ₹100, once per customer.
  perform pg_temp.must_fail(format('select pg_temp.bill(2000, %L, 150, %L, %L, 150)', asha, diwali, 'DIWALI10'),
    '6a: more than the ₹100 cap');
  perform pg_temp.must_fail(format('select pg_temp.bill(500, %L, 50, %L, %L, 50)', asha, diwali, 'WRONG10'),
    '6b: wrong code');
  b := pg_temp.bill(2000, asha, 100, diwali, 'diwali10', 100);
  if (select offer_amount from public.invoices where id = b) <> 100 then
    raise exception 'FAIL 6c: shared code amount';
  end if;
  perform pg_temp.must_fail(format('select pg_temp.bill(500, %L, 50, %L, %L, 50)', asha, diwali, 'DIWALI10'),
    '6d: second use by the same customer');
  raise notice 'PASS 6 (shared code: capped, right code, once per customer)';

  -- 7. Voucher: used once; a cancelled bill frees it.
  b := pg_temp.bill(500, null, 100, voucher, 'sc-0001', 100);
  perform pg_temp.must_fail(format('select pg_temp.bill(500, null, 100, %L, %L, 100)', voucher, 'SC-0001'),
    '7a: voucher used twice');
  if (public.find_offer_code('SC-0001') ->> 'usable')::boolean then
    raise exception 'FAIL 7b: used voucher shown as usable';
  end if;
  perform pg_temp.act(owner);
  perform public.cancel_invoice(b);
  perform pg_temp.act(cashier);
  if not (public.find_offer_code('SC-0001') ->> 'usable')::boolean then
    raise exception 'FAIL 7c: cancelled bill did not free the voucher';
  end if;
  perform pg_temp.bill(500, null, 100, voucher, 'SC-0001', 100);
  raise notice 'PASS 7 (voucher once; cancel frees it)';

  -- 8. Nothing beyond the offer without discount rights.
  perform pg_temp.must_fail(format('select pg_temp.bill(500, %L, 120, %L, null, 50)', asha, scratch),
    '8a: ₹70 extra given with the scratch prize');
  perform pg_temp.must_fail(format('select pg_temp.bill(500, %L, 50, null, null, 0)', asha),
    '8b: ₹50 given with no offer');
  raise notice 'PASS 8 (only the offer''s amount is free)';

  -- 9. Bill offer fields can't be written directly.
  perform pg_temp.act(owner);
  update public.invoices set offer_amount = 999 where offer_id = scratch;
  if exists (select 1 from public.invoices where offer_amount = 999) then
    raise exception 'FAIL 9: offer written directly';
  end if;
  raise notice 'PASS 9 (shops can''t write a bill''s offer)';

  -- 10. Report: uses and amount given; customers with phones.
  v := public.get_offers(scratch);
  select value into o from jsonb_array_elements(v -> 'offers') where value ->> 'id' = scratch::text;
  if (o ->> 'uses')::int <> 1 or (o ->> 'given')::numeric <> 50
     or v -> 'uses' -> 0 ->> 'phone' <> '9876500001' then
    raise exception 'FAIL 10: %', v;
  end if;
  raise notice 'PASS 10 (report: uses, amount given, customer phone)';
end $$;

reset role;

-- 9b. Even with access rules bypassed, only billing sets the offer fields.
do $$
begin
  begin
    update public.invoices set offer_amount = 999
      where business_id = '84848484-1111-0000-0000-00000000000f' and offer_id is not null;
    raise exception 'FAIL 9b: offer written by a direct update';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 9b (the guard refuses direct writes)';
end $$;

do $$ begin raise notice 'ALL OFFER CHECKS PASSED — rolling back test data'; end $$;
rollback;
