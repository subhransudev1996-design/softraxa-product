-- ============================================================
-- An exchanged item at the price the customer paid (migration 0077).
--
-- HOW TO RUN — on a STAGING copy, after 0077:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
--
-- Prices are set once, up front (the shop's price changes are not part
-- of what's tested):
--   kurta A  today ₹500 — sold earlier at ₹450 (price was lower then)
--   kurta B  today ₹450 — sold earlier at ₹500 (price was higher then)
--   dupatta  today ₹500
-- The staff member may handle returns and make bills but can't change
-- prices (no discount at all).
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('77777777-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'xo-owner@test.invalid'),
  ('77777777-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'xo-staff@test.invalid');
insert into public.businesses (id, name, state_code) values
  ('77777777-1111-0000-0000-00000000000a', 'XO Fashion', '21');
update public.profiles set business_id = '77777777-1111-0000-0000-00000000000a', role = 'owner'
  where id = '77777777-0000-0000-0000-00000000000a';
update public.profiles set business_id = '77777777-1111-0000-0000-00000000000a', role = 'staff'
  where id = '77777777-0000-0000-0000-0000000000a1';
insert into public.staff_permissions
  (profile_id, business_id, can_create_invoice, can_manage_returns, can_edit_prices,
   discount_limit_pct)
  values ('77777777-0000-0000-0000-0000000000a1', '77777777-1111-0000-0000-00000000000a',
          true, true, false, 0);
-- A 2-user plan, so the staff login counts (user limit, 0058).
insert into public.plans (id, name, software_id, user_limit, included_features)
select '77777777-9999-0000-0000-00000000000a', 'XO Two Users', id, 2, '[]'
from public.software_products where slug = 'dukania';
insert into public.subscriptions (business_id, plan_id, status, expiry_date) values
  ('77777777-1111-0000-0000-00000000000a', '77777777-9999-0000-0000-00000000000a',
   'active', current_date + 30);

insert into public.products (id, business_id, name, selling_price, purchase_price, gst_rate) values
  ('77777777-2222-0000-0000-00000000000a', '77777777-1111-0000-0000-00000000000a',
   'XO Kurta A', 500, 300, 0),
  ('77777777-2222-0000-0000-00000000000c', '77777777-1111-0000-0000-00000000000a',
   'XO Kurta B', 450, 300, 0),
  ('77777777-2222-0000-0000-00000000000b', '77777777-1111-0000-0000-00000000000a',
   'XO Dupatta', 500, 300, 0);
insert into public.stock_movements (business_id, product_id, movement_type, quantity, note) values
  ('77777777-1111-0000-0000-00000000000a', '77777777-2222-0000-0000-00000000000a', 'opening', 20, 'test'),
  ('77777777-1111-0000-0000-00000000000a', '77777777-2222-0000-0000-00000000000c', 'opening', 20, 'test'),
  ('77777777-1111-0000-0000-00000000000a', '77777777-2222-0000-0000-00000000000b', 'opening', 20, 'test');

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

-- A walk-in bill of one product at a price, paid in cash.
create or replace function pg_temp.sale(p_product uuid, p_price numeric, p_paid numeric)
returns jsonb language sql as $$
  select jsonb_build_object('invoice_type', 'non_gst', 'paid_amount', p_paid,
    'payment_mode', 'cash',
    'items', jsonb_build_array(jsonb_build_object(
      'product_id', p_product, 'product_name', 'x', 'quantity', 1,
      'unit_price', p_price, 'gst_rate', 0, 'tax_amount', 0, 'line_total', p_price)));
$$;

-- Exchange: product p_back from bill p_bill comes back, p_sale replaces it.
create or replace function pg_temp.swap(p_bill uuid, p_back uuid, p_sale jsonb)
returns jsonb language sql as $$
  select public.create_exchange(jsonb_build_object('request_id', gen_random_uuid(),
    'return', jsonb_build_object('invoice_id', p_bill, 'items', jsonb_build_array(
      jsonb_build_object('product_id', p_back,
        'product_name', 'XO Kurta', 'quantity', 1, 'condition', 'sellable'))),
    'sale', p_sale));
$$;

set local role authenticated;

do $$
declare
  owner   constant uuid := '77777777-0000-0000-0000-00000000000a';
  staff   constant uuid := '77777777-0000-0000-0000-0000000000a1';
  kurta_a constant uuid := '77777777-2222-0000-0000-00000000000a';
  kurta_b constant uuid := '77777777-2222-0000-0000-00000000000c';
  dupatta constant uuid := '77777777-2222-0000-0000-00000000000b';
  b uuid; v jsonb; err text;
begin
  -- 1. Without an exchange, staff can't sell kurta A below today's 500.
  perform pg_temp.act(staff);
  err := '';
  begin perform public.create_invoice(pg_temp.sale(kurta_a, 450, 450));
  exception when others then err := sqlerrm; end;
  if err not like '%below the default prices%' then
    raise exception 'FAIL 1: staff sold kurta A at 450 (error: "%")', err;
  end if;
  raise notice 'PASS 1 (an ordinary bill keeps to today''s price)';

  -- 2. Kurta A was sold at 450. Exchanged for kurta A again at the 450
  --    paid: an even swap, allowed, no reduction.
  perform pg_temp.act(owner);
  b := (public.create_invoice(pg_temp.sale(kurta_a, 450, 450)) ->> 'id')::uuid;
  perform pg_temp.act(staff);
  begin v := pg_temp.swap(b, kurta_a, pg_temp.sale(kurta_a, 450, 0));
  exception when others then raise exception 'FAIL 2: exchange refused: %', sqlerrm; end;
  if (v ->> 'credit_used')::numeric <> 450
     or (select price_reduction from public.invoices where id = (v ->> 'invoice_id')::uuid) <> 0
     or (select price_source from public.invoice_items
          where invoice_id = (v ->> 'invoice_id')::uuid) <> 'exchange' then
    raise exception 'FAIL 2: %', v;
  end if;
  raise notice 'PASS 2 (same product at the price paid, no reduction)';

  -- 3. Kurta B was sold at 500, today 450: today's (the lower) is the
  --    default, no reduction, the 50 left refunded.
  perform pg_temp.act(owner);
  b := (public.create_invoice(pg_temp.sale(kurta_b, 500, 500)) ->> 'id')::uuid;
  perform pg_temp.act(staff);
  begin v := pg_temp.swap(b, kurta_b, pg_temp.sale(kurta_b, 450, 0));
  exception when others then raise exception 'FAIL 3: exchange refused: %', sqlerrm; end;
  if (select price_reduction from public.invoices where id = (v ->> 'invoice_id')::uuid) <> 0
     or (v ->> 'refund')::numeric <> 50 then
    raise exception 'FAIL 3: %', v;
  end if;
  raise notice 'PASS 3 (cheaper today: today''s price, the 50 left refunded)';

  -- 4. Another product gets no old price: kurta A back (paid 450), the
  --    dupatta at 450 is still below its 500.
  perform pg_temp.act(owner);
  b := (public.create_invoice(pg_temp.sale(kurta_a, 450, 450)) ->> 'id')::uuid;
  perform pg_temp.act(staff);
  err := '';
  begin perform pg_temp.swap(b, kurta_a, pg_temp.sale(dupatta, 450, 0));
  exception when others then err := sqlerrm; end;
  if err not like '%below the default prices%' then
    raise exception 'FAIL 4: another product took the old price (error: "%")', err;
  end if;
  raise notice 'PASS 4 (only the product coming back)';

  -- 5. The setting is cleared after the exchange.
  if coalesce(current_setting('app.exchange_return', true), '') <> '' then
    raise exception 'FAIL 5: app.exchange_return left set';
  end if;
  raise notice 'PASS 5 (nothing left behind for the next bill)';
end $$;

rollback;
