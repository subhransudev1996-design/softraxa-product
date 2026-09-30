-- ============================================================
-- Master product list: shops' products feed it (without prices), other
-- shops search and use it, SOFTRAXA manages it (migration 0057).
--
-- HOW TO RUN — on a STAGING copy, after 0057:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('e7e7e7e7-0000-0000-0000-0000000000ad', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'mp-admin@test.invalid'),
  ('e7e7e7e7-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'mp-owner-a@test.invalid'),
  ('e7e7e7e7-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'mp-owner-b@test.invalid');

insert into public.businesses (id, name, state_code, phone, business_type) values
  ('e7e7e7e7-1111-0000-0000-00000000000a', 'MPSHOPALPHA', '27', '9000066666', 'mobile'),
  ('e7e7e7e7-1111-0000-0000-00000000000b', 'MPSHOPBETA', '27', '9000077777', 'mobile');
update public.profiles set role = 'admin' where id = 'e7e7e7e7-0000-0000-0000-0000000000ad';
update public.profiles set business_id = 'e7e7e7e7-1111-0000-0000-00000000000a', role = 'owner'
  where id = 'e7e7e7e7-0000-0000-0000-00000000000a';
update public.profiles set business_id = 'e7e7e7e7-1111-0000-0000-00000000000b', role = 'owner'
  where id = 'e7e7e7e7-0000-0000-0000-00000000000b';

-- Shop Alpha's own category, brand and unit. Shop Beta has none yet.
insert into public.categories (id, business_id, name) values
  ('e7e7e7e7-2222-0000-0000-00000000000a', 'e7e7e7e7-1111-0000-0000-00000000000a', 'ZZ Phones');
insert into public.brands (id, business_id, name) values
  ('e7e7e7e7-3333-0000-0000-00000000000a', 'e7e7e7e7-1111-0000-0000-00000000000a', 'ZZ Brand');
insert into public.units (id, business_id, name, short_name, allow_decimal) values
  ('e7e7e7e7-4444-0000-0000-00000000000a', 'e7e7e7e7-1111-0000-0000-00000000000a', 'Piece', 'pcs', false);

-- Start with "offer new products at once" (your real setting is restored by the rollback).
update public.platform_settings set catalog_auto_publish = true where id = 1;

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

do $$
declare
  admin   constant uuid := 'e7e7e7e7-0000-0000-0000-0000000000ad';
  owner_a constant uuid := 'e7e7e7e7-0000-0000-0000-00000000000a';
  owner_b constant uuid := 'e7e7e7e7-0000-0000-0000-00000000000b';
  shop_a  constant uuid := 'e7e7e7e7-1111-0000-0000-00000000000a';
  shop_b  constant uuid := 'e7e7e7e7-1111-0000-0000-00000000000b';
  cat_a   constant uuid := 'e7e7e7e7-2222-0000-0000-00000000000a';
  brand_a constant uuid := 'e7e7e7e7-3333-0000-0000-00000000000a';
  unit_a  constant uuid := 'e7e7e7e7-4444-0000-0000-00000000000a';
  v jsonb; u jsonb; m public.master_products;
  p1 uuid; p2 uuid; p3 uuid; p4 uuid; p5 uuid;
  phone uuid; tablet uuid; charger uuid; cable uuid; moved integer;
begin
  -- 1. A shop adds a product: it joins the list with its details and
  --    without its price, SKU or description. The shop can't read the list.
  perform pg_temp.act(owner_a);
  insert into public.products
    (business_id, name, sku, barcode, hsn_code, gst_rate, brand_id, category_id, unit_id,
     selling_price, purchase_price, mrp, description)
  values (shop_a, 'ZZTest Phone A15', 'SKUALPHA1', '9990000000017', '85171300', 18, brand_a, cat_a, unit_a,
          15999, 14321, 16999, 'secret shop note')
  returning id, master_product_id into p1, phone;
  if phone is null then raise exception 'FAIL 1a: the product did not join the list'; end if;
  if (select count(*) from public.master_products) <> 0 then
    raise exception 'FAIL 1b: a shop can read the master list table';
  end if;
  perform pg_temp.act(admin);
  select * into m from public.master_products where id = phone;
  if m.name <> 'ZZTest Phone A15' or m.brand <> 'ZZ Brand' or m.category <> 'ZZ Phones'
     or m.unit_name <> 'Piece' or m.hsn_code <> '85171300' or m.barcode <> '9990000000017'
     or m.gst_rate <> 18 or m.status <> 'published' or m.source <> 'shop'
     or m.business_type <> 'mobile' then
    raise exception 'FAIL 1c: entry %', to_jsonb(m);
  end if;
  -- (ids and timestamps are left out: their digits could match by chance)
  v := to_jsonb(m) - 'id' - 'source_business_id' - 'created_at' - 'updated_at';
  if v::text like '%15999%' or v::text like '%14321%'
     or v::text like '%16999%' or v::text like '%SKUALPHA1%'
     or v::text like '%secret shop note%'
     or exists (select 1 from information_schema.columns
                where table_schema = 'public' and table_name = 'master_products'
                  and (column_name like '%price%' or column_name like '%mrp%'
                       or column_name like '%stock%')) then
    raise exception 'FAIL 1d: a price, SKU or note reached the list';
  end if;
  raise notice 'PASS 1 (a shop''s product joins the list without prices)';

  -- 2. Another shop finds it by part of the name or by barcode, and is not
  --    told who added it. The shop that has it is not offered it again.
  perform pg_temp.act(owner_b);
  v := public.search_master_products('zztest pho');
  if jsonb_array_length(v) <> 1 or (v -> 0 ->> 'id')::uuid <> phone
     or v -> 0 ->> 'brand' <> 'ZZ Brand' or v::text like '%MPSHOPALPHA%'
     or v::text like '%source%' or v::text like '%price%' then
    raise exception 'FAIL 2a: search %', v;
  end if;
  if jsonb_array_length(public.search_master_products('9990000000017')) <> 1 then
    raise exception 'FAIL 2b: not found by barcode';
  end if;
  perform pg_temp.act(owner_a);
  if jsonb_array_length(public.search_master_products('zztest pho')) <> 0 then
    raise exception 'FAIL 2c: offered a product the shop already has';
  end if;
  raise notice 'PASS 2 (found by name or barcode; the source shop stays private)';

  -- 3. Using it creates the category, brand and unit in the shop once,
  --    and a product saved under the shop's own name keeps the link.
  perform pg_temp.act(owner_b);
  u := public.use_master_product(phone);
  u := public.use_master_product(phone);
  if (select count(*) from public.categories where business_id = shop_b and name = 'ZZ Phones') <> 1
     or (select count(*) from public.brands where business_id = shop_b and name = 'ZZ Brand') <> 1
     or (select count(*) from public.units where business_id = shop_b and name = 'Piece') <> 1
     or (u ->> 'category_id') is null or u ->> 'hsn_code' <> '85171300' or u::text like '%price%' then
    raise exception 'FAIL 3a: use %', u;
  end if;
  insert into public.products
    (business_id, name, hsn_code, gst_rate, category_id, brand_id, unit_id, selling_price, master_product_id)
  values (shop_b, 'ZZTest Phone A15 Blue Offer', u ->> 'hsn_code', 18, (u ->> 'category_id')::uuid,
          (u ->> 'brand_id')::uuid, (u ->> 'unit_id')::uuid, 15500, phone)
  returning id into p2;
  if (select master_product_id from public.products where id = p2) is distinct from phone then
    raise exception 'FAIL 3b: the picked product lost its link';
  end if;
  if jsonb_array_length(public.search_master_products('zztest pho')) <> 0 then
    raise exception 'FAIL 3c: still offered after adding it';
  end if;
  perform pg_temp.act(admin);
  if (select count(*) from public.master_products where name_key like 'zztest phone a15%') <> 1 then
    raise exception 'FAIL 3d: the shop''s own name made a second entry';
  end if;
  raise notice 'PASS 3 (picked product: category, brand and unit created once; link kept)';

  -- 4. The same product typed differently is one entry; a later shop
  --    fills the blanks the first one left.
  perform pg_temp.act(owner_b);
  insert into public.products (business_id, name, selling_price)
    values (shop_b, 'zztest  TABLET-x1', 9000) returning master_product_id into tablet;
  perform pg_temp.act(owner_a);
  insert into public.products (business_id, name, hsn_code, brand_id, unit_id, selling_price)
    values (shop_a, 'ZZTest Tablet X1', '84713010', brand_a, unit_a, 9500) returning id into p3;
  if (select master_product_id from public.products where id = p3) is distinct from tablet then
    raise exception 'FAIL 4a: the same product made two entries';
  end if;
  perform pg_temp.act(admin);
  select * into m from public.master_products where id = tablet;
  if m.hsn_code <> '84713010' or m.brand <> 'ZZ Brand' or m.unit_name <> 'Piece' then
    raise exception 'FAIL 4b: blanks not filled: %', to_jsonb(m);
  end if;
  v := public.get_admin_master_products('zztest tablet');
  if jsonb_array_length(v -> 'rows') <> 1 or (v -> 'rows' -> 0 ->> 'shops')::integer <> 2
     or v -> 'rows' -> 0 ->> 'source_shop' <> 'MPSHOPBETA' then
    raise exception 'FAIL 4c: admin list %', v -> 'rows';
  end if;
  raise notice 'PASS 4 (one entry per product; blanks filled; admin sees 2 shops)';

  -- 5. A shop corrects a typo in a product only it has: the list follows.
  perform pg_temp.act(owner_a);
  insert into public.products (business_id, name, selling_price)
    values (shop_a, 'ZZTest Earbuds Proo', 1200) returning id into p4;
  update public.products set name = 'ZZTest Earbuds Pro' where id = p4;
  perform pg_temp.act(admin);
  if not exists (select 1 from public.master_products where name_key = 'zztest earbuds pro' and status = 'published')
     or exists (select 1 from public.master_products where name_key = 'zztest earbuds proo') then
    raise exception 'FAIL 5: the typo stayed in the list';
  end if;
  raise notice 'PASS 5 (typo corrected in the list too)';

  -- 6. With approval switched on, a new product waits for SOFTRAXA.
  perform public.admin_set_catalog_auto_publish(false);
  perform pg_temp.act(owner_a);
  insert into public.products (business_id, name, selling_price)
    values (shop_a, 'ZZTest Charger 20W', 600) returning master_product_id into charger;
  perform pg_temp.act(owner_b);
  if jsonb_array_length(public.search_master_products('zztest charger')) <> 0 then
    raise exception 'FAIL 6a: an unapproved product is offered';
  end if;
  perform pg_temp.act(admin);
  if (select status from public.master_products where id = charger) <> 'pending' then
    raise exception 'FAIL 6b: not waiting for approval';
  end if;
  perform public.admin_set_master_product_status(charger, 'published');
  perform pg_temp.act(owner_b);
  if jsonb_array_length(public.search_master_products('zztest charger')) <> 1 then
    raise exception 'FAIL 6c: approved product not offered';
  end if;
  raise notice 'PASS 6 (approval mode: waits, then offered once approved)';

  -- 7. SOFTRAXA adds a product: checked, logged, offered; shops don't
  --    change a verified entry. A shop can't manage the list.
  begin
    perform public.admin_save_master_product(null, '{"name": "ZZTest Hack"}');
    raise exception 'FAIL 7a: a shop added to the master list directly';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform pg_temp.act(admin);
  begin
    perform public.admin_save_master_product(null, '{"name": "zztest  charger-20w"}');
    raise exception 'FAIL 7b: duplicate name accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    perform public.admin_save_master_product(null, '{"name": "ZZTest Cable Type C", "hsn_code": "85"}');
    raise exception 'FAIL 7c: bad HSN accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  cable := public.admin_save_master_product(null, jsonb_build_object(
    'name', 'ZZTest Cable Type C', 'brand', 'ZZ Cables', 'category', 'ZZ Accessories',
    'unit_name', 'Piece', 'unit_short', 'pcs', 'hsn_code', '85444290', 'gst_rate', 18,
    'business_type', 'mobile'));
  select * into m from public.master_products where id = cable;
  if m.status <> 'published' or not m.verified or m.source <> 'softraxa'
     or not exists (select 1 from public.audit_logs
                    where action = 'master_product.created' and entity_id = cable::text) then
    raise exception 'FAIL 7d: %', to_jsonb(m);
  end if;
  perform pg_temp.act(owner_b);
  insert into public.products (business_id, name, brand_id, selling_price)
    values (shop_b, 'zztest cable type c', (u ->> 'brand_id')::uuid, 150) returning id into p5;
  perform pg_temp.act(admin);
  if (select master_product_id from public.products where id = p5) is distinct from cable
     or (select brand from public.master_products where id = cable) <> 'ZZ Cables' then
    raise exception 'FAIL 7e: a shop changed a verified entry';
  end if;
  raise notice 'PASS 7 (SOFTRAXA''s entries are checked, logged and not changed by shops)';

  -- 8. Hidden products are not offered, and adding the same name again
  --    does not bring them back.
  perform public.admin_set_master_product_status(charger, 'hidden');
  perform pg_temp.act(owner_b);
  if jsonb_array_length(public.search_master_products('zztest charger')) <> 0 then
    raise exception 'FAIL 8a: a hidden product is offered';
  end if;
  insert into public.products (business_id, name, selling_price)
    values (shop_b, 'ZZTest Charger 20W', 650);
  perform pg_temp.act(admin);
  if (select status from public.master_products where id = charger) <> 'hidden' then
    raise exception 'FAIL 8b: a hidden product came back';
  end if;
  raise notice 'PASS 8 (hidden stays hidden)';

  -- 9. Merge two entries: every shop's product moves, one entry remains.
  moved := public.admin_merge_master_products(tablet, phone);
  if moved <> 2 or exists (select 1 from public.master_products where id = tablet)
     or (select master_product_id from public.products where id = p3) is distinct from phone
     or not exists (select 1 from public.audit_logs where action = 'master_product.merged'
                    and entity_id = phone::text) then
    raise exception 'FAIL 9: merge moved %', moved;
  end if;
  raise notice 'PASS 9 (merge moves the shops'' products and is logged)';

  -- 10. System health knows 0057.
  v := public.get_system_health();
  if not (v -> 'migrations' ->> '0057')::boolean then raise exception 'FAIL 10: %', v; end if;
  raise notice 'PASS 10 (health: 0057 applied)';
end $$;

reset role;
do $$ begin raise notice 'ALL MASTER PRODUCT CHECKS PASSED — rolling back test data'; end $$;
rollback;
