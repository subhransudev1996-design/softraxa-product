-- ============================================================
-- Product photos on the shared list (migration 0082).
--
-- HOW TO RUN — on a STAGING copy, after 0082:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('82828282-0000-0000-0000-0000000000ad', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'photo-admin@test.invalid'),
  ('82828282-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'photo-owner@test.invalid');

insert into public.businesses (id, name, state_code, phone, business_type) values
  ('82828282-1111-0000-0000-00000000000a', 'PHOTOSHOP', '27', '9000082828', 'grocery');
update public.profiles set role = 'admin' where id = '82828282-0000-0000-0000-0000000000ad';
update public.profiles set business_id = '82828282-1111-0000-0000-00000000000a', role = 'owner'
  where id = '82828282-0000-0000-0000-00000000000a';

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

do $$
declare
  admin constant uuid := '82828282-0000-0000-0000-0000000000ad';
  owner constant uuid := '82828282-0000-0000-0000-00000000000a';
  shop  constant uuid := '82828282-1111-0000-0000-00000000000a';
  pic   constant text := 'https://ik.imagekit.io/test/zzphoto-biscuit.jpg';
  own   constant text := 'https://ik.imagekit.io/test/my-own-shelf.jpg';
  biscuit uuid; soap uuid; tea uuid; rusk uuid; p uuid; v jsonb; url text;
begin
  -- 1. SOFTRAXA adds products to the list and gives one a photo (logged).
  perform pg_temp.act(admin);
  biscuit := public.admin_save_master_product(null, jsonb_build_object('name', 'ZZPhoto Biscuit 100g'));
  soap    := public.admin_save_master_product(null, jsonb_build_object('name', 'ZZPhoto Soap 75g'));
  tea     := public.admin_save_master_product(null, jsonb_build_object('name', 'ZZPhoto Tea 250g'));
  rusk    := public.admin_save_master_product(null, jsonb_build_object('name', 'ZZPhoto Rusk 200g'));
  perform public.admin_set_master_product_image(biscuit, pic);
  perform public.admin_set_master_product_image(soap, pic);
  perform public.admin_set_master_product_image(tea, pic);
  perform public.admin_set_master_product_image(rusk, pic);
  if (select image_url from public.master_products where id = biscuit) is distinct from pic then
    raise exception 'FAIL 1a: photo not saved';
  end if;
  if not exists (select 1 from public.audit_logs
                 where action = 'master_product.photo' and entity_id = biscuit::text) then
    raise exception 'FAIL 1b: photo change not logged';
  end if;
  begin
    perform public.admin_set_master_product_image(biscuit, 'http://not-secure.example/x.jpg');
    raise exception 'FAIL 1c: a non-https address was accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  -- Clearing works.
  perform public.admin_set_master_product_image(tea, '');
  if (select image_url from public.master_products where id = tea) is not null then
    raise exception 'FAIL 1d: photo not cleared';
  end if;
  raise notice 'PASS 1 (SOFTRAXA sets, checks, logs and clears photos)';

  -- 2. Shops can't set photos on the list.
  perform pg_temp.act(owner);
  begin
    perform public.admin_set_master_product_image(biscuit, own);
    raise exception 'FAIL 2: a shop changed a list photo';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 2 (only SOFTRAXA sets list photos)';

  -- 3. The shop sees the photo while picking.
  v := public.search_master_products('zzphoto biscuit');
  if v -> 0 ->> 'image_url' is distinct from pic then
    raise exception 'FAIL 3a: search %', v;
  end if;
  v := public.browse_master_products('*', '', 'zzphoto biscuit');
  if v -> 'rows' -> 0 ->> 'image_url' is distinct from pic then
    raise exception 'FAIL 3b: browse %', v;
  end if;
  raise notice 'PASS 3 (search and browse return the photo)';

  -- 4. A product added from the list gets the photo...
  insert into public.products (business_id, name, master_product_id, selling_price)
    values (shop, 'ZZPhoto Biscuit 100g', biscuit, 10)
    returning image_url into url;
  if url is distinct from pic then raise exception 'FAIL 4a: photo not copied (%)', url; end if;
  -- ...unless the shop took its own.
  insert into public.products (business_id, name, master_product_id, selling_price, image_url)
    values (shop, 'ZZPhoto Soap 75g', soap, 20, own)
    returning image_url into url;
  if url is distinct from own then raise exception 'FAIL 4b: the shop''s own photo was replaced'; end if;
  -- ...or removed the list's photo on purpose (the app saves '').
  insert into public.products (business_id, name, master_product_id, selling_price, image_url)
    values (shop, 'ZZPhoto Rusk 200g', rusk, 40, '')
    returning image_url into url;
  if url <> '' then raise exception 'FAIL 4d: a removed photo came back (%)', url; end if;
  -- A list product without a photo leaves it empty.
  insert into public.products (business_id, name, master_product_id, selling_price)
    values (shop, 'ZZPhoto Tea 250g', tea, 30)
    returning image_url into url;
  if url is not null then raise exception 'FAIL 4c: got a photo from nowhere'; end if;
  raise notice 'PASS 4 (list photo copied; the shop''s own photo wins)';

  -- 5. A shop's photo never reaches the list.
  insert into public.products (business_id, name, selling_price, image_url)
    values (shop, 'ZZPhoto Brand New Namkeen', 15, own)
    returning master_product_id into p;
  perform pg_temp.act(admin);
  if exists (select 1 from public.master_products where image_url = own) then
    raise exception 'FAIL 5: a shop photo reached the shared list';
  end if;
  raise notice 'PASS 5 (shop photos stay in the shop)';
end $$;

reset role;
do $$ begin raise notice 'ALL PRODUCT PHOTO CHECKS PASSED — rolling back test data'; end $$;
rollback;
