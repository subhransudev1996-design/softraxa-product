-- ============================================================
-- GST returns the portal accepts (migration 0079): nil-rated lines in
-- Table 8, bills of supply and cash memos reported, untaxed sales
-- flagged, HSN summary without negative quantities, documents per
-- series, GSTR-3B 3.1(c), composition return.
--
-- HOW TO RUN — on a STAGING copy, after 0079:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
--
-- Shop: Maharashtra (27). Today's bills (all values before GST):
--   1 tax invoice, local walk-in : Phone ₹100 @18%, Rice 2 × ₹50 (nil)
--   2 tax invoice, Karnataka B2B : Phone 2 × ₹100 @18%, Rice ₹50 (nil)
--   3 bill of supply, walk-in    : Soap ₹59 (an 18% product, no GST), Rice ₹50
--   4 cash memo, walk-in         : Rice ₹50
--   Returns today: 1 Phone of bill 2 (credit note), Rice of bill 4, and a
--   Lamp ₹50 @18% sold two days ago (credit note).
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('79797979-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'gf-owner@test.invalid');
insert into public.businesses (id, name, state_code, gst_number, turnover_band) values
  ('79797979-1111-0000-0000-00000000000a', 'GF Shop', '27', '27AAPFU0939F1ZV', 'up_to_5cr');
update public.profiles set business_id = '79797979-1111-0000-0000-00000000000a', role = 'owner'
  where id = '79797979-0000-0000-0000-00000000000a';
insert into public.plans (id, name, software_id, user_limit, included_features)
select '79797979-9999-0000-0000-00000000000a', 'GF Plan', id, 2, '[]'
from public.software_products where slug = 'dukania';
insert into public.subscriptions (business_id, plan_id, status, expiry_date) values
  ('79797979-1111-0000-0000-00000000000a', '79797979-9999-0000-0000-00000000000a',
   'active', current_date + 30);

insert into public.products (id, business_id, name, selling_price, purchase_price, gst_rate, hsn_code, gst_category) values
  ('79797979-2222-0000-0000-0000000000a1', '79797979-1111-0000-0000-00000000000a', 'GF Phone', 118, 80, 18, '8517', 'taxable'),
  ('79797979-2222-0000-0000-0000000000a2', '79797979-1111-0000-0000-00000000000a', 'GF Rice', 50, 40, 0, '1006', 'nil'),
  ('79797979-2222-0000-0000-0000000000a3', '79797979-1111-0000-0000-00000000000a', 'GF Soap', 59, 40, 18, '3401', 'taxable'),
  ('79797979-2222-0000-0000-0000000000a4', '79797979-1111-0000-0000-00000000000a', 'GF Lamp', 59, 40, 18, '9405', 'taxable');
insert into public.stock_movements (business_id, product_id, movement_type, quantity, note)
select '79797979-1111-0000-0000-00000000000a', id, 'opening', 50, 'gf test'
from public.products where business_id = '79797979-1111-0000-0000-00000000000a';

insert into public.customers (id, business_id, name, gst_number, state_code, credit_unlimited) values
  ('79797979-3333-0000-0000-0000000000b2', '79797979-1111-0000-0000-00000000000a',
   'GF Karnataka Traders', '29AAPFU0939F1ZR', '29', true),
  ('79797979-3333-0000-0000-0000000000c2', '79797979-1111-0000-0000-00000000000a',
   'GF Walk-in', '', '27', true);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"79797979-0000-0000-0000-00000000000a","role":"authenticated"}', true);

-- A bill line: product, quantity, price before GST, rate.
create or replace function pg_temp.line(p_product uuid, p_name text, p_hsn text,
  p_qty numeric, p_price numeric, p_rate numeric)
returns jsonb language sql as $$
  select jsonb_build_object('product_id', p_product, 'product_name', p_name, 'hsn_code', p_hsn,
    'quantity', p_qty, 'unit_price', p_price, 'gst_rate', p_rate,
    'tax_amount', round(p_qty * p_price * p_rate / 100, 2),
    'line_total', round(p_qty * p_price * (1 + p_rate / 100), 2));
$$;

create or replace function pg_temp.bill(p_type text, p_customer uuid, p_items jsonb,
  p_date timestamptz default null)
returns uuid language sql as $$
  select (public.create_invoice(jsonb_build_object(
    'invoice_type', p_type, 'customer_id', p_customer, 'customer_name', 'x',
    'paid_amount', (select sum((i ->> 'line_total')::numeric) from jsonb_array_elements(p_items) i),
    'payment_mode', 'cash', 'items', p_items)
    || case when p_date is null then '{}'::jsonb
            else jsonb_build_object('invoice_date', p_date) end) ->> 'id')::uuid;
