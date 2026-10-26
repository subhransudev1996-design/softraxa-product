-- ============================================================
-- Dukania AI: free goods, new prices from the bill, changing a purchase,
-- purchase returns (migration 0090).
--
-- HOW TO RUN — on a STAGING copy, after 0087–0090:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes with "ai_purchase_more tests passed". The
-- first failed check stops the run with "FAIL …".
--
-- Gupta's bill: 10 ghee @ ₹500 + 12% GST, 1 more free, on credit; the
-- bill also brings ghee's new MRP ₹699 and the shop sells at ₹660 now.
-- Then: a new shoe in sizes from a bill, a split payment, IMEI phones.
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);
select set_config('request.headers', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('90909090-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'ai-pm-owner@test.invalid'),
  ('90909090-0000-0000-0000-0000000000a5', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'ai-pm-staff@test.invalid');
insert into public.businesses (id, name, state_code, business_type, tax_preference) values
  ('90909090-1111-0000-0000-00000000000a', 'AI Purchase More Kirana', '21', 'grocery', 'gst');
update public.profiles set business_id = '90909090-1111-0000-0000-00000000000a', role = 'owner'
  where id = '90909090-0000-0000-0000-00000000000a';
update public.profiles set business_id = '90909090-1111-0000-0000-00000000000a', role = 'staff'
  where id = '90909090-0000-0000-0000-0000000000a5';
insert into public.plans (id, name, software_id, user_limit, included_features)
select '90909090-9999-0000-0000-000000000001', 'AI PM Plan', id, 3, '[]'
from public.software_products where slug = 'dukania';
insert into public.subscriptions (business_id, plan_id, status, expiry_date) values
  ('90909090-1111-0000-0000-00000000000a', '90909090-9999-0000-0000-000000000001',
   'active', current_date + 30);
insert into public.suppliers (id, business_id, name, state_code) values
  ('90909090-4444-0000-0000-000000000001', '90909090-1111-0000-0000-00000000000a', 'AI Gupta Traders', '21');
insert into public.products (id, business_id, name, selling_price, mrp, purchase_price, gst_rate) values
  ('90909090-2222-0000-0000-000000000001', '90909090-1111-0000-0000-00000000000a',
   'AI PM Ghee 1 L', 650, 680, 480, 12);
insert into public.stock_movements (business_id, product_id, movement_type, quantity, note) values
  ('90909090-1111-0000-0000-00000000000a', '90909090-2222-0000-0000-000000000001', 'opening', 5, 'ai test');
insert into public.products (id, business_id, name, selling_price, purchase_price, gst_rate, track_serial) values
  ('90909090-2222-0000-0000-0000000000f0', '90909090-1111-0000-0000-00000000000a',
   'AI PM Phone', 10000, 8000, 18, true);

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
create or replace function pg_temp.ghee() returns public.products language sql as $$
  select * from public.products where id = '90909090-2222-0000-0000-000000000001';
$$;
create or replace function pg_temp.bill(p_qty numeric, p_extra jsonb default '{}') returns jsonb language sql as $$
  select jsonb_build_object(
    'supplier_id', '90909090-4444-0000-0000-000000000001', 'bill_no', 'GT-201', 'paid', 'none',
    'lines', jsonb_build_array(jsonb_build_object(
      'product_id', '90909090-2222-0000-0000-000000000001', 'quantity', p_qty, 'rate', 500,
      'gst_rate', 12, 'free_quantity', 1, 'new_selling_price', 660, 'new_mrp', 699))) || p_extra;
$$;

set local role authenticated;

-- 1. Free goods and new prices: preview, then the real purchase.
do $$
declare v jsonb; g public.products; pid uuid;
begin
  perform pg_temp.act('90909090-0000-0000-0000-00000000000a');
  v := public.ai_purchase(pg_temp.bill(10), false);
  if (v #>> '{summary,total}')::numeric <> 5600 or (v #>> '{summary,lines,0,free}')::numeric <> 1
     or (v #>> '{summary,price_changes,0,selling_price}')::numeric <> 660 then
    raise exception 'FAIL 1a: preview should be 5600 with 1 free and the new price: %', v -> 'summary';
  end if;
  if (pg_temp.ghee()).selling_price <> 650 then raise exception 'FAIL 1b: preview changed the price'; end if;

  v := public.ai_purchase(pg_temp.bill(10, '{"ref": "90909090-5555-0000-0000-000000000001"}'), true);
  pid := (v ->> 'purchase_id')::uuid;
  g := pg_temp.ghee();
  if g.current_stock <> 16 then raise exception 'FAIL 1c: stock should be 5 + 10 + 1 free = 16, is %', g.current_stock; end if;
  if g.purchase_price <> 500 then raise exception 'FAIL 1d: free goods must not change the cost (500), is %', g.purchase_price; end if;
  if g.selling_price <> 660 or g.mrp <> 699 then
    raise exception 'FAIL 1e: new price 660 / MRP 699 not set: % / %', g.selling_price, g.mrp;
  end if;
  if (select count(*) from public.purchase_items where purchase_id = pid) <> 2 then
    raise exception 'FAIL 1f: expected a paid line and a free line';
  end if;

  -- 2. Change it: 8 bought (+1 free) instead of 10.
  v := public.ai_purchase(pg_temp.bill(8, jsonb_build_object('edit_purchase_id', pid)), false);
  if (v #>> '{summary,total}')::numeric <> 4480 or v #>> '{summary,editing_purchase}' is null then
    raise exception 'FAIL 2a: edit preview should be 4480: %', v -> 'summary';
  end if;
  if (pg_temp.ghee()).current_stock <> 16 then raise exception 'FAIL 2b: edit preview moved stock'; end if;
  v := public.ai_purchase(pg_temp.bill(8, jsonb_build_object('edit_purchase_id', pid)), true);
  if (select total from public.purchases where id = pid) <> 4480 or (pg_temp.ghee()).current_stock <> 14
     or (select due_amount from public.suppliers where id = '90909090-4444-0000-0000-000000000001') <> 4480 then
    raise exception 'FAIL 2c: edited purchase, stock or due wrong';
  end if;
  if (select count(*) from public.purchases where business_id = '90909090-1111-0000-0000-00000000000a') <> 1 then
    raise exception 'FAIL 2d: the edit made a second purchase';
  end if;

  -- 3. Send 2 back to Gupta: valued at this purchase's cost, off what is owed.
  v := public.ai_purchase_return(jsonb_build_object('purchase_id', pid, 'lines', jsonb_build_array(
         jsonb_build_object('product_id', '90909090-2222-0000-0000-000000000001', 'quantity', 2))), false);
  if (v #>> '{summary,return_value}')::numeric <> 995.56 then
    raise exception 'FAIL 3a: 2 of 9 (4480) = 995.56: %', v -> 'summary';
  end if;
  if (pg_temp.ghee()).current_stock <> 14 then raise exception 'FAIL 3b: return preview moved stock'; end if;
  v := public.ai_purchase_return(jsonb_build_object('purchase_id', pid, 'ref', '90909090-5555-0000-0000-000000000003',
         'lines', jsonb_build_array(jsonb_build_object('product_id', '90909090-2222-0000-0000-000000000001', 'quantity', 2))), true);
  if (pg_temp.ghee()).current_stock <> 12
     or (select due_amount from public.suppliers where id = '90909090-4444-0000-0000-000000000001') <> 3484.44 then
    raise exception 'FAIL 3c: stock 12 and due 3484.44 expected';
  end if;
  v := public.ai_purchase_return(jsonb_build_object('purchase_id', pid, 'ref', '90909090-5555-0000-0000-000000000003',
         'lines', jsonb_build_array(jsonb_build_object('product_id', '90909090-2222-0000-0000-000000000001', 'quantity', 2))), true);
  if not (v ->> 'already_saved')::boolean
     or (select count(*) from public.purchase_returns where purchase_id = pid) <> 1 then
    raise exception 'FAIL 3d: second confirm made another return';
  end if;

  -- 4. More than was bought, or changing a purchase with a return: refused.
  begin
    perform public.ai_purchase_return(jsonb_build_object('purchase_id', pid, 'lines', jsonb_build_array(
      jsonb_build_object('product_id', '90909090-2222-0000-0000-000000000001', 'quantity', 20))), false);
    raise exception 'FAIL 4a: returned more than was bought';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    perform public.ai_purchase(pg_temp.bill(5, jsonb_build_object('edit_purchase_id', pid)), true);
    raise exception 'FAIL 4b: a purchase with a return was changed';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
end $$;

-- 5. Staff without the purchases right can't send goods back.
do $$
declare pid uuid;
begin
  select id into pid from public.purchases where business_id = '90909090-1111-0000-0000-00000000000a';
  perform pg_temp.act('90909090-0000-0000-0000-0000000000a5');
  begin
    perform public.ai_purchase_return(jsonb_build_object('purchase_id', pid, 'lines', jsonb_build_array(
      jsonb_build_object('product_id', '90909090-2222-0000-0000-000000000001', 'quantity', 1))), false);
    raise exception 'FAIL 5: staff previewed a purchase return without the right';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
end $$;

-- 6. A new shoe in two sizes from one bill, then a new size later.
do $$
declare v jsonb; shoe uuid;
begin
  perform pg_temp.act('90909090-0000-0000-0000-00000000000a');
  v := public.ai_purchase(jsonb_build_object('supplier_id', '90909090-4444-0000-0000-000000000001',
         'ref', '90909090-5555-0000-0000-000000000006', 'lines', jsonb_build_array(
           jsonb_build_object('quantity', 2, 'rate', 300, 'gst_rate', 12, 'new_product',
             jsonb_build_object('name', 'AI PM Shoe', 'selling_price', 599, 'variant', 'Size 8')),
           jsonb_build_object('quantity', 1, 'rate', 320, 'gst_rate', 12, 'new_product',
             jsonb_build_object('name', 'AI PM Shoe', 'selling_price', 599, 'variant', 'Size 9',
                                'variant_selling_price', 649)))), true);
  select id into shoe from public.products where business_id = '90909090-1111-0000-0000-00000000000a' and name = 'AI PM Shoe';
  if (select count(*) from public.products where business_id = '90909090-1111-0000-0000-00000000000a' and name = 'AI PM Shoe') <> 1
     or not (select has_variants from public.products where id = shoe) then
    raise exception 'FAIL 6a: one shoe product with variants expected';
  end if;
  if (select current_stock from public.product_variants where product_id = shoe and name = 'Size 8') <> 2
     or (select selling_price from public.product_variants where product_id = shoe and name = 'Size 9') <> 649 then
    raise exception 'FAIL 6b: Size 8 stock 2 and Size 9 price 649 expected';
  end if;
  v := public.ai_purchase(jsonb_build_object('supplier_id', '90909090-4444-0000-0000-000000000001',
         'ref', '90909090-5555-0000-0000-000000000007', 'lines', jsonb_build_array(
           jsonb_build_object('product_id', shoe, 'quantity', 1, 'rate', 330, 'gst_rate', 12,
             'new_variant', jsonb_build_object('name', 'Size 10')))), true);
  if (select count(*) from public.product_variants where product_id = shoe) <> 3 then
    raise exception 'FAIL 6c: Size 10 not added';
  end if;
end $$;

-- 7. Split payment: 600 cash + 5000 UPI on a 5,600 bill; nothing more owed.
do $$
declare v jsonb; due numeric;
begin
  perform pg_temp.act('90909090-0000-0000-0000-00000000000a');
  due := (select due_amount from public.suppliers where id = '90909090-4444-0000-0000-000000000001');
  v := public.ai_purchase(jsonb_build_object('supplier_id', '90909090-4444-0000-0000-000000000001',
         'ref', '90909090-5555-0000-0000-000000000008',
         'payments', jsonb_build_array(jsonb_build_object('mode', 'cash', 'amount', 600),
                                       jsonb_build_object('mode', 'upi', 'amount', 5000)),
         'lines', jsonb_build_array(jsonb_build_object(
           'product_id', '90909090-2222-0000-0000-000000000001', 'quantity', 10, 'rate', 500, 'gst_rate', 12))), true);
  if (select paid_amount from public.purchases where id = (v ->> 'purchase_id')::uuid) <> 5600
     or (select due_amount from public.suppliers where id = '90909090-4444-0000-0000-000000000001') <> due
     or (select count(*) from public.supplier_payments where purchase_id = (v ->> 'purchase_id')::uuid) <> 2 then
    raise exception 'FAIL 7: split payment should pay 5600 in two payments';
  end if;
end $$;

-- 8. IMEI phones: bought with their numbers, sold by number, returned.
do $$
declare v jsonb; s jsonb; line uuid;
begin
  perform pg_temp.act('90909090-0000-0000-0000-00000000000a');
  begin
    perform public.ai_purchase(jsonb_build_object('supplier_id', '90909090-4444-0000-0000-000000000001',
      'lines', jsonb_build_array(jsonb_build_object('product_id', '90909090-2222-0000-0000-0000000000f0',
        'quantity', 2, 'rate', 8000, 'gst_rate', 18, 'serial_nos', jsonb_build_array('AIIMEI001')))), false);
    raise exception 'FAIL 8a: 2 phones with 1 IMEI accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  v := public.ai_purchase(jsonb_build_object('supplier_id', '90909090-4444-0000-0000-000000000001',
         'ref', '90909090-5555-0000-0000-000000000009', 'lines', jsonb_build_array(jsonb_build_object(
           'product_id', '90909090-2222-0000-0000-0000000000f0', 'quantity', 2, 'rate', 8000, 'gst_rate', 18,
           'serial_nos', jsonb_build_array('AIIMEI001', 'AIIMEI002')))), true);
  if (select count(*) from public.product_serials where business_id = '90909090-1111-0000-0000-00000000000a'
      and status = 'in_stock') <> 2 then
    raise exception 'FAIL 8b: 2 IMEIs should be in stock';
  end if;

  s := public.ai_create_sale(jsonb_build_object('sale_ref', '90909090-5555-0000-0000-00000000000a',
         'lines', jsonb_build_array(jsonb_build_object('product_id', '90909090-2222-0000-0000-0000000000f0',
           'quantity', 1, 'serial_nos', jsonb_build_array('AIIMEI001')))));
  if (select status from public.product_serials where serial_no = 'AIIMEI001'
      and business_id = '90909090-1111-0000-0000-00000000000a') <> 'sold' then
    raise exception 'FAIL 8c: AIIMEI001 should be sold';
  end if;
  begin
    perform public.ai_preview_sale(jsonb_build_object('lines', jsonb_build_array(jsonb_build_object(
      'product_id', '90909090-2222-0000-0000-0000000000f0', 'quantity', 1, 'serial_nos', jsonb_build_array('AIIMEI001')))));
    raise exception 'FAIL 8d: a sold IMEI sold again';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;

  select id into line from public.invoice_items where invoice_id = (s ->> 'bill_id')::uuid;
  v := public.ai_return(jsonb_build_object('bill_id', s ->> 'bill_id', 'ref', '90909090-5555-0000-0000-00000000000b',
         'lines', jsonb_build_array(jsonb_build_object('bill_line_id', line, 'quantity', 1))), true);
  if (select status from public.product_serials where serial_no = 'AIIMEI001'
      and business_id = '90909090-1111-0000-0000-00000000000a') <> 'in_stock' then
    raise exception 'FAIL 8e: the returned phone''s IMEI should be back in stock';
  end if;
end $$;

select 'ai_purchase_more tests passed' as result;

rollback;
