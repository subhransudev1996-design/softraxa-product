-- ============================================================
-- R1 returns inspection and exchanges (migration 0042).
--
-- HOW TO RUN — on a STAGING copy, after 0042:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
--
-- Shop E (non-GST, ₹500 item). Owner; staff member with returns
-- permission but no stock permission (PD29); one customer.
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('eeeeeeee-0000-0000-0000-00000000000e', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'r1-ret-owner@test.invalid'),
  ('eeeeeeee-0000-0000-0000-00000000005e', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'r1-ret-staff@test.invalid');

insert into public.businesses (id, name, state_code) values
  ('eeeeeeee-1111-0000-0000-00000000000e', 'R1 Returns Shop', '27');

update public.profiles set business_id = 'eeeeeeee-1111-0000-0000-00000000000e', role = 'owner'
  where id = 'eeeeeeee-0000-0000-0000-00000000000e';
update public.profiles set business_id = 'eeeeeeee-1111-0000-0000-00000000000e', role = 'staff'
  where id = 'eeeeeeee-0000-0000-0000-00000000005e';
insert into public.staff_permissions (profile_id, business_id, can_manage_returns, can_manage_stock)
  values ('eeeeeeee-0000-0000-0000-00000000005e', 'eeeeeeee-1111-0000-0000-00000000000e', true, false);

insert into public.subscriptions (business_id, status, expiry_date) values
  ('eeeeeeee-1111-0000-0000-00000000000e', 'active', current_date + 30);

insert into public.products (id, business_id, name, selling_price, purchase_price, gst_rate) values
  ('eeeeeeee-2222-0000-0000-00000000000e', 'eeeeeeee-1111-0000-0000-00000000000e',
   'R1 Kettle', 500, 300, 0);
insert into public.stock_movements (business_id, product_id, movement_type, quantity, note) values
  ('eeeeeeee-1111-0000-0000-00000000000e', 'eeeeeeee-2222-0000-0000-00000000000e', 'opening', 50, 'r1 test');

insert into public.customers (id, business_id, name, credit_unlimited) values
  ('eeeeeeee-3333-0000-0000-0000000000c1', 'eeeeeeee-1111-0000-0000-00000000000e', 'R1 Meena', true);

-- Bill helper: qty × ₹500 for the customer (null = walk-in), paid as given.
create or replace function pg_temp.bill(p_customer uuid, p_qty int, p_paid numeric, p_days_ago int default 0)
returns uuid language sql as $$
  select (public.create_invoice(jsonb_build_object(
    'invoice_type', 'non_gst', 'customer_id', p_customer, 'customer_name', 'x',
    'paid_amount', p_paid, 'payment_mode', case when p_paid > 0 then 'cash' else 'credit' end,
    'invoice_date', now() - make_interval(days => p_days_ago),
    'items', jsonb_build_array(jsonb_build_object(
      'product_id', 'eeeeeeee-2222-0000-0000-00000000000e', 'product_name', 'R1 Kettle',
      'quantity', p_qty, 'unit_price', 500, 'gst_rate', 0, 'tax_amount', 0,
      'line_total', p_qty * 500)))) ->> 'id')::uuid;
$$;

-- Return line helper.
create or replace function pg_temp.line(p_qty numeric, p_condition text)
returns jsonb language sql as $$
  select jsonb_build_object('product_id', 'eeeeeeee-2222-0000-0000-00000000000e',
    'product_name', 'R1 Kettle', 'quantity', p_qty, 'condition', p_condition);
$$;

-- Replacement bill payload: qty × ₹500, cash collected now.
create or replace function pg_temp.sale(p_qty int, p_cash numeric)
returns jsonb language sql as $$
  select jsonb_build_object('invoice_type', 'non_gst', 'paid_amount', p_cash,
    'payment_mode', case when p_cash > 0 then 'cash' else 'credit' end,
    'items', jsonb_build_array(jsonb_build_object(
      'product_id', 'eeeeeeee-2222-0000-0000-00000000000e', 'product_name', 'R1 Kettle',
      'quantity', p_qty, 'unit_price', 500, 'gst_rate', 0, 'tax_amount', 0,
      'line_total', p_qty * 500)));
$$;

create or replace function pg_temp.stock() returns numeric language sql as $$
  select current_stock from public.products where id = 'eeeeeeee-2222-0000-0000-00000000000e';
