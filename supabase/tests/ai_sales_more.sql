-- ============================================================
-- Dukania AI: cards, offers, split payments, quotations, bill edits
-- (migration 0089).
--
-- HOW TO RUN — on a STAGING copy, after 0087, 0088 and 0089:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes with "ai_sales_more tests passed". The first
-- failed check stops the run with "FAIL …".
--
-- A book shop (no GST on these items): Book ₹200 (Books), Pen ₹50
-- (Stationery). Gold card: 10% on Books only. Coupon DIWALI10: 10% off,
-- at most ₹30, on bills of ₹100 or more. Scratch & Win: ₹20 or ₹50.
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);
select set_config('request.headers', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('89898989-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'ai-more-owner@test.invalid');
insert into public.businesses (id, name, state_code, business_type, tax_preference) values
  ('89898989-1111-0000-0000-00000000000a', 'AI Book House', '21', 'book_store', 'gst');
update public.profiles set business_id = '89898989-1111-0000-0000-00000000000a', role = 'owner'
  where id = '89898989-0000-0000-0000-00000000000a';
insert into public.plans (id, name, software_id, user_limit, included_features)
select '89898989-9999-0000-0000-000000000001', 'AI More Plan', id, 3, '[]'
from public.software_products where slug = 'dukania';
insert into public.subscriptions (business_id, plan_id, status, expiry_date) values
  ('89898989-1111-0000-0000-00000000000a', '89898989-9999-0000-0000-000000000001',
   'active', current_date + 30);

insert into public.categories (id, business_id, name) values
  ('89898989-4444-0000-0000-0000000000b0', '89898989-1111-0000-0000-00000000000a', 'Books'),
  ('89898989-4444-0000-0000-0000000000a0', '89898989-1111-0000-0000-00000000000a', 'Stationery');
insert into public.products (id, business_id, name, selling_price, purchase_price, gst_rate, category_id) values
  ('89898989-2222-0000-0000-0000000000b0', '89898989-1111-0000-0000-00000000000a',
   'AI Test Book', 200, 100, 0, '89898989-4444-0000-0000-0000000000b0'),
  ('89898989-2222-0000-0000-0000000000a0', '89898989-1111-0000-0000-00000000000a',
   'AI Test Pen', 50, 20, 0, '89898989-4444-0000-0000-0000000000a0');
insert into public.stock_movements (business_id, product_id, movement_type, quantity, note) values
  ('89898989-1111-0000-0000-00000000000a', '89898989-2222-0000-0000-0000000000b0', 'opening', 50, 'ai test'),
  ('89898989-1111-0000-0000-00000000000a', '89898989-2222-0000-0000-0000000000a0', 'opening', 50, 'ai test');

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
-- 1 Book + 2 Pens = ₹300.
create or replace function pg_temp.sale(p_extra jsonb default '{}') returns jsonb language sql as $$
  select jsonb_build_object('lines', jsonb_build_array(
      jsonb_build_object('product_id', '89898989-2222-0000-0000-0000000000b0', 'quantity', 1),
      jsonb_build_object('product_id', '89898989-2222-0000-0000-0000000000a0', 'quantity', 2))) || p_extra;
$$;
create or replace function pg_temp.stock(p uuid) returns numeric language sql as $$
  select current_stock from public.products where id = p;
$$;

set local role authenticated;

-- The owner sets up the card and offers the way the app does.
do $$
declare t uuid;
begin
  perform pg_temp.act('89898989-0000-0000-0000-00000000000a');
  t := public.save_discount_card_type(null, jsonb_build_object('name', 'Gold', 'discount_pct', 10,
         'applies_to', 'only', 'category_ids', jsonb_build_array('89898989-4444-0000-0000-0000000000b0')));
  perform public.save_discount_card(null, jsonb_build_object('card_no', '2017 1234 1234 9907', 'card_type_id', t));
  perform public.save_offer(null, jsonb_build_object('name', 'Diwali', 'kind', 'percent', 'percent', 10,
         'max_discount', 30, 'min_bill', 100, 'code_mode', 'shared', 'shared_code', 'DIWALI10'));
  perform public.save_offer(null, jsonb_build_object('name', 'Scratch & Win', 'kind', 'amount',
         'amounts', jsonb_build_array(20, 50)));
end $$;

-- 1. Gold card by its last digits: 10% off the book only.
do $$
declare v jsonb; b record;
begin
  perform pg_temp.act('89898989-0000-0000-0000-00000000000a');
  v := public.ai_preview_sale(pg_temp.sale('{"card": "9907"}'));
  if not (v ->> 'ok')::boolean or (v #>> '{summary,total}')::numeric <> 280
     or (v #>> '{summary,discount_card,discount}')::numeric <> 20 then
    raise exception 'FAIL 1a: card should take 20 off the book (300 → 280): %', v;
  end if;
  v := public.ai_create_sale(pg_temp.sale('{"card": "9907", "sale_ref": "89898989-5555-0000-0000-000000000001"}'));
  select * into b from public.invoices where id = (v ->> 'bill_id')::uuid;
  if b.total <> 280 or b.discount_card_no <> '2017 1234 1234 9907' then
    raise exception 'FAIL 1b: bill should carry the card and total 280: %', to_jsonb(b);
  end if;
end $$;

-- 2. Coupon DIWALI10: 10% capped at ₹30; under ₹100 refused.
do $$
declare v jsonb; b record;
begin
  perform pg_temp.act('89898989-0000-0000-0000-00000000000a');
  v := public.ai_create_sale(pg_temp.sale('{"offer_code": "diwali10", "sale_ref": "89898989-5555-0000-0000-000000000002"}'));
  select * into b from public.invoices where id = (v ->> 'bill_id')::uuid;
  if b.total <> 270 or b.offer_amount <> 30 or b.offer_name <> 'Diwali' then
    raise exception 'FAIL 2a: 10%% of 300 capped at 30 → 270: %', to_jsonb(b);
  end if;
  begin
    perform public.ai_preview_sale(jsonb_build_object('lines', jsonb_build_array(jsonb_build_object(
      'product_id', '89898989-2222-0000-0000-0000000000a0', 'quantity', 1)), 'offer_code', 'DIWALI10'));
    raise exception 'FAIL 2b: coupon accepted on a ₹50 bill';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
end $$;

-- 3. Scratch card: the prize must be said; ₹50 then.
do $$
declare v jsonb; o uuid; b record;
begin
  perform pg_temp.act('89898989-0000-0000-0000-00000000000a');
  select id into o from public.offers where business_id = '89898989-1111-0000-0000-00000000000a' and name = 'Scratch & Win';
  begin
    perform public.ai_preview_sale(pg_temp.sale(jsonb_build_object('offer_id', o)));
    raise exception 'FAIL 3a: scratch offer without its prize accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  v := public.ai_create_sale(pg_temp.sale(jsonb_build_object('offer_id', o, 'offer_amount', 50,
         'sale_ref', '89898989-5555-0000-0000-000000000003')));
  select * into b from public.invoices where id = (v ->> 'bill_id')::uuid;
  if b.total <> 250 or b.offer_amount <> 50 then raise exception 'FAIL 3b: 300 − 50 = 250: %', to_jsonb(b); end if;
end $$;

-- 4. Split payment: ₹100 cash + ₹200 UPI.
do $$
declare v jsonb;
begin
  perform pg_temp.act('89898989-0000-0000-0000-00000000000a');
  v := public.ai_create_sale(pg_temp.sale('{"payments": [{"mode": "cash", "amount": 100}, {"mode": "upi", "amount": 200}],
                                            "sale_ref": "89898989-5555-0000-0000-000000000004"}'));
  if (select count(*) from public.invoice_payments where invoice_id = (v ->> 'bill_id')::uuid) <> 2
     or (select paid_amount from public.invoices where id = (v ->> 'bill_id')::uuid) <> 300 then
    raise exception 'FAIL 4: two payments totalling 300 expected';
  end if;
end $$;

-- 5. A quotation moves no stock and takes no money; a cash memo is CM.
do $$
declare v jsonb; s numeric := pg_temp.stock('89898989-2222-0000-0000-0000000000b0');
begin
  perform pg_temp.act('89898989-0000-0000-0000-00000000000a');
  v := public.ai_create_sale(pg_temp.sale('{"bill_type": "estimate", "sale_ref": "89898989-5555-0000-0000-000000000005"}'));
  if (select invoice_type::text from public.invoices where id = (v ->> 'bill_id')::uuid) <> 'estimate'
     or pg_temp.stock('89898989-2222-0000-0000-0000000000b0') <> s then
    raise exception 'FAIL 5a: quotation saved wrong or moved stock';
  end if;
  v := public.ai_create_sale(pg_temp.sale('{"bill_type": "cash_memo", "sale_ref": "89898989-5555-0000-0000-000000000006"}'));
  if (select invoice_type::text from public.invoices where id = (v ->> 'bill_id')::uuid) <> 'cash_memo' then
    raise exception 'FAIL 5b: cash memo not saved as one';
  end if;
end $$;

-- 6. Edit the card bill (test 1): 2 books now; card stays, payment stays.
do $$
declare v jsonb; v_id uuid; b record;
begin
  perform pg_temp.act('89898989-0000-0000-0000-00000000000a');
  select i.id into v_id from public.invoices i where i.local_id = '89898989-5555-0000-0000-000000000001';
  v := public.ai_preview_sale(jsonb_build_object('edit_bill_id', v_id, 'lines', jsonb_build_array(
         jsonb_build_object('product_id', '89898989-2222-0000-0000-0000000000b0', 'quantity', 2),
         jsonb_build_object('product_id', '89898989-2222-0000-0000-0000000000a0', 'quantity', 2))));
  if not (v ->> 'ok')::boolean or (v #>> '{summary,total}')::numeric <> 460 then
    raise exception 'FAIL 6a: 2 books with card (360) + 2 pens (100) = 460: %', v;
  end if;
  if (select total from public.invoices where invoices.id = v_id) <> 280 then
    raise exception 'FAIL 6b: the edit preview changed the bill';
  end if;
  v := public.ai_create_sale(jsonb_build_object('edit_bill_id', v_id, 'expected_total', 460, 'lines', jsonb_build_array(
         jsonb_build_object('product_id', '89898989-2222-0000-0000-0000000000b0', 'quantity', 2),
         jsonb_build_object('product_id', '89898989-2222-0000-0000-0000000000a0', 'quantity', 2))));
  select * into b from public.invoices where invoices.id = v_id;
  if b.total <> 460 or b.paid_amount <> 280 or b.discount_card_id is null then
    raise exception 'FAIL 6c: edited bill wrong: %', to_jsonb(b);
  end if;

  -- 7. Edit the coupon bill: drop the offer.
  select i.id into v_id from public.invoices i where i.local_id = '89898989-5555-0000-0000-000000000002';
  v := public.ai_create_sale(pg_temp.sale(jsonb_build_object('edit_bill_id', v_id, 'offer_code', 'none')));
  select * into b from public.invoices where invoices.id = v_id;
  if b.total <> 300 or b.offer_id is not null then
    raise exception 'FAIL 7: offer not removed in the edit: %', to_jsonb(b);
  end if;
end $$;

select 'ai_sales_more tests passed' as result;

rollback;
