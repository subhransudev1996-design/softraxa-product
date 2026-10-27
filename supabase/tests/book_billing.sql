-- ============================================================
-- Book store billing (migration 0094).
--
-- HOW TO RUN — on a STAGING copy, after 0094:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the last line shows "book_billing tests passed". The first
-- failed check stops the run with "FAIL …".
--
-- A bookshop: Book ₹200 (Penguin, category Books, regular discount
-- 10%), Pen ₹50 (Stationery, none). Privilege card: 10% on Books.
-- Cashier B has default rights (no discounts of their own).
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('94949494-0000-0000-0000-00000000000f', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'book-owner@test.invalid'),
  ('94949494-0000-0000-0000-0000000000b5', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'book-cashier@test.invalid');

insert into public.businesses (id, name, state_code, business_type) values
  ('94949494-1111-0000-0000-00000000000f', 'Regular Book House', '21', 'book_store');
update public.profiles set business_id = '94949494-1111-0000-0000-00000000000f', role = 'owner'
  where id = '94949494-0000-0000-0000-00000000000f';
update public.profiles set business_id = '94949494-1111-0000-0000-00000000000f', role = 'staff'
  where id = '94949494-0000-0000-0000-0000000000b5';

insert into public.plans (id, name, software_id, user_limit, included_features)
select '94949494-9999-0000-0000-000000000001', 'Book Two Users', id, 2, '[]'
from public.software_products where slug = 'dukania';
insert into public.subscriptions (business_id, plan_id, status, expiry_date) values
  ('94949494-1111-0000-0000-00000000000f', '94949494-9999-0000-0000-000000000001',
   'active', current_date + 30);

insert into public.categories (id, business_id, name) values
  ('94949494-4444-0000-0000-0000000000b0', '94949494-1111-0000-0000-00000000000f', 'Books'),
  ('94949494-4444-0000-0000-0000000000a0', '94949494-1111-0000-0000-00000000000f', 'Stationery');
insert into public.products (id, business_id, name, selling_price, purchase_price, gst_rate,
                             category_id, publisher, author) values
  ('94949494-2222-0000-0000-0000000000b0', '94949494-1111-0000-0000-00000000000f',
   'Regular Test Book', 200, 100, 0, '94949494-4444-0000-0000-0000000000b0', 'Penguin', 'R. K. Narayan'),
  ('94949494-2222-0000-0000-0000000000a0', '94949494-1111-0000-0000-00000000000f',
   'Regular Test Pen', 50, 20, 0, '94949494-4444-0000-0000-0000000000a0', '', '');
insert into public.stock_movements (business_id, product_id, movement_type, quantity, note) values
  ('94949494-1111-0000-0000-00000000000f', '94949494-2222-0000-0000-0000000000b0', 'opening', 100, 'book test'),
  ('94949494-1111-0000-0000-00000000000f', '94949494-2222-0000-0000-0000000000a0', 'opening', 100, 'book test');

-- One-line cash bill: product, price, line discount, card.
create or replace function pg_temp.bill(p_product uuid, p_price numeric, p_disc numeric, p_card uuid)
returns uuid language sql as $$
  select (public.create_invoice(jsonb_build_object(
    'invoice_type', 'non_gst', 'customer_name', 'Walk-in',
    'paid_amount', p_price - p_disc, 'payment_mode', 'cash', 'discount_amount', 0,
    'discount_card_id', p_card,
    'items', jsonb_build_array(jsonb_build_object(
      'product_id', p_product, 'product_name', 'x', 'quantity', 1, 'unit_price', p_price,
      'discount_amount', p_disc, 'gst_rate', 0, 'tax_amount', 0,
      'line_total', p_price - p_disc)))) ->> 'id')::uuid;
$$;

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

