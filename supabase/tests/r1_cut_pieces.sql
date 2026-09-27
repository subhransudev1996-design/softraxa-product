-- ============================================================
-- R1 cut pieces (migration 0049).
--
-- HOW TO RUN — on a STAGING copy, after 0049:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
--
-- Spec example (D20, D21): a 4 m cut from a 5 m piece with 0.01 m
-- cutting loss leaves 0.99 m. With a 1 m minimum it is suggested as
-- scrap; with 0.5 m it is kept as a reusable piece. The 5 m piece is
-- preferred over a 12 m one; two 3 m pieces never make a 4 m cut.
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('efefefef-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'r1-cut-owner@test.invalid'),
  ('efefefef-0000-0000-0000-00000000000c', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'r1-cut-cashier@test.invalid');

insert into public.businesses (id, name, state_code) values
  ('efefefef-1111-0000-0000-00000000000a', 'R1 Wire House', '27');
update public.profiles set business_id = 'efefefef-1111-0000-0000-00000000000a', role = 'owner'
  where id = 'efefefef-0000-0000-0000-00000000000a';
-- Cashier: default staff rights (can bill, no stock permission).
update public.profiles set business_id = 'efefefef-1111-0000-0000-00000000000a', role = 'staff'
  where id = 'efefefef-0000-0000-0000-00000000000c';
insert into public.subscriptions (business_id, status, expiry_date) values
  ('efefefef-1111-0000-0000-00000000000a', 'active', current_date + 30);

-- Wire at 100/m, 0.01 m cutting allowance, 1 m minimum offcut.
insert into public.products (id, business_id, name, selling_price, purchase_price, gst_rate,
  track_pieces, cutting_allowance, min_remnant_length) values
  ('efefefef-2222-0000-0000-00000000000a', 'efefefef-1111-0000-0000-00000000000a',
   'R1 Wire', 100, 60, 0, true, 0.01, 1);
insert into public.stock_movements (business_id, product_id, movement_type, quantity, note) values
  ('efefefef-1111-0000-0000-00000000000a', 'efefefef-2222-0000-0000-00000000000a', 'opening', 26, 'r1 test');
-- 12 m + 5 m + 3 m + 3 m + 3 m = 26 m.
insert into public.stock_pieces (id, business_id, product_id, label, length) values
  ('efefefef-4444-0000-0000-000000000012', 'efefefef-1111-0000-0000-00000000000a', 'efefefef-2222-0000-0000-00000000000a', 'Coil A', 12),
  ('efefefef-4444-0000-0000-000000000005', 'efefefef-1111-0000-0000-00000000000a', 'efefefef-2222-0000-0000-00000000000a', 'Coil B', 5),
  ('efefefef-4444-0000-0000-000000000031', 'efefefef-1111-0000-0000-00000000000a', 'efefefef-2222-0000-0000-00000000000a', 'Bit 1', 3),
  ('efefefef-4444-0000-0000-000000000032', 'efefefef-1111-0000-0000-00000000000a', 'efefefef-2222-0000-0000-00000000000a', 'Bit 2', 3),
  ('efefefef-4444-0000-0000-000000000033', 'efefefef-1111-0000-0000-00000000000a', 'efefefef-2222-0000-0000-00000000000a', 'Bit 3', 3);

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

-- Cash bill for p_len metres of wire cut from p_piece, plus extra fields.
create or replace function pg_temp.bill(p_piece uuid, p_len numeric, p_extra jsonb default '{}')
returns jsonb language sql as $$
  select jsonb_build_object(
    'invoice_type', 'non_gst', 'customer_name', 'x', 'paid_amount', p_len * 100,
    'payment_mode', 'cash',
    'items', jsonb_build_array(jsonb_build_object(
      'product_id', 'efefefef-2222-0000-0000-00000000000a', 'product_name', 'R1 Wire',
      'quantity', p_len, 'unit_price', 100, 'gst_rate', 0, 'tax_amount', 0,
      'line_total', p_len * 100, 'piece_id', p_piece) || p_extra));
$$;

set local role authenticated;

do $$
declare
  owner    constant uuid := 'efefefef-0000-0000-0000-00000000000a';
  cashier  constant uuid := 'efefefef-0000-0000-0000-00000000000c';
  wire     constant uuid := 'efefefef-2222-0000-0000-00000000000a';
  coil12   constant uuid := 'efefefef-4444-0000-0000-000000000012';
  coil5    constant uuid := 'efefefef-4444-0000-0000-000000000005';
  bit1     constant uuid := 'efefefef-4444-0000-0000-000000000031';
  bit2     constant uuid := 'efefefef-4444-0000-0000-000000000032';
  bit3     constant uuid := 'efefefef-4444-0000-0000-000000000033';
  v jsonb; c record; n numeric; inv uuid; rem uuid; local uuid := gen_random_uuid();
begin
  perform pg_temp.act(cashier);

  -- 1. Suggestion: 5 m before 12 m; 3 m pieces don't fit a 4 m cut.
  v := public.suggest_pieces(wire, null, 4);
  if jsonb_array_length(v) <> 2 or (v -> 0 ->> 'id')::uuid <> coil5
     or (v -> 0 ->> 'leftover')::numeric <> 0.99 or v -> 0 ->> 'remnant' <> 'scrap' then
    raise exception 'FAIL 1: %', v;
  end if;
  raise notice 'PASS 1 (4 m cut: 5 m piece first, leaves 0.99 m → suggested scrap; 3 m pieces excluded)';

  -- 2. An exact fit needs the allowance too: 3 m can't give 3 m.
  if jsonb_array_length(public.suggest_pieces(wire, null, 3)) <> 2
     or exists (select 1 from jsonb_array_elements(public.suggest_pieces(wire, null, 3)) e
                where (e ->> 'id')::uuid in (bit1, bit2, bit3)) then
    raise exception 'FAIL 2: 3 m pieces offered for a 3 m cut with 0.01 m allowance';
  end if;
  raise notice 'PASS 2 (exact fit needs the cutting allowance)';

  -- 3. Two short pieces never make one cut.
  begin
    perform public.create_invoice(pg_temp.bill(bit1, 4));
    raise exception 'FAIL 3: cut 4 m from a 3 m piece';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 3 (too short refused): %', sqlerrm;
  end;

  -- 4. Cashier can't override the scrap suggestion.
  begin
    perform public.create_invoice(pg_temp.bill(coil5, 4,
      jsonb_build_object('keep_remnant', true, 'remnant_reason', 'looks fine')));
    raise exception 'FAIL 4: cashier kept an offcut below the minimum';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 4 (override needs stock permission): %', sqlerrm;
  end;

  -- 5. Sale: 4 m from the 5 m coil (+ a cutting-charge line). Loss 0.01,
  --    offcut 0.99 scrapped. Stock 26 → 21.
  v := public.create_invoice(pg_temp.bill(coil5, 4) || jsonb_build_object(
    'paid_amount', 420,
    'items', pg_temp.bill(coil5, 4) -> 'items' || jsonb_build_array(jsonb_build_object(
      'product_id', null, 'product_name', 'Cutting charge', 'quantity', 1, 'unit_price', 20,
      'gst_rate', 0, 'tax_amount', 0, 'line_total', 20))));
  inv := (v ->> 'id')::uuid;
  select * into c from public.piece_cuts where invoice_id = inv;
  select current_stock into n from public.products where id = wire;
  if c.cut_length <> 4 or c.loss_length <> 0.01 or c.remnant_length <> 0.99
     or c.remnant_status <> 'scrap' or n <> 21
     or (select status from public.stock_pieces where id = coil5) <> 'consumed'
     or (select status from public.stock_pieces where parent_piece_id = coil5) <> 'scrap'
     or (select total from public.invoices where id = inv) <> 420 then
    raise exception 'FAIL 5: cut % stock % total %', row_to_json(c), n,
      (select total from public.invoices where id = inv);
  end if;
  raise notice 'PASS 5 (billed 4 m + cutting charge = 420; 0.01 loss, 0.99 scrap; stock 26 → 21)';

  -- 6. The same piece can't be cut twice.
  begin
    perform public.create_invoice(pg_temp.bill(coil5, 1));
    raise exception 'FAIL 6: used piece cut again';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 6 (a used piece can''t be cut again)';

  -- 7. Minimum 0.5 m: a 0.99 m leftover is kept as a reusable piece.
  perform pg_temp.act(owner);
  update public.products set min_remnant_length = 0.5 where id = wire;
  perform pg_temp.act(cashier);
  v := public.create_invoice(pg_temp.bill(coil12, 11) || jsonb_build_object('local_id', local));
  select * into c from public.piece_cuts where invoice_id = (v ->> 'id')::uuid;
  rem := c.remnant_piece_id;
  if c.remnant_status <> 'reusable' or c.remnant_length <> 0.99
     or (select status from public.stock_pieces where id = rem) <> 'available'
     or (select parent_piece_id from public.stock_pieces where id = rem) <> coil12 then
    raise exception 'FAIL 7: %', row_to_json(c);
  end if;
  raise notice 'PASS 7 (12 m → 11 m sold, 0.99 m kept as its own piece, linked to its source)';

  -- 8. Re-sending the same bill (offline retry) doesn't cut again.
  v := public.create_invoice(pg_temp.bill(coil12, 11) || jsonb_build_object('local_id', local));
  if not coalesce((v ->> 'already_synced')::boolean, false)
     or (select count(*) from public.piece_cuts where source_piece_id = coil12) <> 1 then
    raise exception 'FAIL 8: retry cut again';
  end if;
  raise notice 'PASS 8 (retry-safe)';

  -- 9. The kept offcut can be sold later: 0.5 m from the 0.99 m piece.
  perform public.create_invoice(pg_temp.bill(rem, 0.5));
  if (select status from public.stock_pieces where id = rem) <> 'consumed' then
    raise exception 'FAIL 9: offcut not used';
  end if;
  raise notice 'PASS 9 (a kept offcut sells like any piece)';

  -- 10. Offline bill whose piece was already used: the sale still syncs.
  v := public.create_invoice(pg_temp.bill(coil5, 1) || jsonb_build_object('offline_created', true));
  if v ->> 'id' is null or exists (select 1 from public.piece_cuts where invoice_id = (v ->> 'id')::uuid) then
    raise exception 'FAIL 10: offline bill failed or cut a used piece';
  end if;
  raise notice 'PASS 10 (offline bill kept; unavailable piece skipped)';

  -- 11. Reclassify: owner with a reason; stock goes back up. Cashier can't.
  begin
    perform public.reclassify_piece(
      (select id from public.stock_pieces where parent_piece_id = coil5), 'available', 'usable');
    raise exception 'FAIL 11a: cashier reclassified a piece';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform pg_temp.act(owner);
  select current_stock into n from public.products where id = wire;
  perform public.reclassify_piece(
    (select id from public.stock_pieces where parent_piece_id = coil5), 'available', 'fits a short run');
  if (select current_stock from public.products where id = wire) <> n + 0.99 then
    raise exception 'FAIL 11b: stock not restored';
  end if;
  raise notice 'PASS 11 (scrap → reusable by the owner with a reason; stock +0.99)';

  -- 12. Owner may keep a below-minimum offcut with a reason.
  update public.products set min_remnant_length = 2 where id = wire;
  v := public.create_invoice(pg_temp.bill(bit1, 1.5,
    jsonb_build_object('keep_remnant', true, 'remnant_reason', 'customer will come back')));
  select * into c from public.piece_cuts where invoice_id = (v ->> 'id')::uuid;
  if c.suggested_status <> 'scrap' or c.remnant_status <> 'reusable' then
    raise exception 'FAIL 12: %', row_to_json(c);
  end if;
  raise notice 'PASS 12 (owner kept a 1.49 m offcut below the 2 m minimum, reason recorded)';

  -- 13. Cut pieces can't be returned unless the owner allows it; then the
  --     returned length comes back as its own piece.
  begin
    perform public.create_sale_return(jsonb_build_object('invoice_id', inv, 'refund_amount', 100,
      'refund_mode', 'cash', 'items', jsonb_build_array(jsonb_build_object(
        'product_id', wire, 'product_name', 'R1 Wire', 'quantity', 1))));
    raise exception 'FAIL 13a: cut piece returned';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  update public.products set allow_piece_returns = true where id = wire;
  perform public.create_sale_return(jsonb_build_object('invoice_id', inv, 'refund_amount', 100,
    'refund_mode', 'cash', 'items', jsonb_build_array(jsonb_build_object(
      'product_id', wire, 'product_name', 'R1 Wire', 'quantity', 1))));
  if not exists (select 1 from public.stock_pieces
                 where product_id = wire and source = 'return' and length = 1 and status = 'available') then
    raise exception 'FAIL 13b: returned length not tracked as a piece';
  end if;
  raise notice 'PASS 13 (returns only when allowed; 1 m returned piece tracked)';
end $$;

reset role;
do $$ begin raise notice 'ALL R1 CUT PIECE CHECKS PASSED — rolling back test data'; end $$;
rollback;
