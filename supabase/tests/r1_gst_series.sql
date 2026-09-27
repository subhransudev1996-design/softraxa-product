-- ============================================================
-- R1 yearly invoice series, bill of supply and HSN (migration 0048).
--
-- HOW TO RUN — on a STAGING copy, AFTER 0048 has been run on its own
-- (the 'composition' value only exists once that migration is committed):
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('dededede-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'r1-series-owner@test.invalid'),
  ('dededede-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'r1-series-comp@test.invalid');

-- A regular GST shop with a 5-letter prefix, and a composition shop.
insert into public.businesses (id, name, state_code, gst_number, invoice_prefix, tax_preference) values
  ('dededede-1111-0000-0000-00000000000a', 'R1 Series Shop', '27', '27AAPFU0939F1ZV', 'SHOPX', 'gst'),
  ('dededede-1111-0000-0000-00000000000b', 'R1 Composition Shop', '27', '27AAPFU0939F1ZV', 'CMP', 'composition');

update public.profiles set business_id = 'dededede-1111-0000-0000-00000000000a', role = 'owner'
  where id = 'dededede-0000-0000-0000-00000000000a';
update public.profiles set business_id = 'dededede-1111-0000-0000-00000000000b', role = 'owner'
  where id = 'dededede-0000-0000-0000-00000000000b';

insert into public.subscriptions (business_id, status, expiry_date) values
  ('dededede-1111-0000-0000-00000000000a', 'active', current_date + 30),
  ('dededede-1111-0000-0000-00000000000b', 'active', current_date + 30);

-- A cover with no HSN yet; stock for both shops.
insert into public.products (id, business_id, name, selling_price, purchase_price, gst_rate, hsn_code) values
  ('dededede-2222-0000-0000-00000000000a', 'dededede-1111-0000-0000-00000000000a', 'R1 Cover', 100, 60, 0, ''),
  ('dededede-2222-0000-0000-00000000000b', 'dededede-1111-0000-0000-00000000000b', 'R1 Cover', 100, 60, 0, '');
insert into public.stock_movements (business_id, product_id, movement_type, quantity, note) values
  ('dededede-1111-0000-0000-00000000000a', 'dededede-2222-0000-0000-00000000000a', 'opening', 100, 'r1 test'),
  ('dededede-1111-0000-0000-00000000000b', 'dededede-2222-0000-0000-00000000000b', 'opening', 100, 'r1 test');

insert into public.customers (id, business_id, name, gst_number, credit_unlimited) values
  ('dededede-3333-0000-0000-0000000000b2', 'dededede-1111-0000-0000-00000000000a',
   'R1 Registered Buyer', '29AAPFU0939F1ZR', true),
  ('dededede-3333-0000-0000-0000000000c2', 'dededede-1111-0000-0000-00000000000a',
   'R1 Walk-in', '', true);

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

-- A one-line cash bill for the cover (price 100, no GST).
create or replace function pg_temp.bill(p_type text, p_customer uuid, p_product uuid,
  p_date timestamptz default null) returns jsonb language sql as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'invoice_type', p_type, 'customer_id', p_customer, 'customer_name', 'x',
    'invoice_date', p_date, 'paid_amount', 100, 'payment_mode', 'cash',
    'items', jsonb_build_array(jsonb_build_object(
      'product_id', p_product, 'product_name', 'R1 Cover', 'quantity', 1,
      'unit_price', 100, 'gst_rate', 0, 'tax_amount', 0, 'line_total', 100))));
$$;

set local role authenticated;

do $$
declare
  owner    constant uuid := 'dededede-0000-0000-0000-00000000000a';
  comp     constant uuid := 'dededede-0000-0000-0000-00000000000b';
  cover    constant uuid := 'dededede-2222-0000-0000-00000000000a';
  cover_b  constant uuid := 'dededede-2222-0000-0000-00000000000b';
  buyer    constant uuid := 'dededede-3333-0000-0000-0000000000b2';
  walkin   constant uuid := 'dededede-3333-0000-0000-0000000000c2';
  fy       constant text := public.fy_label(public.ist_date(now()));
  prev_fy  constant text := public.fy_label(public.ist_date(now()) - 366);
  v jsonb; s text; s2 text;
