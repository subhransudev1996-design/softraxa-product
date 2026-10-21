-- ============================================================
-- Discount cards (migration 0083).
--
-- HOW TO RUN — on a STAGING copy, after 0083:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
--
-- A bookshop: Book ₹200 (category Books), Pen ₹50 (Stationery).
-- Gold card: 10% on Books only. Cashier B has default rights (no
-- discounts at all); clerk C may change prices (so may issue cards).
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('83838383-0000-0000-0000-00000000000f', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'card-owner@test.invalid'),
  ('83838383-0000-0000-0000-0000000000b5', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'card-cashier@test.invalid'),
  ('83838383-0000-0000-0000-0000000000c5', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'card-clerk@test.invalid');

insert into public.businesses (id, name, state_code, business_type) values
  ('83838383-1111-0000-0000-00000000000f', 'Card Book House', '21', 'book_store');
update public.profiles set business_id = '83838383-1111-0000-0000-00000000000f', role = 'owner'
  where id = '83838383-0000-0000-0000-00000000000f';
update public.profiles set business_id = '83838383-1111-0000-0000-00000000000f', role = 'staff'
  where id in ('83838383-0000-0000-0000-0000000000b5', '83838383-0000-0000-0000-0000000000c5');
insert into public.staff_permissions (profile_id, business_id, can_edit_prices, discount_limit_pct)
  values ('83838383-0000-0000-0000-0000000000c5', '83838383-1111-0000-0000-00000000000f', true, 0);

insert into public.plans (id, name, software_id, user_limit, included_features)
select '83838383-9999-0000-0000-000000000001', 'Card Three Users', id, 3, '[]'
from public.software_products where slug = 'dukania';
insert into public.subscriptions (business_id, plan_id, status, expiry_date) values
  ('83838383-1111-0000-0000-00000000000f', '83838383-9999-0000-0000-000000000001',
   'active', current_date + 30);

insert into public.categories (id, business_id, name) values
  ('83838383-4444-0000-0000-0000000000b0', '83838383-1111-0000-0000-00000000000f', 'Books'),
  ('83838383-4444-0000-0000-0000000000a0', '83838383-1111-0000-0000-00000000000f', 'Stationery');
insert into public.products (id, business_id, name, selling_price, purchase_price, gst_rate, category_id) values
  ('83838383-2222-0000-0000-0000000000b0', '83838383-1111-0000-0000-00000000000f',
   'Card Test Book', 200, 100, 0, '83838383-4444-0000-0000-0000000000b0'),
  ('83838383-2222-0000-0000-0000000000a0', '83838383-1111-0000-0000-00000000000f',
   'Card Test Pen', 50, 20, 0, '83838383-4444-0000-0000-0000000000a0');
insert into public.stock_movements (business_id, product_id, movement_type, quantity, note) values
  ('83838383-1111-0000-0000-00000000000f', '83838383-2222-0000-0000-0000000000b0', 'opening', 100, 'card test'),
  ('83838383-1111-0000-0000-00000000000f', '83838383-2222-0000-0000-0000000000a0', 'opening', 100, 'card test');

-- One-line cash bill: product, quantity × price, line discount, card.
create or replace function pg_temp.bill(p_product uuid, p_price numeric, p_disc numeric,
                                        p_card uuid, p_offline boolean default false)