$$;

do $$
declare
  phone  constant uuid := '79797979-2222-0000-0000-0000000000a1';
  rice   constant uuid := '79797979-2222-0000-0000-0000000000a2';
  soap   constant uuid := '79797979-2222-0000-0000-0000000000a3';
  lamp   constant uuid := '79797979-2222-0000-0000-0000000000a4';
  b2b    constant uuid := '79797979-3333-0000-0000-0000000000b2';
  walkin constant uuid := '79797979-3333-0000-0000-0000000000c2';
  v_b2b  uuid;
  v_bos  uuid;
  v_cm   uuid;
  v_old  uuid;
  v_g1   jsonb;
  v_g3   jsonb;
  v_c    jsonb;
  v_today date := public.ist_date(now());
  v_n    numeric;
begin
  perform pg_temp.bill('gst', walkin, jsonb_build_array(
    pg_temp.line(phone, 'GF Phone', '8517', 1, 100, 18),
    pg_temp.line(rice, 'GF Rice', '1006', 2, 50, 0)));
  v_b2b := pg_temp.bill('gst', b2b, jsonb_build_array(
    pg_temp.line(phone, 'GF Phone', '8517', 2, 100, 18),
    pg_temp.line(rice, 'GF Rice', '1006', 1, 50, 0)));
  v_bos := pg_temp.bill('non_gst', walkin, jsonb_build_array(
    pg_temp.line(soap, 'GF Soap', '3401', 1, 59, 0),
    pg_temp.line(rice, 'GF Rice', '1006', 1, 50, 0)));
  v_cm := pg_temp.bill('cash_memo', walkin, jsonb_build_array(
    pg_temp.line(rice, 'GF Rice', '1006', 1, 50, 0)));
  v_old := pg_temp.bill('gst', walkin, jsonb_build_array(
    pg_temp.line(lamp, 'GF Lamp', '9405', 1, 50, 18)), now() - interval '2 days');

  -- 1. Each line keeps its GST type.
  if (select gst_category from public.invoice_items where invoice_id = v_bos and product_id = soap) <> 'untaxed'
     or (select gst_category from public.invoice_items where invoice_id = v_bos and product_id = rice) <> 'nil'
     or (select gst_category from public.invoice_items where invoice_id = v_b2b and product_id = phone) <> 'taxable' then
    raise exception 'FAIL 1: line GST types %',
      (select jsonb_agg(jsonb_build_object('p', product_name, 'c', gst_category))
       from public.invoice_items where invoice_id in (v_bos, v_b2b));
  end if;

  perform public.create_sale_return(jsonb_build_object(
    'invoice_id', v_b2b, 'refund_amount', 118, 'refund_mode', 'cash',
    'items', jsonb_build_array(jsonb_build_object('product_id', phone, 'product_name', 'GF Phone', 'quantity', 1))));
  perform public.create_sale_return(jsonb_build_object(
    'invoice_id', v_cm, 'refund_amount', 50, 'refund_mode', 'cash',
    'items', jsonb_build_array(jsonb_build_object('product_id', rice, 'product_name', 'GF Rice', 'quantity', 1))));
  perform public.create_sale_return(jsonb_build_object(
    'invoice_id', v_old, 'refund_amount', 59, 'refund_mode', 'cash',
    'items', jsonb_build_array(jsonb_build_object('product_id', lamp, 'product_name', 'GF Lamp', 'quantity', 1))));

  v_g1 := public.get_gstr1(v_today, v_today);

  -- 2. B2B: only the taxed line, inter-state.
  if jsonb_array_length(v_g1 -> 'b2b') <> 1 or (v_g1 -> 'b2b' -> 0 ->> 'gst_rate')::numeric <> 18
     or (v_g1 -> 'b2b' -> 0 ->> 'taxable_value')::numeric <> 200
     or not (v_g1 -> 'b2b' -> 0 ->> 'inter')::boolean then
    raise exception 'FAIL 2: B2B %', v_g1 -> 'b2b';
  end if;

  -- 3. B2C small at 18%, local: phone 100 − lamp credit note 50 = 50. No 0% row.
  if jsonb_array_length(v_g1 -> 'b2cs') <> 1
     or (v_g1 -> 'b2cs' -> 0 ->> 'taxable_value')::numeric <> 50
     or v_g1 -> 'b2cs' -> 0 ->> 'supply_type' <> 'INTRA' then
    raise exception 'FAIL 3: B2CS %', v_g1 -> 'b2cs';
  end if;

  -- 4. Table 8: rice to the Karnataka business 50 (inter, registered);
  --    to walk-ins 100 + 50 + 50 − 50 returned = 150 (intra, unregistered).
  if (select (n ->> 'nil_amount')::numeric from jsonb_array_elements(v_g1 -> 'nil') n
      where n ->> 'supply_type' = 'INTRB2B') <> 50
     or (select (n ->> 'nil_amount')::numeric from jsonb_array_elements(v_g1 -> 'nil') n
      where n ->> 'supply_type' = 'INTRAB2C') <> 150 then
    raise exception 'FAIL 4: Table 8 %', v_g1 -> 'nil';
  end if;

  -- 5. Credit notes: the phone to the registered buyer in CDNR.
  if jsonb_array_length(v_g1 -> 'cdnr') <> 1 or (v_g1 -> 'cdnr' -> 0 ->> 'taxable_value')::numeric <> 100 then
    raise exception 'FAIL 5: CDNR %', v_g1 -> 'cdnr';
  end if;

  -- 6. HSN: rice B2C 2 + 1 + 1 − 1 = 3; lamp B2C −1 (returned, sold earlier) → 0
  --    with a warning; soap (untaxed) not in the summary but flagged.
  if (select (h ->> 'quantity')::numeric from jsonb_array_elements(v_g1 -> 'hsn') h
      where h ->> 'supply' = 'B2C' and h ->> 'hsn_code' = '1006') <> 3 then
    raise exception 'FAIL 6a: rice HSN %', v_g1 -> 'hsn';
  end if;
  if (select (h ->> 'quantity')::numeric from jsonb_array_elements(v_g1 -> 'hsn') h
      where h ->> 'hsn_code' = '9405') <> 0
     or (v_g1 -> 'warnings' ->> 'hsn_negative_quantity')::int <> 1 then
    raise exception 'FAIL 6b: lamp HSN % warnings %', v_g1 -> 'hsn', v_g1 -> 'warnings';
  end if;
  if exists (select 1 from jsonb_array_elements(v_g1 -> 'hsn') h where h ->> 'hsn_code' = '3401')
     or (v_g1 -> 'warnings' ->> 'untaxed_bills')::int <> 1
     or (v_g1 -> 'warnings' ->> 'untaxed_value')::numeric <> 59 then
    raise exception 'FAIL 6c: untaxed soap % warnings %', v_g1 -> 'hsn', v_g1 -> 'warnings';
  end if;

  -- 7. Documents: invoices (code 1, every series incl. cash memos) and
  --    credit notes (code 5: the phone and the lamp).
  select coalesce(sum((d ->> 'total')::numeric), 0) into v_n
    from jsonb_array_elements(v_g1 -> 'docs') d where (d ->> 'doc_num')::int = 1;
  if v_n <> 4 then
    raise exception 'FAIL 7a: invoices issued % in %', v_n, v_g1 -> 'docs';
  end if;
  if (select sum((d ->> 'total')::numeric) from jsonb_array_elements(v_g1 -> 'docs') d
      where (d ->> 'doc_num')::int = 5) <> 2 then
    raise exception 'FAIL 7b: credit notes in %', v_g1 -> 'docs';
  end if;

  -- 8. GSTR-3B: 3.1(a) 100 + 200 − 100 − 50 = 150; 3.1(c) rice 200.
  v_g3 := public.get_gstr3b(v_today, v_today);
  if (v_g3 -> 'outward_taxable' ->> 'taxable_value')::numeric <> 150
     or (v_g3 -> 'outward_nil_exempt' ->> 'taxable_value')::numeric <> 200
     or (v_g3 ->> 'untaxed_value')::numeric <> 59 then
    raise exception 'FAIL 8: GSTR-3B %', v_g3;
  end if;

  -- 9. Composition return at 1%: turnover 409, of which rice 200 is nil
  --    → tax on 209 = 2.09 (CGST 1.05 + SGST 1.04).
  v_c := public.get_composition_return(v_today, v_today);
  if (v_c ->> 'turnover')::numeric <> 409 or (v_c ->> 'taxable_turnover')::numeric <> 209
     or (v_c ->> 'tax')::numeric <> 2.09
     or (v_c ->> 'cgst')::numeric + (v_c ->> 'sgst')::numeric <> 2.09 then
    raise exception 'FAIL 9: composition %', v_c;
  end if;

  -- 10. A product's GST type must be one the law knows.
  begin
    update public.products set gst_category = 'zero' where id = rice;
    raise exception 'FAIL 10: an unknown GST type was accepted';
  exception when check_violation then null;
  end;
end $$;

rollback;
