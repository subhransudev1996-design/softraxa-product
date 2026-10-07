-- ============================================================
-- Shop types and suggested products (migration 0066).
--
-- HOW TO RUN — on a STAGING copy, after 0066:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
-- (Test products all start with "QZX", which no real product name contains,
-- so the starter products already in the list do not disturb the checks.)
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('e8e8e8e8-0000-0000-0000-0000000000ad', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'sg-admin@test.invalid'),
  ('e8e8e8e8-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'sg-owner-a@test.invalid'),
  ('e8e8e8e8-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'sg-owner-b@test.invalid'),
  ('e8e8e8e8-0000-0000-0000-00000000000c', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'sg-noshop@test.invalid');

-- The three new kinds of shop exist: a grocery, a mobile shop.
insert into public.businesses (id, name, state_code, phone, business_type) values
  ('e8e8e8e8-1111-0000-0000-00000000000a', 'SGSHOPALPHA', '27', '9000088881', 'grocery'),
  ('e8e8e8e8-1111-0000-0000-00000000000b', 'SGSHOPBETA', '27', '9000088882', 'mobile');
update public.profiles set role = 'admin' where id = 'e8e8e8e8-0000-0000-0000-0000000000ad';
update public.profiles set business_id = 'e8e8e8e8-1111-0000-0000-00000000000a', role = 'owner'
  where id = 'e8e8e8e8-0000-0000-0000-00000000000a';
update public.profiles set business_id = 'e8e8e8e8-1111-0000-0000-00000000000b', role = 'owner'
  where id = 'e8e8e8e8-0000-0000-0000-00000000000b';

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

do $$
declare
  admin   constant uuid := 'e8e8e8e8-0000-0000-0000-0000000000ad';
  owner_a constant uuid := 'e8e8e8e8-0000-0000-0000-00000000000a';
  owner_b constant uuid := 'e8e8e8e8-0000-0000-0000-00000000000b';
  noshop  constant uuid := 'e8e8e8e8-0000-0000-0000-00000000000c';
  shop_a  constant uuid := 'e8e8e8e8-1111-0000-0000-00000000000a';
  shop_b  constant uuid := 'e8e8e8e8-1111-0000-0000-00000000000b';
  v jsonb; r jsonb; items jsonb; m public.master_products; pr public.products;
  rice uuid; dal uuid; soap uuid; phone uuid; ghee uuid; bad boolean;
begin
  -- 1. SOFTRAXA fills the list in bulk. A bad row is reported and the
  --    others still go in. The unit's short name and decimal setting are
  --    filled in from its name.
  perform pg_temp.act(admin);
  v := public.admin_import_master_products(jsonb_build_array(
    jsonb_build_object('name', 'QZX Basmati Rice 5 kg', 'brand', 'QZX Brand', 'category', 'QZX Rice',
                       'unit_name', 'Kg', 'hsn_code', '100630', 'gst_rate', 5, 'business_type', 'grocery'),
    jsonb_build_object('name', 'QZX Toor Dal 1 kg', 'category', 'QZX Pulses', 'unit_name', 'Packet',
                       'gst_rate', 5, 'business_type', 'grocery'),
    jsonb_build_object('name', 'QZX Bath Soap 100 g', 'category', 'QZX Soap', 'unit_name', 'Piece',
                       'hsn_code', '3401', 'gst_rate', 5, 'business_type', 'cosmetics'),
    jsonb_build_object('name', 'QZX Phone Model One', 'category', 'QZX Phones', 'unit_name', 'Piece',
                       'hsn_code', '85171300', 'gst_rate', 18, 'business_type', 'mobile',
                       'track_serial', true, 'warranty_months', 12),
    jsonb_build_object('name', 'QZX Bad Hsn', 'hsn_code', '12', 'business_type', 'grocery'),
    jsonb_build_object('name', 'QZX Bad Type', 'business_type', 'bakery'),
    jsonb_build_object('name', 'QZX Bad Bulk', 'secondary_unit_name', 'Case')));
  if (v ->> 'added')::int <> 4 or jsonb_array_length(v -> 'errors') <> 3
     or (v -> 'errors' -> 0 ->> 'row')::int <> 5 or v -> 'errors' -> 1 ->> 'name' <> 'QZX Bad Type' then
    raise exception 'FAIL 1a: import %', v;
  end if;
  select * into m from public.master_products where name = 'QZX Basmati Rice 5 kg';
  rice := m.id;
  if m.unit_short <> 'kg' or not m.allow_decimal or m.status <> 'published' or not m.verified
     or m.source <> 'softraxa' or m.business_type <> 'grocery' then
    raise exception 'FAIL 1b: entry %', to_jsonb(m);
  end if;
  select id into dal from public.master_products where name = 'QZX Toor Dal 1 kg';
  select id into soap from public.master_products where name = 'QZX Bath Soap 100 g';
  select id into phone from public.master_products where name = 'QZX Phone Model One';
  -- The same name again corrects the entry; a key left out keeps its value.
  v := public.admin_import_master_products(jsonb_build_array(
    jsonb_build_object('name', 'QZX Basmati Rice 5 kg', 'brand', 'QZX Brand Two')));
  select * into m from public.master_products where id = rice;
  if (v ->> 'updated')::int <> 1 or (v ->> 'added')::int <> 0 or m.brand <> 'QZX Brand Two'
     or m.gst_rate <> 5 or m.hsn_code <> '100630' then
    raise exception 'FAIL 1c: correction % %', v, to_jsonb(m);
  end if;
  raise notice 'PASS 1 (bulk import: bad rows reported, good rows added, same name corrected)';

  -- 2. A grocery shop browses: its own kind first, the kinds with counts,
  --    categories, and search across every kind.
  perform pg_temp.act(owner_a);
  v := public.browse_master_products('', '', 'qzx');
  if v ->> 'mine' <> 'grocery' or v ->> 'type' <> 'grocery' or (v ->> 'total')::int <> 2
     or jsonb_array_length(v -> 'rows') <> 2
     or v -> 'rows' -> 0 ->> 'category' <> 'QZX Pulses'      -- ordered by category, then name
     or jsonb_array_length(v -> 'categories') <> 2
     or v::text like '%price%' or v::text like '%source%' then
    raise exception 'FAIL 2a: browse %', v;
  end if;
  if not (v -> 'types') @> '[{"type": "grocery", "count": 2}, {"type": "cosmetics", "count": 1}, {"type": "mobile", "count": 1}]'::jsonb then
    raise exception 'FAIL 2b: kinds of shop %', v -> 'types';
  end if;
  v := public.browse_master_products('', 'QZX Rice', 'qzx');
  if (v ->> 'total')::int <> 1 or v -> 'rows' -> 0 ->> 'name' <> 'QZX Basmati Rice 5 kg' then
    raise exception 'FAIL 2c: category filter %', v;
  end if;
  v := public.browse_master_products('*', '', 'qzx bath');
  if (v ->> 'total')::int <> 1 or v -> 'rows' -> 0 ->> 'business_type' <> 'cosmetics' then
    raise exception 'FAIL 2d: search across kinds %', v;
  end if;
  v := public.browse_master_products('mobile', '', 'qzx');
  if (v ->> 'total')::int <> 1 then raise exception 'FAIL 2e: another kind %', v; end if;
  v := public.browse_master_products('', '', 'qzx', 1, 1);
  if jsonb_array_length(v -> 'rows') <> 1 or (v ->> 'total')::int <> 2 then
    raise exception 'FAIL 2f: paging %', v;
  end if;
  raise notice 'PASS 2 (browse: own kind, kinds and categories with counts, search, paging)';

  -- 3. Hidden products are not offered; offering them again brings them back.
  perform pg_temp.act(admin);
  perform public.admin_set_master_products_status(array[dal], 'hidden');
  perform pg_temp.act(owner_a);
  if (public.browse_master_products('', '', 'qzx') ->> 'total')::int <> 1 then
    raise exception 'FAIL 3a: a hidden product is offered';
  end if;
  perform pg_temp.act(admin);
  perform public.admin_set_master_products_status(array[dal], 'published');
  perform pg_temp.act(owner_a);
  if (public.browse_master_products('', '', 'qzx') ->> 'total')::int <> 2 then
    raise exception 'FAIL 3b: offered again, but not shown';
  end if;
  raise notice 'PASS 3 (hide and offer many at once)';

  -- 4. Adding: every product needs a selling price; nothing is added when one is missing.
  bad := false;
  begin
    perform public.add_products_from_master(jsonb_build_array(
      jsonb_build_object('master_id', rice, 'selling_price', 480),
      jsonb_build_object('master_id', dal, 'selling_price', 0)));
  exception when others then bad := sqlerrm like '%selling price%';
  end;
  if not bad then raise exception 'FAIL 4a: a product without a price was accepted'; end if;
  if exists (select 1 from public.products where business_id = shop_a) then
    raise exception 'FAIL 4b: a failed add left products behind';
  end if;

  r := public.add_products_from_master(jsonb_build_array(
    jsonb_build_object('master_id', rice, 'selling_price', 480, 'purchase_price', 430, 'mrp', 500,
                       'opening_stock', 12),
    jsonb_build_object('master_id', dal, 'selling_price', 140)));
  if (r ->> 'added')::int <> 2 or (r ->> 'skipped')::int <> 0 then
    raise exception 'FAIL 4c: result %', r;
  end if;
  select * into pr from public.products where business_id = shop_a and master_product_id = rice;
  if pr.name <> 'QZX Basmati Rice 5 kg' or pr.selling_price <> 480 or pr.purchase_price <> 430
     or pr.mrp <> 500 or pr.gst_rate <> 5 or pr.hsn_code <> '100630'
     or pr.current_stock <> 12 or pr.category_id is null or pr.brand_id is null or pr.unit_id is null
     or (select name from public.categories where id = pr.category_id) <> 'QZX Rice'
     or (select short_name from public.units where id = pr.unit_id) <> 'kg' then
    raise exception 'FAIL 4d: product %', to_jsonb(pr);
  end if;
  if not exists (select 1 from public.stock_movements
                 where product_id = pr.id and movement_type = 'opening' and quantity = 12) then
    raise exception 'FAIL 4e: no opening stock movement';
  end if;
  if (select current_stock from public.products where business_id = shop_a and master_product_id = dal) <> 0 then
    raise exception 'FAIL 4f: stock appeared from nowhere';
  end if;
  raise notice 'PASS 4 (add: price required, all-or-nothing, product + category + brand + unit + opening stock)';

  -- 5. Adding again skips what the shop has; it is no longer offered;
  --    the category is not created twice; other shops are untouched.
  r := public.add_products_from_master(jsonb_build_array(
    jsonb_build_object('master_id', rice, 'selling_price', 999)));
  if (r ->> 'added')::int <> 0 or (r ->> 'skipped')::int <> 1 then
    raise exception 'FAIL 5a: result %', r;
  end if;
  if (select selling_price from public.products where business_id = shop_a and master_product_id = rice) <> 480 then
    raise exception 'FAIL 5b: an existing product was changed';
  end if;
  if (public.browse_master_products('', '', 'qzx') ->> 'total')::int <> 0 then
    raise exception 'FAIL 5c: offered what the shop already has';
  end if;
  if (select count(*) from public.categories where business_id = shop_a and name = 'QZX Rice') <> 1 then
    raise exception 'FAIL 5d: category created twice';
  end if;
  perform pg_temp.act(owner_b);
  if (public.browse_master_products('*', '', 'qzx') ->> 'total')::int <> 4
     or exists (select 1 from public.products where business_id = shop_b) then
    raise exception 'FAIL 5e: another shop was affected';
  end if;
  raise notice 'PASS 5 (no duplicates; other shops untouched)';

  -- 6. A product the shop typed itself under the same name counts as "have".
  insert into public.products (business_id, name, selling_price) values (shop_b, 'QZX Phone Model One', 9999);
  if (public.browse_master_products('*', '', 'qzx') ->> 'total')::int <> 3 then
    raise exception 'FAIL 6a: still offered a product with the same name';
  end if;
  r := public.add_products_from_master(jsonb_build_array(
    jsonb_build_object('master_id', phone, 'selling_price', 1)));
  if (r ->> 'skipped')::int <> 1 then raise exception 'FAIL 6b: duplicate by name added'; end if;
  raise notice 'PASS 6 (same name = already there)';

  -- 7. Limits and permissions.
  items := '[]'::jsonb;
  for i in 1 .. 101 loop
    items := items || jsonb_build_array(jsonb_build_object('master_id', rice, 'selling_price', 1));
  end loop;
  bad := false;
  begin perform public.add_products_from_master(items);
  exception when others then bad := sqlerrm like '%100 products%'; end;
  if not bad then raise exception 'FAIL 7a: 101 products accepted'; end if;
  bad := false;
  begin perform public.add_products_from_master('[]'::jsonb);
  exception when others then bad := true; end;
  if not bad then raise exception 'FAIL 7b: empty list accepted'; end if;
  perform pg_temp.act(noshop);
  bad := false;
  begin perform public.browse_master_products();
  exception when others then bad := sqlerrm like '%No shop%'; end;
  if not bad then raise exception 'FAIL 7c: browsing without a shop'; end if;
  perform pg_temp.act(owner_a);
  bad := false;
  begin perform public.admin_import_master_products(jsonb_build_array(jsonb_build_object('name', 'QZX Sneaky')));
  exception when others then bad := true; end;
  if not bad then raise exception 'FAIL 7d: a shop imported into the list'; end if;
  bad := false;
  begin perform public.admin_set_master_products_status(array[rice], 'hidden');
  exception when others then bad := true; end;
  if not bad then raise exception 'FAIL 7e: a shop hid a product'; end if;
  bad := false;
  begin perform public.admin_export_master_products();
  exception when others then bad := true; end;
  if not bad then raise exception 'FAIL 7f: a shop downloaded the list'; end if;
  raise notice 'PASS 7 (up to 100 at a time; shops cannot use the admin tools)';

  -- 8. The admin page: filter by kind of shop and category, counts, paging; the export.
  perform pg_temp.act(admin);
  v := public.get_admin_master_products('qzx', '', 200, 'grocery', '', 0);
  if (v ->> 'total')::int <> 2 or jsonb_array_length(v -> 'rows') <> 2 then
    raise exception 'FAIL 8a: admin by kind %', v;
  end if;
  v := public.get_admin_master_products('qzx', '', 200, '', 'QZX Soap', 0);
  if (v ->> 'total')::int <> 1 or v -> 'rows' -> 0 ->> 'name' <> 'QZX Bath Soap 100 g' then
    raise exception 'FAIL 8b: admin by category %', v;
  end if;
  v := public.get_admin_master_products('qzx', '', 1, '', '', 1);
  if jsonb_array_length(v -> 'rows') <> 1 or (v ->> 'total')::int <> 4 then
    raise exception 'FAIL 8c: admin paging %', v;
  end if;
  if not (v -> 'types') @> '[{"type": "grocery", "count": 2}]'::jsonb then
    raise exception 'FAIL 8d: admin kinds %', v -> 'types';
  end if;
  v := public.admin_export_master_products('grocery');
  if not exists (select 1 from jsonb_array_elements(v) e where e ->> 'name' = 'QZX Basmati Rice 5 kg'
                  and e ->> 'status' = 'published' and (e ->> 'gst_rate')::numeric = 5) then
    raise exception 'FAIL 8e: export';
  end if;
  raise notice 'PASS 8 (admin list filters and export)';

  -- 9. The starter products: master_upsert leaves an existing entry alone when asked.
  reset role;
  if public.master_upsert(jsonb_build_object('name', 'QZX Basmati Rice 5 kg', 'brand', 'Changed'), false, false)
       <> 'skipped'
     or (select brand from public.master_products where id = rice) <> 'QZX Brand Two' then
    raise exception 'FAIL 9a: skip mode changed an entry';
  end if;
  if public.master_upsert(jsonb_build_object('name', 'QZX Unverified Item', 'unit_name', 'Litre'), false, false)
       <> 'added'
     or (select verified from public.master_products where name = 'QZX Unverified Item') then
    raise exception 'FAIL 9b: a starter product should not be marked verified';
  end if;
  raise notice 'PASS 9 (starter products: existing entries untouched)';
end $$;

rollback;