$$;

create or replace function pg_temp.held(p_condition text) returns numeric language sql as $$
  select coalesce(sum(quantity), 0) from public.stock_hold_entries
  where product_id = 'eeeeeeee-2222-0000-0000-00000000000e' and condition = p_condition;
$$;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"eeeeeeee-0000-0000-0000-00000000000e","role":"authenticated"}', true);

-- ---------- 1. Mixed-condition return (D28 example) ----------
do $$
declare b uuid; v jsonb;
begin
  b := pg_temp.bill('eeeeeeee-3333-0000-0000-0000000000c1', 3, 1500);   -- stock 50 → 47
  v := public.create_sale_return(jsonb_build_object('invoice_id', b, 'refund_amount', 1500,
    'items', jsonb_build_array(pg_temp.line(1, 'sellable'), pg_temp.line(1, 'inspection'),
                               pg_temp.line(1, 'scrap'))));
  if pg_temp.stock() <> 48 or pg_temp.held('inspection') <> 1 or pg_temp.held('scrap') <> 1
     or (v ->> 'total')::numeric <> 1500 then
    raise exception 'FAIL 1: stock % inspection % scrap % value %',
      pg_temp.stock(), pg_temp.held('inspection'), pg_temp.held('scrap'), v ->> 'total';
  end if;
  raise notice 'PASS 1 (only the sellable unit went back to stock; 3 received)';
end $$;

-- ---------- 2. Staff: returns permission, no stock permission ----------
select set_config('request.jwt.claims',
  '{"sub":"eeeeeeee-0000-0000-0000-00000000005e","role":"authenticated"}', true);

do $$ begin
  perform public.move_held_stock('eeeeeeee-2222-0000-0000-00000000000e', null, 'inspection', 'damaged', 1);
  if pg_temp.held('inspection') <> 0 or pg_temp.held('damaged') <> 1 then
    raise exception 'FAIL 2a: reclassify inspection → damaged';
  end if;
  raise notice 'PASS 2a (staff with returns permission reclassifies)';
  begin
    perform public.move_held_stock('eeeeeeee-2222-0000-0000-00000000000e', null, 'damaged', 'sellable', 1);
    raise exception 'FAIL 2b: staff released held goods without stock permission';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 2b (release needs stock permission, PD29): %', sqlerrm;
  end;
end $$;

-- ---------- 3–4. Owner: release, dispose, over-move ----------
select set_config('request.jwt.claims',
  '{"sub":"eeeeeeee-0000-0000-0000-00000000000e","role":"authenticated"}', true);

do $$ begin
  perform public.move_held_stock('eeeeeeee-2222-0000-0000-00000000000e', null, 'damaged', 'sellable', 1,
    p_note => 'repaired');
  perform public.move_held_stock('eeeeeeee-2222-0000-0000-00000000000e', null, 'scrap', 'disposed', 1);
  if pg_temp.stock() <> 49 or pg_temp.held('damaged') <> 0 or pg_temp.held('scrap') <> 0 then
    raise exception 'FAIL 3: stock % damaged % scrap %', pg_temp.stock(), pg_temp.held('damaged'), pg_temp.held('scrap');
  end if;
  raise notice 'PASS 3 (release adds to sale once; disposal leaves stock unchanged)';
  begin
    perform public.move_held_stock('eeeeeeee-2222-0000-0000-00000000000e', null, 'damaged', 'scrap', 5);
    raise exception 'FAIL 4: moved more than was held';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 4 (can''t move more than held): %', sqlerrm;
  end;
end $$;

-- ---------- 5. Return window (PD25) ----------
do $$
declare b uuid; v jsonb;
begin
  b := pg_temp.bill('eeeeeeee-3333-0000-0000-0000000000c1', 1, 500, 40);
  begin
    perform public.create_sale_return(jsonb_build_object('invoice_id', b,
      'items', jsonb_build_array(pg_temp.line(1, 'sellable'))));
    raise exception 'FAIL 5a: 40-day-old bill returned without a reason';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 5a (window enforced): %', sqlerrm;
  end;
  v := public.create_sale_return(jsonb_build_object('invoice_id', b,
    'window_override_reason', 'manufacturing defect',
    'items', jsonb_build_array(pg_temp.line(1, 'damaged'))));
  if (select window_override_reason from public.sale_returns where id = (v ->> 'id')::uuid)
     <> 'manufacturing defect' then
    raise exception 'FAIL 5b: override reason not kept';
  end if;
  raise notice 'PASS 5b (owner accepts a late return with a reason)';
