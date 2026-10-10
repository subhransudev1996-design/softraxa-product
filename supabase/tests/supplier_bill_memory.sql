-- ============================================================
-- Remembering supplier bills: item names and columns (migration 0078).
--
-- HOW TO RUN — on a STAGING copy, after 0078:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('78787878-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'bm-owner-a@test.invalid'),
  ('78787878-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'bm-staff-a@test.invalid'),
  ('78787878-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'bm-owner-b@test.invalid');
insert into public.businesses (id, name, state_code) values
  ('78787878-1111-0000-0000-00000000000a', 'BM Shop A', '27'),
  ('78787878-1111-0000-0000-00000000000b', 'BM Shop B', '27');
update public.profiles set business_id = '78787878-1111-0000-0000-00000000000a', role = 'owner'
  where id = '78787878-0000-0000-0000-00000000000a';
update public.profiles set business_id = '78787878-1111-0000-0000-00000000000a', role = 'staff'
  where id = '78787878-0000-0000-0000-0000000000a1';
update public.profiles set business_id = '78787878-1111-0000-0000-00000000000b', role = 'owner'
  where id = '78787878-0000-0000-0000-00000000000b';
-- The staff member makes bills but doesn't handle purchases.
insert into public.staff_permissions (profile_id, business_id, can_create_invoice, can_manage_purchases)
  values ('78787878-0000-0000-0000-0000000000a1', '78787878-1111-0000-0000-00000000000a', true, false);
-- A 2-user plan, so the staff login counts (user limit, 0058).
insert into public.plans (id, name, software_id, user_limit, included_features)
select '78787878-9999-0000-0000-00000000000a', 'BM Two Users', id, 2, '[]'
from public.software_products where slug = 'dukania';
insert into public.subscriptions (business_id, plan_id, status, expiry_date) values
  ('78787878-1111-0000-0000-00000000000a', '78787878-9999-0000-0000-00000000000a',
   'active', current_date + 30);

insert into public.suppliers (id, business_id, name) values
  ('78787878-3333-0000-0000-00000000000a', '78787878-1111-0000-0000-00000000000a', 'BM Gupta Traders'),
  ('78787878-3333-0000-0000-00000000000c', '78787878-1111-0000-0000-00000000000a', 'BM Other Agency'),
  ('78787878-3333-0000-0000-00000000000b', '78787878-1111-0000-0000-00000000000b', 'BM B Supplier');
insert into public.products (id, business_id, name, selling_price, purchase_price, gst_rate, has_variants) values
  ('78787878-2222-0000-0000-00000000000a', '78787878-1111-0000-0000-00000000000a', 'BM Amul Ghee 1 L', 600, 550, 12, false),
  ('78787878-2222-0000-0000-00000000000c', '78787878-1111-0000-0000-00000000000a', 'BM Kurta', 500, 300, 5, true),
  ('78787878-2222-0000-0000-00000000000b', '78787878-1111-0000-0000-00000000000b', 'BM B Product', 10, 5, 0, false);
insert into public.product_variants (id, business_id, product_id, name) values
  ('78787878-4444-0000-0000-00000000000a', '78787878-1111-0000-0000-00000000000a',
   '78787878-2222-0000-0000-00000000000c', 'Red / M');

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

do $$
declare
  owner_a constant uuid := '78787878-0000-0000-0000-00000000000a';
  staff_a constant uuid := '78787878-0000-0000-0000-0000000000a1';
  owner_b constant uuid := '78787878-0000-0000-0000-00000000000b';
  gupta   constant uuid := '78787878-3333-0000-0000-00000000000a';
  other   constant uuid := '78787878-3333-0000-0000-00000000000c';
  sup_b   constant uuid := '78787878-3333-0000-0000-00000000000b';
  ghee    constant uuid := '78787878-2222-0000-0000-00000000000a';
  kurta   constant uuid := '78787878-2222-0000-0000-00000000000c';
  red_m   constant uuid := '78787878-4444-0000-0000-00000000000a';
  prod_b  constant uuid := '78787878-2222-0000-0000-00000000000b';
  v_n     integer;
  v_mem   jsonb;
  v_ok    boolean;
begin
  -- 1. The owner teaches two names for Gupta, with Gupta's columns.
  perform pg_temp.act(owner_a);
  v_n := public.remember_bill(gupta, jsonb_build_array(
    jsonb_build_object('key', 'amul ghee 1l tin', 'product_id', ghee, 'factor', 1),
    jsonb_build_object('key', 'kurta red m', 'product_id', kurta, 'variant_id', red_m, 'factor', 1)),
    '{"value": "rate", "net": "amount"}'::jsonb);
  if v_n <> 2 then raise exception 'FAIL 1: saved % names, expected 2', v_n; end if;

  v_mem := public.bill_memory(gupta, array['amul ghee 1l tin', 'kurta red m', 'unknown item']);
  if jsonb_array_length(v_mem -> 'items') <> 2 then
    raise exception 'FAIL 2: memory has % names, expected 2: %', jsonb_array_length(v_mem -> 'items'), v_mem;
  end if;
  if not exists (select 1 from jsonb_array_elements(v_mem -> 'items') i
                 where i ->> 'key' = 'kurta red m' and (i ->> 'variant_id')::uuid = red_m
                   and (i ->> 'same_supplier')::boolean) then
    raise exception 'FAIL 3: the kurta variant was not remembered for Gupta: %', v_mem;
  end if;
  if v_mem -> 'columns' <> '{"value": "rate", "net": "amount"}'::jsonb then
    raise exception 'FAIL 4: columns are %', v_mem -> 'columns';
  end if;

  -- 2. Another supplier's bill gets Gupta's names too, as not its own.
  v_mem := public.bill_memory(other, array['amul ghee 1l tin']);
  if not exists (select 1 from jsonb_array_elements(v_mem -> 'items') i
                 where (i ->> 'product_id')::uuid = ghee and not (i ->> 'same_supplier')::boolean) then
    raise exception 'FAIL 5: another supplier did not get the name: %', v_mem;
  end if;
  if v_mem -> 'columns' <> '{}'::jsonb then
    raise exception 'FAIL 6: another supplier got Gupta''s columns: %', v_mem -> 'columns';
  end if;

  -- 3. Teaching it again replaces it (now in boxes of 12), and the
  --    supplier's own link wins over another's.
  perform public.remember_bill(other, jsonb_build_array(
    jsonb_build_object('key', 'amul ghee 1l tin', 'product_id', kurta, 'factor', 1)), null);
  perform public.remember_bill(gupta, jsonb_build_array(
    jsonb_build_object('key', 'amul ghee 1l tin', 'product_id', ghee, 'factor', 12)), null);
  v_mem := public.bill_memory(gupta, array['amul ghee 1l tin']);
  if (v_mem -> 'items' -> 0 ->> 'product_id')::uuid <> ghee
     or (v_mem -> 'items' -> 0 ->> 'factor')::numeric <> 12 then
    raise exception 'FAIL 7: Gupta''s own link should win with factor 12: %', v_mem;
  end if;
  -- (Counted as the database owner: app users can't read the table.)
  reset role;
  if (select count(*) from public.supplier_bill_items
      where supplier_id = gupta and item_key = 'amul ghee 1l tin') <> 1 then
    raise exception 'FAIL 8: the name is saved twice for Gupta';
  end if;
  set local role authenticated;
  if v_mem -> 'columns' <> '{"value": "rate", "net": "amount"}'::jsonb then
    raise exception 'FAIL 9: null columns should leave them as they were: %', v_mem -> 'columns';
  end if;

  -- 4. '{}' forgets the columns; a bad column choice is refused.
  perform public.remember_bill(gupta, '[]'::jsonb, '{}'::jsonb);
  if public.bill_memory(gupta, array[]::text[]) -> 'columns' <> '{}'::jsonb then
    raise exception 'FAIL 10: columns were not forgotten';
  end if;
  v_ok := false;
  begin
    perform public.remember_bill(gupta, '[]'::jsonb, '{"value": "drop table"}'::jsonb);
  exception when others then v_ok := true;
  end;
  if not v_ok then raise exception 'FAIL 11: an unknown column choice was accepted'; end if;

  -- 5. Someone else's product, variant or supplier is refused.
  v_ok := false;
  begin
    perform public.remember_bill(gupta, jsonb_build_array(
      jsonb_build_object('key', 'x', 'product_id', prod_b)), null);
  exception when others then v_ok := true;
  end;
  if not v_ok then raise exception 'FAIL 12: another shop''s product was accepted'; end if;
  v_ok := false;
  begin
    perform public.remember_bill(gupta, jsonb_build_array(
      jsonb_build_object('key', 'x', 'product_id', ghee, 'variant_id', red_m)), null);
  exception when others then v_ok := true;
  end;
  if not v_ok then raise exception 'FAIL 13: a variant of another product was accepted'; end if;
  v_ok := false;
  begin
    perform public.bill_memory(sup_b, array['x']);
  exception when others then v_ok := true;
  end;
  if not v_ok then raise exception 'FAIL 14: another shop''s supplier was accepted'; end if;

  -- 6. Staff without purchases can't read or teach.
  perform pg_temp.act(staff_a);
  v_ok := false;
  begin
    perform public.bill_memory(gupta, array['amul ghee 1l tin']);
  exception when others then v_ok := true;
  end;
  if not v_ok then raise exception 'FAIL 15: staff without purchases read the memory'; end if;
  v_ok := false;
  begin
    perform public.remember_bill(gupta, jsonb_build_array(
      jsonb_build_object('key', 'y', 'product_id', ghee)), null);
  exception when others then v_ok := true;
  end;
  if not v_ok then raise exception 'FAIL 16: staff without purchases taught a name'; end if;

  -- 7. Another shop sees nothing of shop A's names, and can't read the
  --    tables directly.
  perform pg_temp.act(owner_b);
  v_mem := public.bill_memory(null, array['amul ghee 1l tin', 'kurta red m']);
  if jsonb_array_length(v_mem -> 'items') <> 0 then
    raise exception 'FAIL 17: shop B saw shop A''s names: %', v_mem;
  end if;
  v_ok := false;
  begin
    perform 1 from public.supplier_bill_items;
  exception when others then v_ok := true;
  end;
  if not v_ok then raise exception 'FAIL 18: the table can be read directly'; end if;

  -- 8. A name without a supplier is remembered for any supplier.
  perform pg_temp.act(owner_a);
  perform public.remember_bill(null, jsonb_build_array(
    jsonb_build_object('key', 'walk in item', 'product_id', ghee)), '{"a": "rate"}'::jsonb);
  v_mem := public.bill_memory(gupta, array['walk in item']);
  if jsonb_array_length(v_mem -> 'items') <> 1 then
    raise exception 'FAIL 19: a name taught without a supplier was not offered: %', v_mem;
  end if;

  -- 9. A deleted product's names go with it.
  reset role;
  delete from public.products where id = kurta;
  if exists (select 1 from public.supplier_bill_items where product_id = kurta) then
    raise exception 'FAIL 20: names of a deleted product were kept';
  end if;
end $$;

rollback;
