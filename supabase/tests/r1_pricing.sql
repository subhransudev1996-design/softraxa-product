-- ============================================================
-- R1 pricing and discount limits (migration 0043).
--
-- HOW TO RUN — on a STAGING copy, after 0043:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
--
-- Spec example (D15): retail 100, wholesale 90 (from 10 units), customer
-- Asha's agreed price 95. Staff A may change prices with a 5% limit;
-- staff B has default permissions (no price changes, PD08).
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('ffffffff-0000-0000-0000-00000000000f', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'r1-price-owner@test.invalid'),
  ('ffffffff-0000-0000-0000-0000000000a5', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'r1-price-staff-a@test.invalid'),
  ('ffffffff-0000-0000-0000-0000000000b5', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'r1-price-staff-b@test.invalid');

insert into public.businesses (id, name, state_code) values
  ('ffffffff-1111-0000-0000-00000000000f', 'R1 Pricing Shop', '27');

update public.profiles set business_id = 'ffffffff-1111-0000-0000-00000000000f', role = 'owner'
  where id = 'ffffffff-0000-0000-0000-00000000000f';
update public.profiles set business_id = 'ffffffff-1111-0000-0000-00000000000f', role = 'staff'
  where id in ('ffffffff-0000-0000-0000-0000000000a5', 'ffffffff-0000-0000-0000-0000000000b5');
insert into public.staff_permissions (profile_id, business_id, can_edit_prices, discount_limit_pct)
  values ('ffffffff-0000-0000-0000-0000000000a5', 'ffffffff-1111-0000-0000-00000000000f', true, 5);

insert into public.subscriptions (business_id, status, expiry_date) values
  ('ffffffff-1111-0000-0000-00000000000f', 'active', current_date + 30);

insert into public.products
  (id, business_id, name, selling_price, purchase_price, gst_rate, wholesale_price, wholesale_min_qty) values
  ('ffffffff-2222-0000-0000-00000000000f', 'ffffffff-1111-0000-0000-00000000000f',
   'R1 Cable', 100, 60, 0, 90, 10);
insert into public.stock_movements (business_id, product_id, movement_type, quantity, note) values
  ('ffffffff-1111-0000-0000-00000000000f', 'ffffffff-2222-0000-0000-00000000000f', 'opening', 500, 'r1 test');

insert into public.customers (id, business_id, name, credit_unlimited, is_wholesale) values
  ('ffffffff-3333-0000-0000-0000000000a1', 'ffffffff-1111-0000-0000-00000000000f', 'R1 Asha', true, false),
  ('ffffffff-3333-0000-0000-0000000000b1', 'ffffffff-1111-0000-0000-00000000000f', 'R1 Traders', true, true);
insert into public.customer_prices (business_id, customer_id, product_id, price) values
  ('ffffffff-1111-0000-0000-00000000000f', 'ffffffff-3333-0000-0000-0000000000a1',
   'ffffffff-2222-0000-0000-00000000000f', 95);

-- Bill helper: qty × unit price, optional line and bill discount, paid in cash.
create or replace function pg_temp.bill(p_customer uuid, p_qty numeric, p_price numeric,
                                        p_line_disc numeric default 0, p_bill_disc numeric default 0)
returns uuid language sql as $$
  select (public.create_invoice(jsonb_build_object(
    'invoice_type', 'non_gst', 'customer_id', p_customer, 'customer_name', 'x',
    'paid_amount', p_qty * p_price - p_line_disc - p_bill_disc, 'payment_mode', 'cash',
    'discount_amount', p_bill_disc,
    'items', jsonb_build_array(jsonb_build_object(
      'product_id', 'ffffffff-2222-0000-0000-00000000000f', 'product_name', 'R1 Cable',
      'quantity', p_qty, 'unit_price', p_price, 'discount_amount', p_line_disc,
      'gst_rate', 0, 'tax_amount', 0, 'line_total', p_qty * p_price - p_line_disc)))) ->> 'id')::uuid;
$$;

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

do $$
declare
  owner   constant uuid := 'ffffffff-0000-0000-0000-00000000000f';
  staff_a constant uuid := 'ffffffff-0000-0000-0000-0000000000a5';
  staff_b constant uuid := 'ffffffff-0000-0000-0000-0000000000b5';
  asha    constant uuid := 'ffffffff-3333-0000-0000-0000000000a1';
  traders constant uuid := 'ffffffff-3333-0000-0000-0000000000b1';
  b uuid;
  li record;