begin
  perform pg_temp.act(owner);

  -- 1. Yearly series, prefix cut to 4 characters, at most 16 characters.
  s := public.create_invoice(pg_temp.bill('gst', walkin, cover)) ->> 'invoice_no';
  s2 := public.create_invoice(pg_temp.bill('gst', walkin, cover)) ->> 'invoice_no';
  if s <> 'SHOP/' || fy || '/0001' or s2 <> 'SHOP/' || fy || '/0002' or length(s) > 16 then
    raise exception 'FAIL 1: % then %', s, s2;
  end if;
  raise notice 'PASS 1 (% then %)', s, s2;

  -- 2. A bill dated last year (made offline) takes last year's series.
  s := public.create_invoice(pg_temp.bill('gst', walkin, cover, now() - interval '366 days')) ->> 'invoice_no';
  if s <> 'SHOP/' || prev_fy || '/0001' then
    raise exception 'FAIL 2: last year''s bill numbered %', s;
  end if;
  s := public.create_invoice(pg_temp.bill('gst', walkin, cover)) ->> 'invoice_no';
  if s <> 'SHOP/' || fy || '/0003' then
    raise exception 'FAIL 2b: this year''s series broken: %', s;
  end if;
  raise notice 'PASS 2 (bill dated last year → SHOP/%/0001; this year continues at 0003)', prev_fy;

  -- 3. Cash memos have their own yearly series.
  s := public.create_invoice(pg_temp.bill('cash_memo', walkin, cover)) ->> 'invoice_no';
  if s <> 'CM/' || fy || '/0001' then raise exception 'FAIL 3: cash memo %', s; end if;
  raise notice 'PASS 3 (cash memo %)', s;

  -- 4. HSN format is checked.
  begin
    update public.products set hsn_code = '85A7' where id = cover;
    raise exception 'FAIL 4: bad HSN accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 4 (HSN format): %', sqlerrm;
  end;

  -- 5. B2B tax invoice needs HSN on every line; B2C doesn't.
  begin
    perform public.create_invoice(pg_temp.bill('gst', buyer, cover));
    raise exception 'FAIL 5a: B2B bill without HSN';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 5a (B2B needs HSN): %', sqlerrm;
  end;
  update public.products set hsn_code = '3926' where id = cover;
  v := public.create_invoice(pg_temp.bill('gst', buyer, cover));
  if (select hsn_code from public.invoice_items where invoice_id = (v ->> 'id')::uuid) <> '3926' then
    raise exception 'FAIL 5b: HSN not filled from the product';
  end if;
  raise notice 'PASS 5 (B2B bill carries HSN 3926 from the product; B2C bills above had none)';

  -- 6. Composition shop: no GST tax invoice; a bill of supply is fine.
  perform pg_temp.act(comp);
  begin
    perform public.create_invoice(pg_temp.bill('gst', null, cover_b));
    raise exception 'FAIL 6a: composition shop charged GST';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  s := public.create_invoice(pg_temp.bill('non_gst', null, cover_b)) ->> 'invoice_no';
  if s <> 'CMP/' || fy || '/0001' then raise exception 'FAIL 6b: %', s; end if;
  raise notice 'PASS 6 (composition: GST refused, bill of supply %)', s;

  -- 7. Setup accepts composition; prefix limited to 4 characters.
  begin
    perform public.complete_onboarding(jsonb_build_object('business_type', 'garment',
      'tax_preference', 'composition', 'gst_number', '27AAPFU0939F1ZV',
      'turnover_band', 'up_to_5cr', 'invoice_prefix', 'ABCDE'));
    raise exception 'FAIL 7a: 5-character prefix accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  v := public.complete_onboarding(jsonb_build_object('business_type', 'garment',
    'tax_preference', 'composition', 'gst_number', '27AAPFU0939F1ZV',
    'turnover_band', 'up_to_5cr', 'invoice_prefix', 'cmp'));
  if v ->> 'tax_preference' <> 'composition' or v ->> 'invoice_prefix' <> 'CMP' then
    raise exception 'FAIL 7b: %', v;
  end if;
  raise notice 'PASS 7 (composition set up; prefix up to 4 characters)';
end $$;

reset role;
do $$ begin raise notice 'ALL R1 GST SERIES CHECKS PASSED — rolling back test data'; end $$;
rollback;
