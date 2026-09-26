-- ============================================================
-- R1 GST verification (migration 0040): bill discounts inside the
-- taxable value, credit notes, GSTR-1 / GSTR-3B.
--
-- HOW TO RUN — on a STAGING copy, after 0040:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
--
-- Shop: Maharashtra (27). Customers: a Karnataka business with a GSTIN
-- (B2B, inter-state) and a local walk-in-style customer (B2C).
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('cccccccc-0000-0000-0000-00000000000c', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'r1-gst-owner@test.invalid');

insert into public.businesses (id, name, state_code, gst_number) values
  ('cccccccc-1111-0000-0000-00000000000c', 'R1 GST Shop', '27', '27AAPFU0939F1ZV');

update public.profiles set business_id = 'cccccccc-1111-0000-0000-00000000000c', role = 'owner'
  where id = 'cccccccc-0000-0000-0000-00000000000c';

insert into public.subscriptions (business_id, status, expiry_date) values
  ('cccccccc-1111-0000-0000-00000000000c', 'active', current_date + 30);

insert into public.products (id, business_id, name, selling_price, purchase_price, gst_rate, hsn_code) values
  ('cccccccc-2222-0000-0000-00000000000c', 'cccccccc-1111-0000-0000-00000000000c',
   'R1 Phone', 118, 80, 18, '8517');
insert into public.stock_movements (business_id, product_id, movement_type, quantity, note) values
  ('cccccccc-1111-0000-0000-00000000000c', 'cccccccc-2222-0000-0000-00000000000c', 'opening', 50, 'r1 test');

insert into public.customers (id, business_id, name, gst_number, credit_unlimited) values
  ('cccccccc-3333-0000-0000-0000000000b2', 'cccccccc-1111-0000-0000-00000000000c',
   'R1 Karnataka Traders', '29AAPFU0939F1ZR', true),
  ('cccccccc-3333-0000-0000-0000000000c2', 'cccccccc-1111-0000-0000-00000000000c',
   'R1 Local customer', '', true);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"cccccccc-0000-0000-0000-00000000000c","role":"authenticated"}', true);

do $$
declare
  v_b2b    uuid;
  v_b2c    uuid;
  v_line   record;
  v_ret    jsonb;
  v_cn     record;
  v_g1     jsonb;
  v_g3     jsonb;
  v_today  date := public.ist_date(now());