end $$;

-- ---------- 6–10. Exchanges (D29 examples) ----------
do $$
declare
  c1 constant uuid := 'eeeeeeee-3333-0000-0000-0000000000c1';
  b  uuid;
  v  jsonb;
  req uuid := gen_random_uuid();
  n_returns bigint;
  adv0 numeric;
begin
  -- 6. Paid item worth 1,000 (2 units) exchanged for 1,200-ish: here 3 units
  --    = 1,500 → credit 1,000, collect 500.
  b := pg_temp.bill(c1, 2, 1000);
  v := public.create_exchange(jsonb_build_object('request_id', gen_random_uuid(),
    'return', jsonb_build_object('invoice_id', b, 'items', jsonb_build_array(pg_temp.line(2, 'sellable'))),
    'sale', pg_temp.sale(3, 500)));
  if (v ->> 'credit_used')::numeric <> 1000 or (v ->> 'refund')::numeric <> 0
     or (select due_amount from public.invoices where id = (v ->> 'invoice_id')::uuid) <> 0 then
    raise exception 'FAIL 6: %', v;
  end if;
  raise notice 'PASS 6 (dearer replacement: credit used, difference collected)';

  -- 7. Cheaper replacement: credit 1,000, replacement 500 → 500 kept as advance.
  adv0 := (select advance_amount from public.customers where id = c1);
  b := pg_temp.bill(c1, 2, 1000);
  v := public.create_exchange(jsonb_build_object('request_id', gen_random_uuid(),
    'return', jsonb_build_object('invoice_id', b, 'items', jsonb_build_array(pg_temp.line(2, 'sellable'))),
    'sale', pg_temp.sale(1, 0), 'excess', 'advance'));
  if (v ->> 'advance')::numeric <> 500
     or (select advance_amount from public.customers where id = c1) <> adv0 + 500 then
    raise exception 'FAIL 7: %', v;
  end if;
  raise notice 'PASS 7 (cheaper replacement: excess kept as advance)';

  -- 8. Original still owes 400: 1,000 return settles 400 first, 600 credit
  --    left; a 1,500 replacement needs 900 more.
  b := pg_temp.bill(c1, 2, 600);
  v := public.create_exchange(jsonb_build_object('request_id', req,
    'return', jsonb_build_object('invoice_id', b, 'items', jsonb_build_array(pg_temp.line(2, 'sellable'))),
    'sale', pg_temp.sale(3, 900)));
  if (v ->> 'applied_to_original')::numeric <> 400 or (v ->> 'credit')::numeric <> 600
     or (select due_amount from public.invoices where id = b) <> 0
     or (select due_amount from public.invoices where id = (v ->> 'invoice_id')::uuid) <> 0 then
    raise exception 'FAIL 8: %', v;
  end if;
  raise notice 'PASS 8 (original due settled first, D27)';

  -- 9. A retried request isn't posted twice.
  n_returns := (select count(*) from public.sale_returns where invoice_id = b);
  v := public.create_exchange(jsonb_build_object('request_id', req,
    'return', jsonb_build_object('invoice_id', b, 'items', jsonb_build_array(pg_temp.line(2, 'sellable'))),
    'sale', pg_temp.sale(3, 900)));
  if not coalesce((v ->> 'already_done')::boolean, false)
     or (select count(*) from public.sale_returns where invoice_id = b) <> n_returns then
    raise exception 'FAIL 9: retry posted again';
  end if;
  raise notice 'PASS 9 (retry returns the first result)';

  -- 10. Walk-in exchange must be paid in full.
  b := pg_temp.bill(null, 1, 500);
  begin
    perform public.create_exchange(jsonb_build_object('request_id', gen_random_uuid(),
      'return', jsonb_build_object('invoice_id', b, 'items', jsonb_build_array(pg_temp.line(1, 'sellable'))),
      'sale', pg_temp.sale(2, 0)));
    raise exception 'FAIL 10: walk-in exchange left a due';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 10 (walk-in pays the full difference): %', sqlerrm;
  end;
end $$;

reset role;
do $$ begin raise notice 'ALL R1 RETURNS/EXCHANGE CHECKS PASSED — rolling back test data'; end $$;
rollback;
