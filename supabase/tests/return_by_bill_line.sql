-- ============================================================
-- Returns valued at the bill line's own price (migration 0075).
--
-- HOW TO RUN — on a STAGING copy, after 0075:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
--
-- Example: cigarettes, 1 Box = 10 pcs. One bill: 1 box at ₹95 (₹9.50 a
-- piece) + 3 loose pieces at ₹10. Before 0075 every piece came back at the
-- average ₹9.62.
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('75757575-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'rbl-owner@test.invalid');
insert into public.businesses (id, name, state_code) values
  ('75757575-1111-0000-0000-000000000001', 'RBL Pan Shop', '27');
update public.profiles set business_id = '75757575-1111-0000-0000-000000000001', role = 'owner'
  where id = '75757575-0000-0000-0000-000000000001';

insert into public.products
  (id, business_id, name, selling_price, purchase_price, gst_rate,
   secondary_unit_name, conversion_factor, pack_price) values
  ('75757575-2222-0000-0000-000000000001', '75757575-1111-0000-0000-000000000001',
   'RBL Cigarette', 10, 8, 0, 'Box', 10, 95),
  ('75757575-2222-0000-0000-000000000002', '75757575-1111-0000-0000-000000000001',
   'RBL Lighter', 20, 12, 0, null, null, null);
insert into public.stock_movements (business_id, product_id, movement_type, quantity, note) values
  ('75757575-1111-0000-0000-000000000001', '75757575-2222-0000-0000-000000000001', 'opening', 100, 'test'),
  ('75757575-1111-0000-0000-000000000001', '75757575-2222-0000-0000-000000000002', 'opening', 10, 'test');

create or replace function pg_temp.line(p_qty numeric, p_rate numeric, p_pack boolean)
returns jsonb language sql as $$
  select jsonb_build_object(
    'product_id', '75757575-2222-0000-0000-000000000001', 'product_name', 'RBL Cigarette',
    'quantity', p_qty, 'unit_name', 'pcs', 'unit_price', p_rate, 'gst_rate', 0, 'tax_amount', 0,
    'line_total', round(p_qty * p_rate, 2), 'pack', p_pack);
$$;

-- A return of p_qty pieces of the cigarette, from bill line p_line (null:
-- the way older app versions send it).
create or replace function pg_temp.ret(p_inv uuid, p_qty numeric, p_line uuid)
returns jsonb language sql as $$
  select public.create_sale_return(jsonb_build_object(
    'invoice_id', p_inv, 'refund_mode', 'cash', 'refund_amount', 0,
    'items', jsonb_build_array(jsonb_build_object(
      'product_id', '75757575-2222-0000-0000-000000000001', 'product_name', 'RBL Cigarette',
      'quantity', p_qty, 'condition', 'sellable', 'invoice_item_id', p_line))));
$$;

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

do $$
declare
  inv uuid; inv2 uuid; box_line uuid; loose_line uuid; lighter_line uuid; r jsonb; bad boolean;
begin
  perform pg_temp.act('75757575-0000-0000-0000-000000000001');
  inv := (public.create_invoice(jsonb_build_object(
            'invoice_type', 'non_gst', 'customer_name', 'x', 'payment_mode', 'cash',
            'paid_amount', 125,
            'items', jsonb_build_array(pg_temp.line(10, 9.5, true), pg_temp.line(3, 10, false))))
         ->> 'id')::uuid;
  select id into box_line from public.invoice_items where invoice_id = inv and sold_as_pack;
  select id into loose_line from public.invoice_items where invoice_id = inv and not sold_as_pack;
  if box_line is null or loose_line is null then raise exception 'FAIL 0: bill lines not set up'; end if;

  -- 1. One loose piece comes back at ₹10, not the average ₹9.62.
  r := pg_temp.ret(inv, 1, loose_line);
  if (r ->> 'total')::numeric <> 10 then raise exception 'FAIL 1a: loose piece worth %', r ->> 'total'; end if;
  if not exists (select 1 from public.sale_return_items where invoice_item_id = loose_line and line_total = 10) then
    raise exception 'FAIL 1b: the return line does not record its bill line';
  end if;
  raise notice 'PASS 1 (a loose piece at the loose price)';

  -- 2. Each line has its own limit: 12 pieces of the product are left on
  --    the bill, but only 2 of them on the loose line.
  bad := false;
  begin perform pg_temp.ret(inv, 3, loose_line);
  exception when others then bad := sqlerrm like '%left to return on it%'; end;
  if not bad then raise exception 'FAIL 2a: returned more than the line had left'; end if;
  r := pg_temp.ret(inv, 2, loose_line);
  if (r ->> 'total')::numeric <> 20 then raise exception 'FAIL 2b: last 2 loose worth %', r ->> 'total'; end if;
  raise notice 'PASS 2 (per-line limit)';

  -- 3. The whole box comes back at ₹95.
  r := pg_temp.ret(inv, 10, box_line);
  if (r ->> 'total')::numeric <> 95 then raise exception 'FAIL 3: box worth %', r ->> 'total'; end if;
  raise notice 'PASS 3 (a box at the box price)';

  -- 4. A line of another product, or of another bill, is refused.
  inv2 := (public.create_invoice(jsonb_build_object(
            'invoice_type', 'non_gst', 'customer_name', 'x', 'payment_mode', 'cash',
            'paid_amount', 20,
            'items', jsonb_build_array(jsonb_build_object(
              'product_id', '75757575-2222-0000-0000-000000000002', 'product_name', 'RBL Lighter',
              'quantity', 1, 'unit_name', 'pcs', 'unit_price', 20, 'gst_rate', 0, 'tax_amount', 0,
              'line_total', 20))))
          ->> 'id')::uuid;
  select id into lighter_line from public.invoice_items where invoice_id = inv2;
  bad := false;
  begin perform pg_temp.ret(inv2, 1, lighter_line);   -- cigarette named on the lighter's line
  exception when others then bad := sqlerrm like '%is not on this bill%'; end;
  if not bad then raise exception 'FAIL 4: a line of another product was accepted'; end if;
  raise notice 'PASS 4 (the named line must be that product on that bill)';

  -- 5. Older app versions (no line named) still work, at the average.
  inv := (public.create_invoice(jsonb_build_object(
            'invoice_type', 'non_gst', 'customer_name', 'x', 'payment_mode', 'cash',
            'paid_amount', 125,
            'items', jsonb_build_array(pg_temp.line(10, 9.5, true), pg_temp.line(3, 10, false))))
         ->> 'id')::uuid;
  r := pg_temp.ret(inv, 1, null);
  if (r ->> 'total')::numeric <> 9.62 then raise exception 'FAIL 5: older return worth %', r ->> 'total'; end if;
  raise notice 'PASS 5 (older app versions unchanged)';
end $$;

rollback;