begin
  -- 1. The customer's agreed price is the default for her (D15 example).
  perform pg_temp.act(owner);
  b := pg_temp.bill(asha, 1, 95);
  select list_price, price_source into li from public.invoice_items where invoice_id = b;
  if li.list_price <> 95 or li.price_source <> 'customer'
     or (select price_reduction from public.invoices where id = b) <> 0 then
    raise exception 'FAIL 1: list % source %', li.list_price, li.price_source;
  end if;
  raise notice 'PASS 1 (customer price is the default: 95, not retail 100)';

  -- 2. Staff without price permission bills Asha at her price.
  perform pg_temp.act(staff_b);
  perform pg_temp.bill(asha, 1, 95);
  raise notice 'PASS 2 (staff can bill at the default price)';

  -- 3. …but can't pick the cheaper wholesale 90 for her.
  begin
    perform pg_temp.bill(asha, 1, 90);
    raise exception 'FAIL 3: staff without permission charged 90 instead of 95';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 3 (override needs permission): %', sqlerrm;
  end;

  -- 4. Staff A (5% limit) on 5 × 100 = 500: 25 off is allowed, 30 is not.
  perform pg_temp.act(staff_a);
  b := pg_temp.bill(null, 5, 100, 25);
  if (select price_reduction from public.invoices where id = b) <> 25 then
    raise exception 'FAIL 4a: reduction not recorded';
  end if;
  begin
    perform pg_temp.bill(null, 5, 100, 30);
    raise exception 'FAIL 4b: 6%% discount allowed with a 5%% limit';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 4 (limit enforced at exactly 5%%): %', sqlerrm;
  end;

  -- 5. PD07: a price change plus a bill discount count together.
  begin
    perform pg_temp.bill(null, 5, 98, 0, 20);     -- 10 + 20 = 30 off 500 = 6%
    raise exception 'FAIL 5: combined price change and bill discount bypassed the limit';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 5 (price change + bill discount share one limit): %', sqlerrm;
  end;

  -- 6. Quantity tier: 10 units at wholesale 90 is the default, even for staff B.
  perform pg_temp.act(staff_b);
  b := pg_temp.bill(null, 10, 90);
  select price_source into li from public.invoice_items where invoice_id = b;
  if li.price_source <> 'wholesale' then
    raise exception 'FAIL 6: source %', li.price_source;
  end if;
  raise notice 'PASS 6 (wholesale tier from 10 units)';

  -- 7. A wholesale customer gets 90 from the first unit.
  perform pg_temp.bill(traders, 1, 90);
  raise notice 'PASS 7 (wholesale customer priced at 90)';

  -- 8. Staff can't mark a customer wholesale or set agreed prices.
  begin
    update public.customers set is_wholesale = true where id = asha;
    raise exception 'FAIL 8a: staff made a customer wholesale';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 8a (wholesale flag needs price permission): %', sqlerrm;
  end;
  begin
    insert into public.customer_prices (business_id, customer_id, product_id, price)
    values ('ffffffff-1111-0000-0000-00000000000f', traders, 'ffffffff-2222-0000-0000-00000000000f', 50);
    raise exception 'FAIL 8b: staff set an agreed price';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 8b (agreed prices need price permission): %', sqlerrm;
  end;

  -- 9. Only the owner sets limits.
  perform pg_temp.act(staff_a);
  begin
    perform public.set_staff_discount_limit(staff_a, 50);
    raise exception 'FAIL 9a: staff raised their own limit';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 9a (staff can''t change limits): %', sqlerrm;
  end;
  perform pg_temp.act(owner);
  perform public.set_staff_discount_limit(staff_a, 10);
  perform pg_temp.act(staff_a);
  perform pg_temp.bill(null, 5, 100, 30);          -- 6% now within 10%
  raise notice 'PASS 9 (owner raised the limit to 10%%; 6%% now allowed)';
end $$;

reset role;
do $$ begin raise notice 'ALL R1 PRICING CHECKS PASSED — rolling back test data'; end $$;
rollback;
