-- ============================================================
-- Sell loose or by the pack, each at its own price (migrations 0061, 0062).
--
-- HOW TO RUN — on a STAGING copy, after 0062:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
--
-- Example: cigarettes, 1 Box = 10 pcs. One piece ₹10, a whole box ₹95
-- (not ₹100). A staff member WITHOUT price permission bills both ways.
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('61616161-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'pack-owner@test.invalid'),
  ('61616161-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'pack-staff@test.invalid');

insert into public.businesses (id, name, state_code) values
  ('61616161-1111-0000-0000-000000000001', 'Pack Pan Shop', '27');
update public.profiles set business_id = '61616161-1111-0000-0000-000000000001', role = 'owner'
  where id = '61616161-0000-0000-0000-000000000001';
update public.profiles set business_id = '61616161-1111-0000-0000-000000000001', role = 'staff'
  where id = '61616161-0000-0000-0000-000000000002';
-- A 2-user plan, so the staff login counts (user limit, 0058).
insert into public.plans (id, name, software_id, user_limit, included_features)
select '61616161-9999-0000-0000-000000000001', 'Pack Two Users', id, 2, '[]'
from public.software_products where slug = 'dukania';
insert into public.subscriptions (business_id, plan_id, status, expiry_date) values
  ('61616161-1111-0000-0000-000000000001', '61616161-9999-0000-0000-000000000001',
   'active', current_date + 30);

insert into public.products
  (id, business_id, name, selling_price, purchase_price, gst_rate,
   secondary_unit_name, conversion_factor, pack_price) values
  ('61616161-2222-0000-0000-000000000001', '61616161-1111-0000-0000-000000000001',
   'Pack Cigarette', 10, 8, 0, 'Box', 10, 95),
  ('61616161-2222-0000-0000-000000000002', '61616161-1111-0000-0000-000000000001',
   'Pack Eggs', 7, 5.5, 0, 'Tray', 30, 190);
insert into public.stock_movements (business_id, product_id, movement_type, quantity, note) values
  ('61616161-1111-0000-0000-000000000001', '61616161-2222-0000-0000-000000000001', 'opening', 100, 'test'),
  ('61616161-1111-0000-0000-000000000001', '61616161-2222-0000-0000-000000000002', 'opening', 90, 'test');

-- One line: qty in pieces, rate per piece, "pack" when sold as whole boxes.
create or replace function pg_temp.line(p_qty numeric, p_rate numeric, p_pack boolean)
returns jsonb language sql as $$
  select jsonb_build_object(
    'product_id', '61616161-2222-0000-0000-000000000001', 'product_name', 'Pack Cigarette',
    'quantity', p_qty, 'unit_name', 'pcs', 'unit_price', p_rate, 'gst_rate', 0, 'tax_amount', 0,
    'line_total', round(p_qty * p_rate, 2), 'pack', p_pack);
$$;

create or replace function pg_temp.bill(p_items jsonb) returns jsonb language sql as $$
  select jsonb_build_object(
    'invoice_type', 'non_gst', 'customer_name', 'x', 'payment_mode', 'cash',
    'paid_amount', (select sum((x ->> 'line_total')::numeric) from jsonb_array_elements(p_items) x),
    'items', p_items);
$$;

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

do $$
declare
  staff constant uuid := '61616161-0000-0000-0000-000000000002';
  cig   constant uuid := '61616161-2222-0000-0000-000000000001';
  inv uuid; r record; stock numeric;
begin
  perform pg_temp.act(staff);

  -- 1. Staff bills 1 box (₹95) + 3 loose pieces (₹30): accepted, nothing
  --    counted as a discount, stock down by 13 pieces.
  inv := (public.create_invoice(pg_temp.bill(jsonb_build_array(
            pg_temp.line(10, 9.5, true), pg_temp.line(3, 10, false)))) ->> 'id')::uuid;
  select * into r from public.invoices where id = inv;
  if r.total <> 125 or r.price_reduction <> 0 then
    raise exception 'FAIL 1: total % reduction %', r.total, r.price_reduction;
  end if;
  if (select count(*) from public.invoice_items where invoice_id = inv and sold_as_pack
        and quantity = 10 and list_price = 9.5 and price_source = 'retail' and alt_unit_name = 'Box') <> 1
     or (select count(*) from public.invoice_items where invoice_id = inv and not sold_as_pack
        and quantity = 3 and list_price = 10) <> 1 then
    raise exception 'FAIL 1b: pack / loose lines not marked as expected';
  end if;
  select current_stock into stock from public.products where id = cig;
  if stock <> 87 then raise exception 'FAIL 1c: stock % instead of 87', stock; end if;
  raise notice 'PASS 1 (1 box at ₹95 + 3 pieces at ₹10, stock 100 → 87)';

  -- 2. 10 loose pieces at the box rate is still a discount: refused for
  --    staff without price permission.
  begin
    perform public.create_invoice(pg_temp.bill(jsonb_build_array(pg_temp.line(10, 9.5, false))));
    raise exception 'FAIL 2: loose pieces accepted at the box rate';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 2 (loose pieces still need the piece price)';

  -- 3. A pack line must be whole boxes.
  begin
    perform public.create_invoice(pg_temp.bill(jsonb_build_array(pg_temp.line(15, 9.5, true))));
    raise exception 'FAIL 3: 1½ boxes accepted as a pack line';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 3 (half boxes refused)';

  -- 4. Editing the bill to 2 boxes keeps the box price.
  perform pg_temp.act('61616161-0000-0000-0000-000000000001');  -- owner edits
  perform public.update_invoice(inv, pg_temp.bill(jsonb_build_array(
            pg_temp.line(20, 9.5, true), pg_temp.line(3, 10, false))));
  select * into r from public.invoices where id = inv;
  if r.total <> 220 or r.price_reduction <> 0
     or (select count(*) from public.invoice_items where invoice_id = inv and sold_as_pack and quantity = 20) <> 1 then
    raise exception 'FAIL 4: total % reduction % after editing to 2 boxes', r.total, r.price_reduction;
  end if;
  select current_stock into stock from public.products where id = cig;
  if stock <> 77 then raise exception 'FAIL 4b: stock % instead of 77', stock; end if;
  raise notice 'PASS 4 (edited to 2 boxes: ₹190 + ₹30, stock 77)';

  -- 5. A tray of 30 eggs at ₹190 (₹6.3333 an egg, 0062) bills exactly ₹190:
  --    no 10-paise round-off, rate kept to 4 decimals.
  perform pg_temp.act(staff);
  inv := (public.create_invoice(jsonb_build_object(
    'invoice_type', 'non_gst', 'customer_name', 'x', 'payment_mode', 'cash', 'paid_amount', 190,
    'items', jsonb_build_array(jsonb_build_object(
      'product_id', '61616161-2222-0000-0000-000000000002', 'product_name', 'Pack Eggs',
      'quantity', 30, 'unit_name', 'pcs', 'unit_price', 6.3333, 'gst_rate', 0, 'tax_amount', 0,
      'line_total', 190, 'pack', true)))) ->> 'id')::uuid;
  select * into r from public.invoices where id = inv;
  if r.total <> 190 or r.subtotal <> 190 or r.round_off <> 0 or r.price_reduction <> 0
     or (select unit_price from public.invoice_items where invoice_id = inv and sold_as_pack) <> 6.3333 then
    raise exception 'FAIL 5: total % subtotal % round off % reduction %',
      r.total, r.subtotal, r.round_off, r.price_reduction;
  end if;
  raise notice 'PASS 5 (tray of 30 at ₹190: exactly ₹190)';
end $$;

rollback;
select set_config('request.jwt.claims', '', false);
