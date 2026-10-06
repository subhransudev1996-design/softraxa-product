-- ============================================================
-- Cut pieces without the paperwork (migration 0064): new stock becomes
-- pieces by itself, bills cut the best piece on their own, one tap puts
-- pieces back in step with stock.
--
-- HOW TO RUN — on a STAGING copy, after 0064:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('64646464-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'cut-owner@test.invalid'),
  ('64646464-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'cut-staff@test.invalid');

insert into public.businesses (id, name, state_code) values
  ('64646464-1111-0000-0000-000000000001', 'Rod House', '27');
update public.profiles set business_id = '64646464-1111-0000-0000-000000000001', role = 'owner'
  where id = '64646464-0000-0000-0000-000000000001';
update public.profiles set business_id = '64646464-1111-0000-0000-000000000001', role = 'staff'
  where id = '64646464-0000-0000-0000-000000000002';
insert into public.plans (id, name, software_id, user_limit, included_features)
select '64646464-9999-0000-0000-000000000001', 'Cut Two Users', id, 2, '[]'
from public.software_products where slug = 'dukania';
insert into public.subscriptions (business_id, plan_id, status, expiry_date) values
  ('64646464-1111-0000-0000-000000000001', '64646464-9999-0000-0000-000000000001',
   'active', current_date + 30);

-- Rod: 12 ft full length, no cutting loss, leftovers under 1 ft are scrap.
-- Wire: no full length (a coil is whatever arrived).
insert into public.products (id, business_id, name, selling_price, purchase_price, gst_rate,
  track_pieces, piece_length, min_remnant_length) values
  ('64646464-2222-0000-0000-000000000001', '64646464-1111-0000-0000-000000000001',
   'Cut Rod', 50, 40, 0, true, 12, 1),
  ('64646464-2222-0000-0000-000000000002', '64646464-1111-0000-0000-000000000001',
   'Cut Wire', 20, 15, 0, true, 0, 0);
insert into public.stock_movements (business_id, product_id, movement_type, quantity, note) values
  ('64646464-1111-0000-0000-000000000001', '64646464-2222-0000-0000-000000000001', 'opening', 30, 'test'),
  ('64646464-1111-0000-0000-000000000001', '64646464-2222-0000-0000-000000000002', 'opening', 50, 'test');

-- Available piece lengths of a product, longest first: '12,12,6'.
create or replace function pg_temp.pieces(p uuid) returns text language sql as $$
  select coalesce(string_agg(trim(trailing '.' from trim(trailing '0' from length::text)), ','
                  order by length desc), '')
  from public.stock_pieces where product_id = p and status = 'available';
$$;

-- A cash bill of p_qty of a product at its price — no piece chosen.
create or replace function pg_temp.bill(p uuid, p_qty numeric, p_price numeric)
returns jsonb language sql as $$
  select jsonb_build_object(
    'invoice_type', 'non_gst', 'customer_name', '', 'payment_mode', 'cash',
    'paid_amount', p_qty * p_price,
    'items', jsonb_build_array(jsonb_build_object(
      'product_id', p, 'product_name', 'x', 'quantity', p_qty, 'unit_name', 'ft',
      'unit_price', p_price, 'gst_rate', 0, 'tax_amount', 0, 'line_total', p_qty * p_price)));
$$;

create or replace function pg_temp.pur(p_qty numeric) returns jsonb language sql as $$
  select jsonb_build_object(
    'supplier_id', null, 'supplier_name', '', 'purchase_date', current_date,
    'paid_amount', p_qty * 40, 'payment_mode', 'cash', 'bill_no', 'R-1',
    'items', jsonb_build_array(jsonb_build_object(
      'product_id', '64646464-2222-0000-0000-000000000001', 'product_name', 'Cut Rod',
      'quantity', p_qty, 'unit_price', 40, 'gst_rate', 0, 'tax_amount', 0,
      'line_total', p_qty * 40)));
$$;

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

do $$
declare
  owner constant uuid := '64646464-0000-0000-0000-000000000001';
  staff constant uuid := '64646464-0000-0000-0000-000000000002';
  rod   constant uuid := '64646464-2222-0000-0000-000000000001';
  wire  constant uuid := '64646464-2222-0000-0000-000000000002';
  v jsonb; p1 uuid; n numeric;
begin
  perform pg_temp.act(owner);

  -- 1. Opening stock became pieces: 30 ft of 12 ft rods = 12 + 12 + 6;
  --    a wire coil with no full length is one piece.
  if pg_temp.pieces(rod) <> '12,12,6' or pg_temp.pieces(wire) <> '50' then
    raise exception 'FAIL 1: rod % wire %', pg_temp.pieces(rod), pg_temp.pieces(wire);
  end if;
  raise notice 'PASS 1 (opening stock split into full rods + the odd piece)';

  -- 2. Bill 7 ft, no piece chosen: cut from a 12 (the 6 is too short),
  --    the 5 ft leftover is kept.
  v := public.create_invoice(pg_temp.bill(rod, 7, 50));
  if pg_temp.pieces(rod) <> '12,6,5'
     or (select current_stock from public.products where id = rod) <> 23
     or (select count(*) from public.piece_cuts where invoice_id = (v ->> 'id')::uuid) <> 1 then
    raise exception 'FAIL 2: pieces %', pg_temp.pieces(rod);
  end if;
  raise notice 'PASS 2 (7 ft cut from a 12 ft rod by itself; 5 ft kept)';

  -- 3. Bill 20 ft — longer than any piece: whole 12, whole 6, then 2 ft
  --    cut from the 5 (3 ft left). Pieces still match stock.
  v := public.create_invoice(pg_temp.bill(rod, 20, 50));
  if pg_temp.pieces(rod) <> '3'
     or (select current_stock from public.products where id = rod) <> 3
     or (select count(*) from public.piece_cuts where invoice_id = (v ->> 'id')::uuid) <> 3 then
    raise exception 'FAIL 3: pieces % stock %', pg_temp.pieces(rod),
      (select current_stock from public.products where id = rod);
  end if;
  raise notice 'PASS 3 (20 ft = 12 + 6 whole + 2 cut from the 5)';

  -- 4. A purchase of 24 ft adds two full rods.
  p1 := (public.create_purchase(pg_temp.pur(24)) ->> 'id')::uuid;
  if pg_temp.pieces(rod) <> '12,12,3' then
    raise exception 'FAIL 4: pieces %', pg_temp.pieces(rod);
  end if;
  raise notice 'PASS 4 (purchase → full rods)';

  -- 5. Purchase corrected 24 → 36: only the extra 12 ft becomes a piece.
  perform public.update_purchase(p1, pg_temp.pur(36));
  if pg_temp.pieces(rod) <> '12,12,12,3'
     or (select current_stock from public.products where id = rod) <> 39 then
    raise exception 'FAIL 5: pieces % (doubled?)', pg_temp.pieces(rod);
  end if;
  raise notice 'PASS 5 (edited purchase adds only the difference)';

  -- 6. Stock added by hand becomes a piece too.
  perform public.adjust_stock(rod, null, 5, 'adjustment', 'found in godown');
  if pg_temp.pieces(rod) <> '12,12,12,5,3' then
    raise exception 'FAIL 6: pieces %', pg_temp.pieces(rod);
  end if;
  raise notice 'PASS 6 (hand-added stock → a piece)';

  -- 7. Damaged stock written off without a piece: one tap takes the
  --    missing 4 ft off the smallest bits (the 3, then 1 ft of the 5).
  perform public.adjust_stock(rod, null, -4, 'damage', 'bent');
  n := public.match_pieces_to_stock(rod);
  if n <> -4 or pg_temp.pieces(rod) <> '12,12,12,4' then
    raise exception 'FAIL 7: change % pieces %', n, pg_temp.pieces(rod);
  end if;
  -- Already in step: nothing to do.
  if public.match_pieces_to_stock(rod) <> 0 then raise exception 'FAIL 7b'; end if;
  raise notice 'PASS 7 (match to stock trims the smallest pieces)';

  -- 8. Staff without stock permission can't do it.
  perform pg_temp.act(staff);
  begin
    perform public.match_pieces_to_stock(rod);
    raise exception 'FAIL 8: staff matched pieces';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  raise notice 'PASS 8 (match needs stock permission)';

  -- 9. Staff can still bill: 30 m of the 50 m coil leaves a 20 m piece.
  perform public.create_invoice(pg_temp.bill(wire, 30, 20));
  if pg_temp.pieces(wire) <> '20' then
    raise exception 'FAIL 9: wire pieces %', pg_temp.pieces(wire);
  end if;
  raise notice 'PASS 9 (coil cut by itself on a staff bill)';
end $$;

reset role;
do $$ begin raise notice 'ALL SIMPLE CUT PIECE CHECKS PASSED — rolling back test data'; end $$;
rollback;
