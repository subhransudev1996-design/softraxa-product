-- ============================================================
-- Alternative products (migration 0074).
--
-- HOW TO RUN — on a STAGING copy, after 0074:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('eaeaeaea-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'alt-owner-a@test.invalid'),
  ('eaeaeaea-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'alt-owner-b@test.invalid');
insert into public.businesses (id, name, state_code, phone, business_type) values
  ('eaeaeaea-1111-0000-0000-00000000000a', 'ALTSHOPALPHA', '27', '9000066661', 'mobile'),
  ('eaeaeaea-1111-0000-0000-00000000000b', 'ALTSHOPBETA', '27', '9000066662', 'mobile');
update public.profiles set business_id = 'eaeaeaea-1111-0000-0000-00000000000a', role = 'owner'
  where id = 'eaeaeaea-0000-0000-0000-00000000000a';
update public.profiles set business_id = 'eaeaeaea-1111-0000-0000-00000000000b', role = 'owner'
  where id = 'eaeaeaea-0000-0000-0000-00000000000b';

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

do $$
declare
  owner_a constant uuid := 'eaeaeaea-0000-0000-0000-00000000000a';
  owner_b constant uuid := 'eaeaeaea-0000-0000-0000-00000000000b';
  shop_a  constant uuid := 'eaeaeaea-1111-0000-0000-00000000000a';
  shop_b  constant uuid := 'eaeaeaea-1111-0000-0000-00000000000b';
  chargers uuid; covers uuid;
  a uuid; b uuid; c uuid; d uuid; e uuid; f uuid; g uuid; h uuid; x uuid;
  v jsonb; bad boolean; n integer;
begin
  perform pg_temp.act(owner_a);
  insert into public.categories (business_id, name) values (shop_a, 'ALT Chargers') returning id into chargers;
  insert into public.categories (business_id, name) values (shop_a, 'ALT Covers') returning id into covers;
  -- a: the product sold. b, c: the shop's own picks (c out of stock).
  -- d, e: same category, in stock (d shares more name words). f: same
  -- category, out of stock. g: inactive. h: another category.
  insert into public.products (business_id, name, selling_price, category_id) values
    (shop_a, 'ALT Samsung 25W Fast Charger', 1200, chargers) returning id into a;
  insert into public.products (business_id, name, selling_price, category_id) values
    (shop_a, 'ALT Boat Charger', 600, covers) returning id into b;
  insert into public.products (business_id, name, selling_price, category_id) values
    (shop_a, 'ALT Mi Charger', 500, chargers) returning id into c;
  insert into public.products (business_id, name, selling_price, category_id) values
    (shop_a, 'ALT Generic 25W Fast Charger', 450, chargers) returning id into d;
  insert into public.products (business_id, name, selling_price, category_id) values
    (shop_a, 'ALT Realme Charger', 700, chargers) returning id into e;
  insert into public.products (business_id, name, selling_price, category_id) values
    (shop_a, 'ALT Oppo 25W Fast Charger', 800, chargers) returning id into f;
  insert into public.products (business_id, name, selling_price, category_id, is_active) values
    (shop_a, 'ALT Old 25W Fast Charger', 300, chargers, false) returning id into g;
  insert into public.products (business_id, name, selling_price, category_id) values
    (shop_a, 'ALT 25W Charger Cover', 100, covers) returning id into h;
  perform public.add_opening_stock(a, null, 5);
  perform public.add_opening_stock(b, null, 3);
  perform public.add_opening_stock(d, null, 4);
  perform public.add_opening_stock(e, null, 2);
  perform public.add_opening_stock(g, null, 9);
  perform public.add_opening_stock(h, null, 9);

  -- 1. The shop links b and c (and a itself, which is dropped).
  n := public.set_product_alternatives(a, array[b, c, a, b]);
  if n <> 2 then raise exception 'FAIL 1a: % links saved, expected 2', n; end if;
  v := public.get_linked_alternatives(a);
  if jsonb_array_length(v) <> 2 or v -> 0 ->> 'name' <> 'ALT Boat Charger' then
    raise exception 'FAIL 1b: linked %', v;
  end if;
  if not exists (select 1 from jsonb_array_elements(public.get_linked_alternatives(b)) el
                 where (el ->> 'id')::uuid = a) then
    raise exception 'FAIL 1c: a link must work both ways';
  end if;
  raise notice 'PASS 1 (links saved once, both ways, not to itself)';

  -- 2. Offered: own picks first (in stock before out of stock), then same
  --    category in stock by words in common; never out of stock, inactive,
  --    another category or itself.
  v := public.get_product_alternatives(a, 8);
  if jsonb_array_length(v) <> 4
     or (v -> 0 ->> 'id')::uuid <> b or (v -> 0 ->> 'picked')::boolean is not true
     or (v -> 1 ->> 'id')::uuid <> c or (v -> 1 ->> 'picked')::boolean is not true
     or (v -> 2 ->> 'id')::uuid <> d or (v -> 2 ->> 'picked')::boolean
     or (v -> 3 ->> 'id')::uuid <> e then
    raise exception 'FAIL 2a: offered %', v;
  end if;
  if exists (select 1 from jsonb_array_elements(v) el where (el ->> 'id')::uuid in (a, f, g, h)) then
    raise exception 'FAIL 2b: offered something it should not %', v;
  end if;
  if jsonb_array_length(public.get_product_alternatives(a, 3)) <> 3 then
    raise exception 'FAIL 2c: limit not kept';
  end if;
  -- Nothing linked: only the automatic ones.
  v := public.get_product_alternatives(f, 8);
  if jsonb_array_length(v) <> 3 or (v -> 0 ->> 'id')::uuid not in (a, d) then
    raise exception 'FAIL 2d: automatic only %', v;
  end if;
  raise notice 'PASS 2 (own picks first, then same category in stock)';

  -- 3. Saving again replaces this product's links only.
  perform public.set_product_alternatives(d, array[e]);
  perform public.set_product_alternatives(a, array[c]);
  v := public.get_linked_alternatives(a);
  if jsonb_array_length(v) <> 1 or (v -> 0 ->> 'id')::uuid <> c then
    raise exception 'FAIL 3a: replace %', v;
  end if;
  if jsonb_array_length(public.get_linked_alternatives(d)) <> 1 then
    raise exception 'FAIL 3b: another product''s links were touched';
  end if;
  perform public.set_product_alternatives(a, '{}');
  if jsonb_array_length(public.get_linked_alternatives(a)) <> 0 then
    raise exception 'FAIL 3c: could not clear';
  end if;
  raise notice 'PASS 3 (replace and clear)';

  -- 4. Other shops: neither their products nor yours across shops.
  perform pg_temp.act(owner_b);
  insert into public.products (business_id, name, selling_price) values (shop_b, 'ALT Beta Charger', 1) returning id into x;
  bad := false;
  begin perform public.set_product_alternatives(a, array[x]);
  exception when others then bad := sqlerrm like '%not found in your store%'; end;
  if not bad then raise exception 'FAIL 4a: changed another shop''s product'; end if;
  bad := false;
  begin perform public.set_product_alternatives(x, array[a]);
  exception when others then bad := sqlerrm like '%not a product of your store%'; end;
  if not bad then raise exception 'FAIL 4b: linked another shop''s product'; end if;
  if jsonb_array_length(public.get_product_alternatives(a)) <> 0
     or jsonb_array_length(public.get_linked_alternatives(c)) <> 0 then
    raise exception 'FAIL 4c: saw another shop''s alternatives';
  end if;
  bad := false;
  begin perform count(*) from public.product_alternatives;
  exception when others then bad := true; end;
  if not bad then raise exception 'FAIL 4d: the table can be read directly'; end if;
  raise notice 'PASS 4 (shops stay apart; table only through the functions)';
end $$;

rollback;
