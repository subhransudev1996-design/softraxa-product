-- ============================================================
-- Dukania AI phase 2: sales made through the AI assistant (migration 0087).
--
-- HOW TO RUN — on a STAGING copy, after 0087:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes with "ai_sales tests passed". The first
-- failed check stops the run with "FAIL …".
--
-- A GST kirana: Tea ₹118 incl. 18% GST (cost ₹90), Salt ₹50 at 0% that
-- cost ₹60 (so selling it is below cost). Owner O, cashier S (default
-- rights: no price changes), customer Ramesh.
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);
select set_config('request.headers', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('87878787-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'ai-sale-owner@test.invalid'),
  ('87878787-0000-0000-0000-0000000000a5', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'ai-sale-staff@test.invalid');

insert into public.businesses (id, name, state_code, business_type, tax_preference) values
  ('87878787-1111-0000-0000-00000000000a', 'AI Sale Kirana', '21', 'grocery', 'gst');
update public.profiles set business_id = '87878787-1111-0000-0000-00000000000a', role = 'owner'
  where id = '87878787-0000-0000-0000-00000000000a';
update public.profiles set business_id = '87878787-1111-0000-0000-00000000000a', role = 'staff'
  where id = '87878787-0000-0000-0000-0000000000a5';

insert into public.plans (id, name, software_id, user_limit, included_features)
select '87878787-9999-0000-0000-000000000001', 'AI Sale Plan', id, 3, '[]'
from public.software_products where slug = 'dukania';
insert into public.subscriptions (business_id, plan_id, status, expiry_date) values
  ('87878787-1111-0000-0000-00000000000a', '87878787-9999-0000-0000-000000000001',
   'active', current_date + 30);

insert into public.products (id, business_id, name, selling_price, purchase_price, gst_rate, hsn_code) values
  ('87878787-2222-0000-0000-000000000001', '87878787-1111-0000-0000-00000000000a',
   'AI Sale Tea', 118, 90, 18, '0902'),
  ('87878787-2222-0000-0000-000000000002', '87878787-1111-0000-0000-00000000000a',
   'AI Sale Salt', 50, 60, 0, '2501');
insert into public.stock_movements (business_id, product_id, movement_type, quantity, note) values
  ('87878787-1111-0000-0000-00000000000a', '87878787-2222-0000-0000-000000000001', 'opening', 100, 'ai test'),
  ('87878787-1111-0000-0000-00000000000a', '87878787-2222-0000-0000-000000000002', 'opening', 100, 'ai test');
-- Unlimited credit: a new customer otherwise gets the shop's default
-- limit (₹0 here), and the credit sale in test 6 would need the owner's OK.
insert into public.customers (id, business_id, name, phone, credit_unlimited) values
  ('87878787-3333-0000-0000-000000000001', '87878787-1111-0000-0000-00000000000a', 'AI Ramesh', '9000000001', true);

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

-- Two Tea, paid in cash.
create or replace function pg_temp.tea(p_ref text default null) returns jsonb language sql as $$
  select jsonb_build_object(
    'lines', jsonb_build_array(jsonb_build_object(
      'product_id', '87878787-2222-0000-0000-000000000001', 'quantity', 2)),
    'payment_mode', 'cash')
    || case when p_ref is null then '{}'::jsonb else jsonb_build_object('sale_ref', p_ref) end;
$$;

create or replace function pg_temp.bills() returns bigint language sql as $$
  select count(*) from public.invoices where business_id = '87878787-1111-0000-0000-00000000000a';
$$;

set local role authenticated;

-- 1. Preview: right totals, nothing saved.
do $$
declare v jsonb;
begin
  perform pg_temp.act('87878787-0000-0000-0000-00000000000a');
  v := public.ai_preview_sale(pg_temp.tea());
  if not (v ->> 'ok')::boolean then raise exception 'FAIL 1a: preview not ok: %', v; end if;
  if (v #>> '{summary,total}')::numeric <> 236 or (v #>> '{summary,due}')::numeric <> 0 then
    raise exception 'FAIL 1b: 2 x 118 paid should be 236, nothing due: %', v -> 'summary';
  end if;
  if jsonb_array_length(v -> 'warnings') <> 0 then raise exception 'FAIL 1c: no warnings expected: %', v; end if;
  if pg_temp.bills() <> 0 then raise exception 'FAIL 1d: a preview saved a bill'; end if;
end $$;

-- 2. The real sale, marked as made by the AI; GST split like the app.
select set_config('request.headers', '{"x-dukania-source": "ai"}', true);
do $$
declare v jsonb; i record;
begin
  perform pg_temp.act('87878787-0000-0000-0000-00000000000a');
  begin
    perform public.ai_create_sale(pg_temp.tea());
    raise exception 'FAIL 2a: a sale without a sale_ref was made';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;

  v := public.ai_create_sale(pg_temp.tea('87878787-5555-0000-0000-000000000001')
                             || '{"expected_total": 236}');
  select * into i from public.invoices where id = (v ->> 'bill_id')::uuid;
  if i.id is null or i.total <> 236 or i.tax_amount <> 36 or i.paid_amount <> 236 then
    raise exception 'FAIL 2b: bill wrong: %', to_jsonb(i);
  end if;
  if i.created_via <> 'ai' then raise exception 'FAIL 2c: bill not marked as made by the AI'; end if;
  if (select unit_price from public.invoice_items where invoice_id = i.id) <> 100 then
    raise exception 'FAIL 2d: unit price before GST should be 100';
  end if;
  if (select current_stock from public.products where id = '87878787-2222-0000-0000-000000000001') <> 98 then
    raise exception 'FAIL 2e: stock should be 98';
  end if;
  if not exists (select 1 from public.audit_logs where entity_id = i.id::text and source = 'ai') then
    raise exception 'FAIL 2f: audit log not marked as AI';
  end if;

  -- 3. Confirming twice gives the same bill, not a second one.
  v := public.ai_create_sale(pg_temp.tea('87878787-5555-0000-0000-000000000001'));
  if not (v ->> 'already_saved')::boolean or v ->> 'bill_no' <> i.invoice_no or pg_temp.bills() <> 1 then
    raise exception 'FAIL 3a: second confirm billed again: %', v;
  end if;
  v := public.ai_preview_sale(pg_temp.tea('87878787-5555-0000-0000-000000000001'));
  if not (v ->> 'already_saved')::boolean then raise exception 'FAIL 3b: preview of a saved sale: %', v; end if;

  -- 4. A changed total is refused.
  begin
    perform public.ai_create_sale(pg_temp.tea('87878787-5555-0000-0000-000000000002')
                                  || '{"expected_total": 200}');
    raise exception 'FAIL 4: sale made although the total changed';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
end $$;
select set_config('request.headers', '', true);

-- 5. Below cost: the owner sees the warning and must accept it.
do $$
declare v jsonb; p jsonb;
begin
  perform pg_temp.act('87878787-0000-0000-0000-00000000000a');
  p := jsonb_build_object('lines', jsonb_build_array(jsonb_build_object(
         'product_id', '87878787-2222-0000-0000-000000000002', 'quantity', 1)),
       'sale_ref', '87878787-5555-0000-0000-000000000005');
  v := public.ai_preview_sale(p);
  if v ->> 'needs' <> 'owner_ack' or v -> 'warnings' -> 0 ->> 'kind' <> 'below_cost' then
    raise exception 'FAIL 5a: below-cost warning for the owner, got %', v;
  end if;
  begin
    perform public.ai_create_sale(p);
    raise exception 'FAIL 5b: below-cost sale made without the owner accepting';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  v := public.ai_create_sale(p || '{"owner_ack": true}');
  if (select exception_status from public.invoices where id = (v ->> 'bill_id')::uuid) <> 'acknowledged' then
    raise exception 'FAIL 5c: accepted sale not marked acknowledged';
  end if;
  if (select created_via from public.invoices where id = (v ->> 'bill_id')::uuid) <> 'app' then
    raise exception 'FAIL 5d: without the header a bill is from the app';
  end if;
end $$;

-- 6. Credit: needs a customer, and adds to what they owe.
do $$
declare v jsonb;
begin
  perform pg_temp.act('87878787-0000-0000-0000-00000000000a');
  begin
    perform public.ai_preview_sale(pg_temp.tea() || '{"paid": "none"}');
    raise exception 'FAIL 6a: credit sale without a customer accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  v := public.ai_create_sale(pg_temp.tea('87878787-5555-0000-0000-000000000006')
       || '{"paid": "none", "customer_id": "87878787-3333-0000-0000-000000000001"}');
  if (select due_amount from public.customers where id = '87878787-3333-0000-0000-000000000001') <> 236 then
    raise exception 'FAIL 6b: Ramesh should owe 236';
  end if;
  if (select payment_status::text from public.invoices where id = (v ->> 'bill_id')::uuid) <> 'unpaid' then
    raise exception 'FAIL 6c: credit bill should be unpaid';
  end if;
end $$;

-- 7. Staff: a lower price needs the owner's approval; never a bill.
do $$
declare v jsonb; n bigint := pg_temp.bills();
begin
  perform pg_temp.act('87878787-0000-0000-0000-0000000000a5');
  v := public.ai_preview_sale(jsonb_build_object('lines', jsonb_build_array(jsonb_build_object(
         'product_id', '87878787-2222-0000-0000-000000000001', 'quantity', 1, 'price', 100))));
  if (v ->> 'ok')::boolean then raise exception 'FAIL 7a: staff price cut previewed as fine: %', v; end if;
  if coalesce(v ->> 'needs', '') <> 'owner_approval' and v ->> 'error' is null then
    raise exception 'FAIL 7b: staff price cut should need approval or fail: %', v;
  end if;
  if v::text like '%"cost"%' then raise exception 'FAIL 7c: staff saw cost in warnings'; end if;
  v := public.ai_preview_sale(pg_temp.tea());
  if not (v ->> 'ok')::boolean then raise exception 'FAIL 7d: staff normal sale refused: %', v; end if;
  if pg_temp.bills() <> n then raise exception 'FAIL 7e: staff preview saved a bill'; end if;
end $$;

-- 8. Bad input is explained.
do $$
begin
  perform pg_temp.act('87878787-0000-0000-0000-00000000000a');
  begin
    perform public.ai_preview_sale('{"lines": []}');
    raise exception 'FAIL 8a: empty sale accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    perform public.ai_preview_sale(jsonb_build_object('lines', jsonb_build_array(jsonb_build_object(
      'product_id', '87878787-2222-0000-0000-000000000001', 'quantity', 0))));
    raise exception 'FAIL 8b: zero quantity accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
end $$;

select 'ai_sales tests passed' as result;

rollback;