do $$
declare
  owner   constant uuid := '94949494-0000-0000-0000-00000000000f';
  cashier constant uuid := '94949494-0000-0000-0000-0000000000b5';
  biz     constant uuid := '94949494-1111-0000-0000-00000000000f';
  books   constant uuid := '94949494-4444-0000-0000-0000000000b0';
  book    constant uuid := '94949494-2222-0000-0000-0000000000b0';
  pen     constant uuid := '94949494-2222-0000-0000-0000000000a0';
  priv uuid; card uuid; b uuid; n integer; v jsonb;
begin
  -- 1. Regular discount in bulk: owner, by publisher; a cashier can't.
  perform pg_temp.act(owner);
  n := public.set_regular_discount(10, 'penguin', null);
  if n <> 1 or (select regular_discount_pct from public.products where id = book) <> 10 then
    raise exception 'FAIL 1a: by publisher changed % products', n;
  end if;
  if (select regular_discount_pct from public.products where id = pen) <> 0 then
    raise exception 'FAIL 1b: another publisher''s product changed';
  end if;
  v := public.product_publishers();
  if jsonb_array_length(v) <> 1 or v -> 0 ->> 'publisher' <> 'Penguin'
     or (v -> 0 ->> 'max_pct')::numeric <> 10 then
    raise exception 'FAIL 1c: publishers %', v;
  end if;
  begin
    perform public.set_regular_discount(100, '', null);
    raise exception 'FAIL 1d: 100%% accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform pg_temp.act(cashier);
  begin
    perform public.set_regular_discount(50, '', null);
    raise exception 'FAIL 1e: a cashier set a regular discount';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 1 (regular discount in bulk, owner only)';

  -- 2. A cashier with no discount rights may give the regular discount,
  --    and nothing more.
  b := pg_temp.bill(book, 200, 20, null);
  if b is null then raise exception 'FAIL 2a: regular discount refused'; end if;
  begin
    perform pg_temp.bill(book, 200, 30, null);
    raise exception 'FAIL 2b: more than the regular discount accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    perform pg_temp.bill(pen, 50, 5, null);
    raise exception 'FAIL 2c: a discount on an item with no regular discount accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 2 (regular discount allowed, not beyond)';

  -- 3. With the privilege card: its 10% comes off what is left after the
  --    regular discount: 200 - 20 = 180, card 18, line discount 38.
  perform pg_temp.act(owner);
  priv := public.save_discount_card_type(null, jsonb_build_object(
    'name', 'Privilege', 'discount_pct', 10, 'applies_to', 'only', 'category_ids', jsonb_build_array(books)));
  card := public.save_discount_card(null, jsonb_build_object(
    'card_no', '2017 1234 1234 0007', 'card_type_id', priv));
  perform pg_temp.act(cashier);
  b := pg_temp.bill(book, 200, 38, card);
  if (select discount_card_amount from public.invoices where id = b) <> 18 then
    raise exception 'FAIL 3a: card amount %', (select discount_card_amount from public.invoices where id = b);
  end if;
  begin
    perform pg_temp.bill(book, 200, 40, card);
    raise exception 'FAIL 3b: more than regular + card accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 3 (card on top of the regular discount)';

  -- 4. Card numbers in the shop's pattern.
  perform pg_temp.act(owner);
  update public.businesses set card_no_prefix = '2017-1234-1234-', card_no_digits = 4 where id = biz;
  if public.next_discount_card_no() <> '2017-1234-1234-0008' then
    raise exception 'FAIL 4a: next number %', public.next_discount_card_no();
  end if;
  perform public.save_discount_card(null, jsonb_build_object(
    'card_no', public.next_discount_card_no(), 'card_type_id', priv));
  if public.next_discount_card_no() <> '2017-1234-1234-0009' then
    raise exception 'FAIL 4b: after giving one %', public.next_discount_card_no();
  end if;
  update public.businesses set card_no_prefix = 'PC', card_no_digits = 3 where id = biz;
  if public.next_discount_card_no() <> 'PC001' then
    raise exception 'FAIL 4c: a new prefix starts at %', public.next_discount_card_no();
  end if;
  raise notice 'PASS 4 (next card number)';
end $$;

reset role;
select 'book_billing tests passed' as result;
rollback;