returns uuid language sql as $$
  select (public.create_invoice(jsonb_build_object(
    'invoice_type', 'non_gst', 'customer_name', 'Walk-in',
    'paid_amount', p_price - p_disc, 'payment_mode', 'cash', 'discount_amount', 0,
    'discount_card_id', p_card, 'offline_created', p_offline,
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
  owner   constant uuid := '83838383-0000-0000-0000-00000000000f';
  cashier constant uuid := '83838383-0000-0000-0000-0000000000b5';
  clerk   constant uuid := '83838383-0000-0000-0000-0000000000c5';
  books   constant uuid := '83838383-4444-0000-0000-0000000000b0';
  stat    constant uuid := '83838383-4444-0000-0000-0000000000a0';
  book    constant uuid := '83838383-2222-0000-0000-0000000000b0';
  pen     constant uuid := '83838383-2222-0000-0000-0000000000a0';
  gold uuid; student uuid; card1 uuid; card2 uuid; old_card uuid; b uuid; v jsonb; r record;
begin
  -- 1. Card types: owner only.
  perform pg_temp.act(owner);
  gold := public.save_discount_card_type(null, jsonb_build_object(
    'name', 'Gold', 'discount_pct', 10, 'applies_to', 'only', 'category_ids', jsonb_build_array(books)));
  student := public.save_discount_card_type(null, jsonb_build_object(
    'name', 'Student', 'discount_pct', 5, 'applies_to', 'except', 'category_ids', jsonb_build_array(stat)));
  begin
    perform public.save_discount_card_type(null, jsonb_build_object(
      'name', 'Broken', 'discount_pct', 10, 'applies_to', 'only'));
    raise exception 'FAIL 1a: "only" with no categories accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform pg_temp.act(clerk);
  begin
    perform public.save_discount_card_type(null, jsonb_build_object('name', 'Silver', 'discount_pct', 5));
    raise exception 'FAIL 1b: staff made a card type';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 1 (card types: owner only, categories checked)';

  -- 2. Cards: staff who may change prices issue them; numbers are unique
  --    whatever the spacing; cashiers without price rights can't.
  card1 := public.save_discount_card(null, jsonb_build_object(
    'card_no', '2017 1234 1234 4109', 'card_type_id', gold, 'holder_name', 'R. Mohanty'));
  card2 := public.save_discount_card(null, jsonb_build_object(
    'card_no', '2017 1234 1234 5109', 'card_type_id', student));
  begin
    perform public.save_discount_card(null, jsonb_build_object(
      'card_no', '2017-1234-1234-4109', 'card_type_id', gold));
    raise exception 'FAIL 2a: the same card number added twice';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform pg_temp.act(cashier);
  begin
    perform public.save_discount_card(null, jsonb_build_object('card_no', '9999', 'card_type_id', gold));
    raise exception 'FAIL 2b: a cashier without price rights issued a card';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 2 (cards issued by the right people, numbers unique)';

  -- 3. Finding: full number in any spacing, or a unique ending.
  v := public.find_discount_card('20171234 1234-4109');
  if (v ->> 'id')::uuid is distinct from card1 or (v ->> 'discount_pct')::numeric <> 10
     or not (v ->> 'usable')::boolean then
    raise exception 'FAIL 3a: full number %', v;
  end if;
  if (public.find_discount_card('4109') ->> 'id')::uuid is distinct from card1 then
    raise exception 'FAIL 3b: ending 4109 not found';
  end if;
  begin
    perform public.find_discount_card('109');
    raise exception 'FAIL 3c: an ending shared by two cards picked one';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  if (public.find_discount_card('7777') ->> 'found')::boolean then
    raise exception 'FAIL 3d: an unknown card was found';
  end if;
  raise notice 'PASS 3 (found by number or unique ending; unknown = not found)';

  -- 4. Cashier with no discount rights: 10% off a Book with the Gold card.
  b := pg_temp.bill(book, 200, 20, card1);
  select * into r from public.invoices where id = b;
  if r.discount_card_id is distinct from card1 or r.discount_card_no <> '2017 1234 1234 4109'
     or r.discount_card_type <> 'Gold' or r.discount_card_pct <> 10 or r.discount_card_amount <> 20 then
    raise exception 'FAIL 4: bill card fields % % % % %', r.discount_card_id, r.discount_card_no,
      r.discount_card_type, r.discount_card_pct, r.discount_card_amount;
  end if;
  raise notice 'PASS 4 (card discount allowed and recorded on the bill)';

  -- 5. …not on a Pen (Gold covers Books only)…
  begin
    perform pg_temp.bill(pen, 50, 5, card1);
    raise exception 'FAIL 5: card discount given on an item it does not cover';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  -- 6. …not more than the card's 10%…
  begin
    perform pg_temp.bill(book, 200, 30, card1);
    raise exception 'FAIL 6: 15%% given on a 10%% card';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  -- 7. …and not without the card.
  begin
    perform pg_temp.bill(book, 200, 20, null);
    raise exception 'FAIL 7: 10%% given with no card and no rights';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 5-7 (only covered items, only the card %%, only with the card)';

  -- 8. Student card (5% on all but Stationery) on a Book: 10 off.
  b := pg_temp.bill(book, 200, 10, card2);
  if (select discount_card_amount from public.invoices where id = b) <> 10 then
    raise exception 'FAIL 8: student card amount';
  end if;
  raise notice 'PASS 8 ("all except" categories)';

  -- 9. Expired card: refused at the counter, but a bill made offline
  --    before it expired still syncs.
  perform pg_temp.act(clerk);
  old_card := public.save_discount_card(null, jsonb_build_object(
    'card_no', 'OLD-1001', 'card_type_id', gold, 'valid_until', current_date - 1));
  perform pg_temp.act(cashier);
  if (public.find_discount_card('OLD1001') ->> 'usable')::boolean then
    raise exception 'FAIL 9a: expired card shown as usable';
  end if;
  begin
    perform pg_temp.bill(book, 200, 20, old_card);
    raise exception 'FAIL 9b: expired card accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform pg_temp.bill(book, 200, 20, old_card, true);
  raise notice 'PASS 9 (expired cards refused; offline bills sync)';

  -- 10. The card fields can't be written directly, even by the owner:
  --     bills are written only through billing (0037), so nothing changes.
  --     (The guard behind that is checked as the database owner below.)
  perform pg_temp.act(owner);
  update public.invoices set discount_card_pct = 100 where id = b;
  if (select discount_card_pct from public.invoices where id = b) <> 5 then
    raise exception 'FAIL 10a: card fields written directly';
  end if;
  raise notice 'PASS 10a (shops can''t write a bill''s card fields)';

  -- 11. Editing a bill keeps its card when the edit doesn't mention it.
  b := pg_temp.bill(book, 200, 20, card1);
  perform public.update_invoice(b, jsonb_build_object(
    'invoice_type', 'non_gst', 'customer_name', 'Walk-in',
    'paid_amount', 360, 'payment_mode', 'cash', 'discount_amount', 0,
    'items', jsonb_build_array(jsonb_build_object(
      'product_id', book, 'product_name', 'x', 'quantity', 2, 'unit_price', 200,
      'discount_amount', 40, 'gst_rate', 0, 'tax_amount', 0, 'line_total', 360))));
  select * into r from public.invoices where id = b;
  if r.discount_card_id is distinct from card1 or r.discount_card_amount <> 40 then
    raise exception 'FAIL 11: card after edit % %', r.discount_card_id, r.discount_card_amount;
  end if;
  raise notice 'PASS 11 (an edit keeps the card)';

  -- 12. The management list shows use and discount given.
  v := public.get_discount_cards('4109');
  if jsonb_array_length(v -> 'cards') <> 1
     or (v -> 'cards' -> 0 ->> 'uses')::int <> 2
     or (v -> 'cards' -> 0 ->> 'discount_given')::numeric <> 60 then
    raise exception 'FAIL 12: list %', v -> 'cards';
  end if;
  raise notice 'PASS 12 (card list with uses and discount given)';
end $$;

reset role;

-- 10b. Even with access rules bypassed, only billing sets the card fields.
do $$
begin
  begin
    update public.invoices set discount_card_pct = 100
      where business_id = '83838383-1111-0000-0000-00000000000f';
    raise exception 'FAIL 10b: card fields written by a direct update';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 10b (the guard refuses direct writes)';
end $$;

do $$ begin raise notice 'ALL DISCOUNT CARD CHECKS PASSED — rolling back test data'; end $$;
rollback;
