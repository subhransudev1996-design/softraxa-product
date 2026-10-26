-- ============================================================
-- Dukania AI phase 3/4: supplier bills and returns (migration 0088).
--
-- HOW TO RUN — on a STAGING copy, after 0087 and 0088:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes with "ai_purchases_returns tests passed".
-- The first failed check stops the run with "FAIL …".
--
-- A GST kirana with supplier Gupta Traders. Ghee ₹650 incl. 12% GST is
-- already known from Gupta's bills as "amul ghee 1l". Their new bill also
-- has a biscuit the shop doesn't stock yet (boxes of 12).
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);
select set_config('request.headers', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('88888888-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'ai-pur-owner@test.invalid'),
  ('88888888-0000-0000-0000-0000000000a5', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'ai-pur-staff@test.invalid');

insert into public.businesses (id, name, state_code, business_type, tax_preference) values
  ('88888888-1111-0000-0000-00000000000a', 'AI Purchase Kirana', '21', 'grocery', 'gst');
update public.profiles set business_id = '88888888-1111-0000-0000-00000000000a', role = 'owner'
  where id = '88888888-0000-0000-0000-00000000000a';
update public.profiles set business_id = '88888888-1111-0000-0000-00000000000a', role = 'staff'
  where id = '88888888-0000-0000-0000-0000000000a5';

insert into public.plans (id, name, software_id, user_limit, included_features)
select '88888888-9999-0000-0000-000000000001', 'AI Purchase Plan', id, 3, '[]'
from public.software_products where slug = 'dukania';
insert into public.subscriptions (business_id, plan_id, status, expiry_date) values
  ('88888888-1111-0000-0000-00000000000a', '88888888-9999-0000-0000-000000000001',
   'active', current_date + 30);

insert into public.suppliers (id, business_id, name, gst_number, state_code) values
  ('88888888-4444-0000-0000-000000000001', '88888888-1111-0000-0000-00000000000a',
   'AI Gupta Traders', '21AAAAA0000A1Z5', '21');
insert into public.products (id, business_id, name, selling_price, purchase_price, gst_rate, hsn_code) values
  ('88888888-2222-0000-0000-000000000001', '88888888-1111-0000-0000-00000000000a',
   'AI Amul Pure Ghee 1 L', 650, 480, 12, '0405');
insert into public.stock_movements (business_id, product_id, movement_type, quantity, note) values
  ('88888888-1111-0000-0000-00000000000a', '88888888-2222-0000-0000-000000000001', 'opening', 5, 'ai test');
insert into public.supplier_bill_items (business_id, supplier_id, item_key, product_id, factor) values
  ('88888888-1111-0000-0000-00000000000a', '88888888-4444-0000-0000-000000000001',
   'amul ghee 1l', '88888888-2222-0000-0000-000000000001', 1);

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

-- Gupta's bill: 10 ghee @ 500 + 12% = 5,600; 2 boxes of 12 biscuits
-- @ 120 a box + 18% = 283.20; total 5,883.20 → 5,883. On credit.
create or replace function pg_temp.bill(p_ref text default null) returns jsonb language sql as $$
  select jsonb_build_object(
    'supplier_id', '88888888-4444-0000-0000-000000000001',
    'bill_no', 'GT-101', 'bill_total', 5883, 'paid', 'none',
    'lines', jsonb_build_array(
      jsonb_build_object('bill_name', 'AMUL GHEE 1LTR TIN', 'bill_key', 'amul ghee 1l',
                         'quantity', 10, 'rate', 500, 'gst_rate', 12),
      jsonb_build_object('bill_name', 'CRUNCHY BISCUIT 100G', 'bill_key', 'crunchy biscuit 100g',
                         'quantity', 2, 'pack_size', 12, 'rate', 120, 'gst_rate', 18,
                         'new_product', jsonb_build_object('name', 'AI Crunchy Biscuit 100 g',
                                                           'selling_price', 15, 'mrp', 15))))
    || case when p_ref is null then '{}'::jsonb else jsonb_build_object('ref', p_ref) end;
$$;

create or replace function pg_temp.purchases() returns bigint language sql as $$
  select count(*) from public.purchases where business_id = '88888888-1111-0000-0000-00000000000a';
$$;
create or replace function pg_temp.biscuits() returns bigint language sql as $$
  select count(*) from public.products
  where business_id = '88888888-1111-0000-0000-00000000000a' and name = 'AI Crunchy Biscuit 100 g';
$$;

set local role authenticated;

-- 1. Preview: matched from memory, new product shown, totals agree; nothing saved.
do $$
declare v jsonb;
begin
  perform pg_temp.act('88888888-0000-0000-0000-00000000000a');
  v := public.ai_purchase(pg_temp.bill(), false);
  if not (v ->> 'ok')::boolean then raise exception 'FAIL 1a: preview not ok: %', v; end if;
  if (v #>> '{summary,total}')::numeric <> 5883 or not (v #>> '{summary,matches_printed_total}')::boolean then
    raise exception 'FAIL 1b: total should be 5883 and match the bill: %', v -> 'summary';
  end if;
  if v #>> '{summary,lines,0,how}' <> 'remembered' or v #>> '{summary,lines,1,how}' <> 'new' then
    raise exception 'FAIL 1c: line matching wrong: %', v #> '{summary,lines}';
  end if;
  if (v #>> '{summary,lines,1,quantity}')::numeric <> 24 then
    raise exception 'FAIL 1d: 2 boxes of 12 should be 24 pieces';
  end if;
  if pg_temp.purchases() <> 0 or pg_temp.biscuits() <> 0 then
    raise exception 'FAIL 1e: the preview saved a purchase or a product';
  end if;
end $$;

-- 2. A line that isn't matched can't be saved.
do $$
declare v jsonb; b jsonb := pg_temp.bill();
begin
  perform pg_temp.act('88888888-0000-0000-0000-00000000000a');
  b := jsonb_set(b, '{lines,1}', (b #> '{lines,1}') - 'new_product');
  v := public.ai_purchase(b, false);
  if (v ->> 'ok')::boolean or v #>> '{summary,not_matched,0,line}' <> '2' then
    raise exception 'FAIL 2a: unmatched line should be reported: %', v;
  end if;
  begin
    perform public.ai_purchase(b || '{"ref": "88888888-5555-0000-0000-0000000000ff"}', true);
    raise exception 'FAIL 2b: purchase saved with an unmatched line';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
end $$;

-- 3. The real purchase, made by the AI.
select set_config('request.headers', '{"x-dukania-source": "ai"}', true);
do $$
declare v jsonb; pu record;
begin
  perform pg_temp.act('88888888-0000-0000-0000-00000000000a');
  begin
    perform public.ai_purchase(pg_temp.bill(), true);
    raise exception 'FAIL 3a: purchase saved without a ref';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  v := public.ai_purchase(pg_temp.bill('88888888-5555-0000-0000-000000000001'), true);
  select * into pu from public.purchases where id = (v ->> 'purchase_id')::uuid;
  if pu.id is null or pu.total <> 5883 or pu.paid_amount <> 0 or pu.created_via <> 'ai' then
    raise exception 'FAIL 3b: purchase wrong: %', to_jsonb(pu);
  end if;
  if (select current_stock from public.products where id = '88888888-2222-0000-0000-000000000001') <> 15 then
    raise exception 'FAIL 3c: ghee stock should be 5 + 10';
  end if;
  if (select current_stock from public.products
      where business_id = '88888888-1111-0000-0000-00000000000a' and name = 'AI Crunchy Biscuit 100 g') <> 24 then
    raise exception 'FAIL 3d: new biscuit should have 24 in stock';
  end if;
  if (select created_via from public.products where name = 'AI Crunchy Biscuit 100 g'
      and business_id = '88888888-1111-0000-0000-00000000000a') <> 'ai' then
    raise exception 'FAIL 3e: new product not marked as made by the AI';
  end if;
  if (select due_amount from public.suppliers where id = '88888888-4444-0000-0000-000000000001') <> 5883 then
    raise exception 'FAIL 3f: the shop should owe Gupta 5883';
  end if;
  -- The memory table is only reachable through its functions (0078).
  v := public.bill_memory('88888888-4444-0000-0000-000000000001', array['crunchy biscuit 100g']);
  if coalesce((v #>> '{items,0,factor}')::numeric, 0) <> 12 then
    raise exception 'FAIL 3g: the biscuit name (box of 12) was not remembered: %', v;
  end if;

  -- 4. Confirming again returns the same purchase.
  v := public.ai_purchase(pg_temp.bill('88888888-5555-0000-0000-000000000001'), true);
  if not (v ->> 'already_saved')::boolean or pg_temp.purchases() <> 1 or pg_temp.biscuits() <> 1 then
    raise exception 'FAIL 4: second confirm made another purchase: %', v;
  end if;

  -- 5. Next bill: the biscuit is now remembered, no new product needed.
  v := public.ai_purchase(jsonb_build_object(
         'supplier_id', '88888888-4444-0000-0000-000000000001',
         'lines', jsonb_build_array(jsonb_build_object(
           'bill_name', 'CRUNCHY BISCUIT 100G', 'bill_key', 'crunchy biscuit 100g',
           'quantity', 1, 'rate', 120, 'gst_rate', 18))), false);
  if v #>> '{summary,lines,0,how}' <> 'remembered' or (v #>> '{summary,lines,0,quantity}')::numeric <> 12 then
    raise exception 'FAIL 5: remembered box of 12 not used: %', v -> 'summary';
  end if;
end $$;

-- 6. A new supplier from the bill; the same GSTIN later is that supplier.
do $$
declare v jsonb; p jsonb;
begin
  perform pg_temp.act('88888888-0000-0000-0000-00000000000a');
  p := jsonb_build_object(
         'new_supplier', jsonb_build_object('name', 'AI Sharma Wholesale', 'gstin', '21BBBBB1111B1Z5'),
         'lines', jsonb_build_array(jsonb_build_object(
           'product_id', '88888888-2222-0000-0000-000000000001', 'quantity', 1, 'rate', 500)),
         'ref', '88888888-5555-0000-0000-000000000006');
  v := public.ai_purchase(p, false);
  if not coalesce((v #>> '{summary,new_supplier}')::boolean, false) then
    raise exception 'FAIL 6a: a new supplier should be shown: %', v -> 'summary';
  end if;
  v := public.ai_purchase(p, true);
  if not exists (select 1 from public.suppliers where gst_number = '21BBBBB1111B1Z5'
                 and business_id = '88888888-1111-0000-0000-00000000000a') then
    raise exception 'FAIL 6b: new supplier not added';
  end if;
  v := public.ai_purchase(jsonb_set(p, '{new_supplier,name}', '"Sharma W/S"') - 'ref', false);
  if coalesce((v #>> '{summary,new_supplier}')::boolean, false) then
    raise exception 'FAIL 6c: same GSTIN should be the existing supplier';
  end if;
end $$;
select set_config('request.headers', '', true);

-- 7. Staff without the purchases right can't.
do $$
begin
  perform pg_temp.act('88888888-0000-0000-0000-0000000000a5');
  begin
    perform public.ai_purchase(pg_temp.bill(), false);
    raise exception 'FAIL 7: staff previewed a purchase without the right';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
end $$;

-- 8. Returns: 2 ghee sold, 1 comes back.
do $$
declare v jsonb; s jsonb; line uuid; stock numeric;
begin
  perform pg_temp.act('88888888-0000-0000-0000-00000000000a');
  s := public.ai_create_sale(jsonb_build_object(
         'lines', jsonb_build_array(jsonb_build_object(
           'product_id', '88888888-2222-0000-0000-000000000001', 'quantity', 2)),
         'sale_ref', '88888888-5555-0000-0000-000000000008'));
  select id into line from public.invoice_items where invoice_id = (s ->> 'bill_id')::uuid;
  stock := (select current_stock from public.products where id = '88888888-2222-0000-0000-000000000001');

  v := public.ai_return(jsonb_build_object('bill_id', s ->> 'bill_id',
         'lines', jsonb_build_array(jsonb_build_object('bill_line_id', line, 'quantity', 1))), false);
  if (v #>> '{summary,return_value}')::numeric <> 650 or (v #>> '{summary,refund_now}')::numeric <> 650 then
    raise exception 'FAIL 8a: return of 1 ghee should be worth 650, refunded: %', v;
  end if;
  if exists (select 1 from public.sale_returns where invoice_id = (s ->> 'bill_id')::uuid) then
    raise exception 'FAIL 8b: return preview saved a return';
  end if;

  v := public.ai_return(jsonb_build_object('bill_id', s ->> 'bill_id', 'ref', '88888888-5555-0000-0000-000000000009',
         'lines', jsonb_build_array(jsonb_build_object('bill_line_id', line, 'quantity', 1))), true);
  if (select current_stock from public.products where id = '88888888-2222-0000-0000-000000000001') <> stock + 1 then
    raise exception 'FAIL 8c: returned ghee not back in stock';
  end if;
  v := public.ai_return(jsonb_build_object('bill_id', s ->> 'bill_id', 'ref', '88888888-5555-0000-0000-000000000009',
         'lines', jsonb_build_array(jsonb_build_object('bill_line_id', line, 'quantity', 1))), true);
  if not (v ->> 'already_saved')::boolean
     or (select count(*) from public.sale_returns where invoice_id = (s ->> 'bill_id')::uuid) <> 1 then
    raise exception 'FAIL 8d: second confirm made another return: %', v;
  end if;

  begin
    perform public.ai_return(jsonb_build_object('bill_id', s ->> 'bill_id',
      'lines', jsonb_build_array(jsonb_build_object('bill_line_id', line, 'quantity', 5))), false);
    raise exception 'FAIL 8e: returned more than was sold';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
end $$;

select 'ai_purchases_returns tests passed' as result;

rollback;