begin
  -- 1. GSTIN check digits.
  if not public.is_valid_gstin('27AAPFU0939F1ZV') or public.is_valid_gstin('27AAPFU0939F1ZX') then
    raise exception 'FAIL 1: GSTIN check digit validation';
  end if;
  raise notice 'PASS 1 (GSTIN check digit)';

  -- 2. B2B inter-state bill: IGST, customer GSTIN kept on the bill.
  v_b2b := (public.create_invoice(jsonb_build_object(
    'invoice_type', 'gst', 'customer_id', 'cccccccc-3333-0000-0000-0000000000b2',
    'customer_name', 'R1 Karnataka Traders', 'paid_amount', 236, 'payment_mode', 'cash',
    'items', jsonb_build_array(jsonb_build_object(
      'product_id', 'cccccccc-2222-0000-0000-00000000000c', 'product_name', 'R1 Phone', 'hsn_code', '8517',
      'quantity', 2, 'unit_price', 100, 'gst_rate', 18, 'tax_amount', 36, 'line_total', 236)))) ->> 'id')::uuid;
  if (select customer_gstin from public.invoices where id = v_b2b) <> '29AAPFU0939F1ZR' then
    raise exception 'FAIL 2a: customer GSTIN not kept on the bill';
  end if;
  select * into v_line from public.invoice_items where invoice_id = v_b2b;
  if v_line.taxable_value <> 200 or v_line.igst_amount <> 36 or v_line.cgst_amount <> 0 then
    raise exception 'FAIL 2b: B2B line taxable % IGST % CGST %', v_line.taxable_value, v_line.igst_amount, v_line.cgst_amount;
  end if;
  raise notice 'PASS 2 (B2B inter-state → IGST, GSTIN snapshot)';

  -- 3. Bill discount reduces the taxable value: 118 incl. 18% less ₹18
  --    → customer pays 100 = taxable 84.75 + tax 15.25 (CGST 7.63 + SGST 7.62).
  v_b2c := (public.create_invoice(jsonb_build_object(
    'invoice_type', 'gst', 'customer_id', 'cccccccc-3333-0000-0000-0000000000c2',
    'customer_name', 'R1 Local customer', 'paid_amount', 100, 'payment_mode', 'cash',
    'discount_amount', 18,
    'items', jsonb_build_array(jsonb_build_object(
      'product_id', 'cccccccc-2222-0000-0000-00000000000c', 'product_name', 'R1 Phone', 'hsn_code', '8517',
      'quantity', 1, 'unit_price', 100, 'gst_rate', 18, 'tax_amount', 18, 'line_total', 118)))) ->> 'id')::uuid;
  select * into v_line from public.invoice_items where invoice_id = v_b2c;
  if (select total from public.invoices where id = v_b2c) <> 100
     or v_line.taxable_value <> 84.75 or v_line.cgst_amount + v_line.sgst_amount <> 15.25
     or v_line.igst_amount <> 0 then
    raise exception 'FAIL 3: discounted line taxable % CGST % SGST % IGST %',
      v_line.taxable_value, v_line.cgst_amount, v_line.sgst_amount, v_line.igst_amount;
  end if;
  raise notice 'PASS 3 (bill discount inside the taxable value)';

  -- 4. Partial return on the B2B bill → credit note with IGST reversed.
  v_ret := public.create_sale_return(jsonb_build_object(
    'invoice_id', v_b2b, 'refund_amount', 118, 'refund_mode', 'cash',
    'items', jsonb_build_array(jsonb_build_object(
      'product_id', 'cccccccc-2222-0000-0000-00000000000c', 'product_name', 'R1 Phone', 'quantity', 1))));
  select sr.credit_note_no, sri.taxable_value, sri.igst_amount, sri.cgst_amount, sri.hsn_code
    into v_cn
    from public.sale_returns sr join public.sale_return_items sri on sri.sale_return_id = sr.id
    where sr.id = (v_ret ->> 'id')::uuid;
  if v_cn.credit_note_no not like 'CN/__-__/_____' or v_cn.taxable_value <> 100
     or v_cn.igst_amount <> 18 or v_cn.cgst_amount <> 0 or v_cn.hsn_code <> '8517' then
    raise exception 'FAIL 4: credit note % taxable % IGST % CGST % HSN %',
      v_cn.credit_note_no, v_cn.taxable_value, v_cn.igst_amount, v_cn.cgst_amount, v_cn.hsn_code;
  end if;
  raise notice 'PASS 4 (credit note %: IGST reversed proportionally)', v_cn.credit_note_no;

  -- 5. GSTR-1 sections.
  v_g1 := public.get_gstr1(v_today, v_today);
  if jsonb_array_length(v_g1 -> 'b2b') <> 1
     or (v_g1 -> 'b2b' -> 0 ->> 'igst_amount')::numeric <> 36 then
    raise exception 'FAIL 5a: GSTR-1 B2B %', v_g1 -> 'b2b';
  end if;
  if jsonb_array_length(v_g1 -> 'cdnr') <> 1
     or (v_g1 -> 'cdnr' -> 0 ->> 'taxable_value')::numeric <> 100 then
    raise exception 'FAIL 5b: GSTR-1 CDNR %', v_g1 -> 'cdnr';
  end if;
  if jsonb_array_length(v_g1 -> 'b2cs') <> 1
     or (v_g1 -> 'b2cs' -> 0 ->> 'taxable_value')::numeric <> 84.75 then
    raise exception 'FAIL 5c: GSTR-1 B2CS %', v_g1 -> 'b2cs';
  end if;
  -- HSN (B2B): 2 sold − 1 returned = 1 unit, taxable 100.
  if (select (h ->> 'quantity')::numeric from jsonb_array_elements(v_g1 -> 'hsn') h
      where h ->> 'supply' = 'B2B' and h ->> 'hsn_code' = '8517') <> 1 then
    raise exception 'FAIL 5d: GSTR-1 HSN %', v_g1 -> 'hsn';
  end if;
  raise notice 'PASS 5 (GSTR-1 B2B, CDNR, B2CS, HSN)';

  -- 6. GSTR-3B: outward tax = 36 IGST − 18 IGST credit note, + 15.25 CGST/SGST.
  v_g3 := public.get_gstr3b(v_today, v_today);
  if (v_g3 -> 'outward_taxable' ->> 'igst_amount')::numeric <> 18
     or (v_g3 -> 'outward_taxable' ->> 'taxable_value')::numeric <> 184.75
     or (v_g3 -> 'outward_taxable' ->> 'cgst_amount')::numeric
        + (v_g3 -> 'outward_taxable' ->> 'sgst_amount')::numeric <> 15.25 then
    raise exception 'FAIL 6: GSTR-3B outward %', v_g3 -> 'outward_taxable';
  end if;
  raise notice 'PASS 6 (GSTR-3B outward supplies net of credit notes)';
end $$;

reset role;
do $$ begin raise notice 'ALL R1 GST CHECKS PASSED — rolling back test data'; end $$;
rollback;
