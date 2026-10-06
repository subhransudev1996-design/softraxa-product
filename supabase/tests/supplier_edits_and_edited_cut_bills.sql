-- ============================================================
-- Migration 0065: suppliers can be edited and deleted again (balances
-- and advances stay protected), and an edited bill of a cut-length
-- product keeps its pieces in step with stock.
--
-- HOW TO RUN — after 0065:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error.
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('65656565-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'sup-owner@test.invalid');
insert into public.businesses (id, name, state_code) values
  ('65656565-1111-0000-0000-000000000001', 'Supplier Fix Shop', '27');
update public.profiles set business_id = '65656565-1111-0000-0000-000000000001', role = 'owner'
  where id = '65656565-0000-0000-0000-000000000001';
insert into public.subscriptions (business_id, status, expiry_date) values
  ('65656565-1111-0000-0000-000000000001', 'active', current_date + 30);

-- Pipe: 12 ft full length.
insert into public.products (id, business_id, name, selling_price, purchase_price, gst_rate,
  track_pieces, piece_length) values
  ('65656565-2222-0000-0000-000000000001', '65656565-1111-0000-0000-000000000001',
   'Fix Pipe', 50, 40, 0, true, 12);
insert into public.stock_movements (business_id, product_id, movement_type, quantity, note) values
  ('65656565-1111-0000-0000-000000000001', '65656565-2222-0000-0000-000000000001', 'opening', 12, 'test');

create or replace function pg_temp.pieces(p uuid) returns text language sql as $$
  select coalesce(string_agg(trim(trailing '.' from trim(trailing '0' from length::text)), ','
                  order by length desc), '')
  from public.stock_pieces where product_id = p and status = 'available';
$$;

create or replace function pg_temp.bill(p_qty numeric) returns jsonb language sql as $$
  select jsonb_build_object(
    'invoice_type', 'non_gst', 'customer_name', '', 'payment_mode', 'cash',
    'paid_amount', p_qty * 50,
    'items', jsonb_build_array(jsonb_build_object(
      'product_id', '65656565-2222-0000-0000-000000000001', 'product_name', 'Fix Pipe',
      'quantity', p_qty, 'unit_name', 'ft', 'unit_price', 50, 'gst_rate', 0, 'tax_amount', 0,
      'line_total', p_qty * 50)));
$$;

select set_config('request.jwt.claims',
  json_build_object('sub', '65656565-0000-0000-0000-000000000001', 'role', 'authenticated')::text, true);
set local role authenticated;

do $$
declare
  biz  constant uuid := '65656565-1111-0000-0000-000000000001';
  pipe constant uuid := '65656565-2222-0000-0000-000000000001';
  sup uuid; cus uuid; inv uuid;
begin
  insert into public.suppliers (business_id, name) values (biz, 'Old Name') returning id into sup;
  insert into public.customers (business_id, name) values (biz, 'Kiran') returning id into cus;

  -- 1. Edit and delete (hide) a supplier.
  update public.suppliers set name = 'New Name', phone = '9000000000' where id = sup;
  update public.suppliers set is_active = false where id = sup;
  if (select name || '/' || is_active from public.suppliers where id = sup) <> 'New Name/false' then
    raise exception 'FAIL 1: supplier not updated';
  end if;
  raise notice 'PASS 1 (supplier edited and hidden)';

  -- 2. Balances still can't be typed in.
  begin
    update public.suppliers set due_amount = 500 where id = sup;
    raise exception 'FAIL 2: supplier due changed directly';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  begin
    update public.customers set advance_amount = 500 where id = cus;
    raise exception 'FAIL 2b: customer advance changed directly';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  raise notice 'PASS 2 (due and advance still protected)';

  -- 3. Customers still editable.
  update public.customers set name = 'Kiran B' where id = cus;
  if (select name from public.customers where id = cus) <> 'Kiran B' then
    raise exception 'FAIL 3';
  end if;
  raise notice 'PASS 3 (customer edit unchanged)';

  -- 4. Bill 7 ft of the 12 ft pipe → 5 ft left. Edit it to 5 ft: the 7 ft
  --    comes back, 5 ft is cut again → one 7 ft piece, matching stock.
  inv := (public.create_invoice(pg_temp.bill(7)) ->> 'id')::uuid;
  if pg_temp.pieces(pipe) <> '5' then raise exception 'FAIL 4a: %', pg_temp.pieces(pipe); end if;
  perform public.update_invoice(inv, pg_temp.bill(5));
  if pg_temp.pieces(pipe) <> '7'
     or (select current_stock from public.products where id = pipe) <> 7 then
    raise exception 'FAIL 4: pieces % stock %', pg_temp.pieces(pipe),
      (select current_stock from public.products where id = pipe);
  end if;
  -- Saving the same edit again changes nothing.
  perform public.update_invoice(inv, pg_temp.bill(5));
  if pg_temp.pieces(pipe) <> '7' then raise exception 'FAIL 4b: %', pg_temp.pieces(pipe); end if;
  raise notice 'PASS 4 (edited cut bill keeps pieces = stock)';
end $$;

reset role;
do $$ begin raise notice 'ALL 0065 CHECKS PASSED — rolling back test data'; end $$;
rollback;
