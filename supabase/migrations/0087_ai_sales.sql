-- ============================================================
-- 0087_ai_sales.sql — Dukania AI phase 2: the AI assistant makes sales.
--
-- The shop connector (supabase/functions/shop-mcp) never invents bill
-- maths: it sends simple lines (product, quantity, optional price and
-- discount) and these functions turn them into exactly the payload the app
-- sends, then use the app's own create_invoice — so prices, discount
-- rights, GST, stock, approvals and plan limits are checked the same way.
--
--   1. request_source(): 'ai' when the request came through the connector
--      (it sends the header X-Dukania-Source: ai), else 'app'. Bills,
--      products, expenses, customers and audit log rows record it
--      (created_via / source), so "made by ChatGPT" is always visible.
--   2. ai_build_sale(p): the create_invoice payload + totals for p.
--   3. ai_preview_sale(p): a dry run of the real sale, rolled back: the
--      totals, and the warnings the owner must accept (below cost, credit
--      limit, overdue, discount limit) or the reason it can't be made.
--   4. ai_create_sale(p): makes it. p.sale_ref (a uuid from the preview) is
--      the bill's local_id, so a repeated confirm returns the same bill
--      instead of billing twice; p.expected_total refuses a sale whose total
--      changed since the preview.
--
-- p: { customer_id?, customer_name?, lines: [{ product_id, variant_id?,
--      quantity, price? (per unit, incl. GST), discount? (₹ off the line) }],
--      bill_discount?, paid?: 'full' | 'none' | amount, payment_mode?,
--      notes?, due_date?, sale_ref?, expected_total?, owner_ack? }
-- ============================================================

-- ------------------------------------------------------------
-- 1. Where a record came from
-- ------------------------------------------------------------
create or replace function public.request_source()
returns text language plpgsql stable as $$
begin
  return case
    when nullif(current_setting('request.headers', true), '')::json ->> 'x-dukania-source' = 'ai'
    then 'ai' else 'app' end;
exception when others then
  return 'app';
end $$;

alter table public.invoices  add column if not exists created_via text not null default 'app';
alter table public.products  add column if not exists created_via text not null default 'app';
alter table public.expenses  add column if not exists created_via text not null default 'app';
alter table public.customers add column if not exists created_via text not null default 'app';
alter table public.audit_logs add column if not exists source text not null default 'app';
alter table public.invoices  alter column created_via set default public.request_source();
alter table public.products  alter column created_via set default public.request_source();
alter table public.expenses  alter column created_via set default public.request_source();
alter table public.customers alter column created_via set default public.request_source();
alter table public.audit_logs alter column source set default public.request_source();

-- ------------------------------------------------------------
-- 2. Simple lines → the app's create_invoice payload
-- ------------------------------------------------------------
-- Same maths as the app's buildInvoicePayload (pos/cart.dart): prices are
-- GST-inclusive; unit price, discount and tax are split out per line; the
-- bill discount comes off the GST-inclusive total; whole-rupee round-off.
create or replace function public.ai_build_sale(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_biz      public.businesses;
  v_gst      boolean;
  v_line     jsonb;
  v_prod     public.products;
  v_var      public.product_variants;
  v_unit     text;
  v_qty      numeric;
  v_price    numeric;
  v_disc     numeric;
  v_rate     numeric;
  v_div      numeric;
  v_gross    numeric;
  v_items    jsonb := '[]'::jsonb;
  v_show     jsonb := '[]'::jsonb;
  v_sum      numeric := 0;
  v_bill_disc numeric := coalesce(nullif(p ->> 'bill_discount', '')::numeric, 0);
  v_grand    numeric;
  v_round    numeric;
  v_total    numeric;
  v_paid     numeric;
  v_mode     text := lower(coalesce(nullif(p ->> 'payment_mode', ''), 'cash'));
  v_cust     public.customers;
  v_uuid     constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_ref      uuid;
begin
  if v_business is null then raise exception 'No shop selected'; end if;
  select * into v_biz from public.businesses where id = v_business;
  v_gst := v_biz.tax_preference = 'gst' and public.feature_enabled('gst_billing');

  if jsonb_typeof(p -> 'lines') is distinct from 'array' or jsonb_array_length(p -> 'lines') = 0 then
    raise exception 'Add at least one item to the sale';
  end if;
  if jsonb_array_length(p -> 'lines') > 100 then
    raise exception 'At most 100 items in one sale';
  end if;

  for v_line in select * from jsonb_array_elements(p -> 'lines') loop
    if coalesce(v_line ->> 'product_id', '') !~ v_uuid then
      raise exception 'Each item needs a product_id from find_products';
    end if;
    select * into v_prod from public.products
      where id = (v_line ->> 'product_id')::uuid and business_id = v_business and is_active;
    if v_prod.id is null then raise exception 'Product not found in your shop'; end if;
    if v_prod.track_serial then
      raise exception '% needs an IMEI / serial number — bill it in the Dukania app', v_prod.name;
    end if;
    select name into v_unit from public.units where id = v_prod.unit_id;

    v_var := null;
    if v_prod.has_variants then
      if coalesce(v_line ->> 'variant_id', '') !~ v_uuid then
        raise exception '% comes in variants (%): say which one', v_prod.name,
          (select string_agg(name, ', ' order by name) from public.product_variants
           where product_id = v_prod.id and is_active);
      end if;
      select * into v_var from public.product_variants
        where id = (v_line ->> 'variant_id')::uuid and product_id = v_prod.id and is_active;
      if v_var.id is null then raise exception 'That variant of % wasn''t found', v_prod.name; end if;
    end if;

    v_qty := nullif(v_line ->> 'quantity', '')::numeric;
    if v_qty is null or v_qty <= 0 then
      raise exception 'The quantity of % must be more than 0', v_prod.name;
    end if;
    v_price := coalesce(nullif(v_line ->> 'price', '')::numeric, v_var.selling_price, v_prod.selling_price);
    if v_price is null or v_price < 0 then raise exception 'Give a price for %', v_prod.name; end if;
    v_disc := coalesce(nullif(v_line ->> 'discount', '')::numeric, 0);
    if v_disc < 0 or v_disc > v_qty * v_price then
      raise exception 'The discount on % is more than its price', v_prod.name;
    end if;

    v_rate  := case when v_gst then v_prod.gst_rate else 0 end;
    v_div   := 1 + v_rate / 100;
    v_gross := v_qty * v_price - v_disc;
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'product_id', v_prod.id,
      'variant_id', v_var.id,
      'product_name', v_prod.name,
      'variant_name', coalesce(v_var.name, ''),
      'hsn_code', v_prod.hsn_code,
      'serial_no', '',
      'quantity', v_qty,
      'unit_name', coalesce(v_unit, ''),
      'unit_price', round(v_price / v_div, 2),
      'mrp', coalesce(nullif(v_var.mrp, 0), v_prod.mrp),
      'cost_price', coalesce(nullif(v_var.purchase_price, 0), v_prod.purchase_price),
      'discount_amount', round(v_disc / v_div, 2),
      'gst_rate', v_rate,
      'tax_amount', round(v_gross - v_gross / v_div, 2),
      'line_total', round(v_gross, 2)));
    v_show := v_show || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'item', v_prod.name || coalesce(' (' || v_var.name || ')', ''),
      'quantity', v_qty, 'unit', v_unit, 'price', v_price,
      'discount', nullif(v_disc, 0), 'gst_rate', nullif(v_rate, 0),
      'amount', round(v_gross, 2))));
    v_sum := v_sum + round(v_gross, 2);
  end loop;

  if v_bill_disc < 0 or v_bill_disc > v_sum then
    raise exception 'The bill discount must be between 0 and the bill amount';
  end if;
  v_grand := v_sum - v_bill_disc;
  v_round := round(v_grand) - v_grand;
  v_total := round(v_grand);

  v_paid := case
    when coalesce(p ->> 'paid', 'full') = 'full' then v_total
    when p ->> 'paid' = 'none' then 0
    else nullif(p ->> 'paid', '')::numeric end;
  if v_paid is null or v_paid < 0 then raise exception 'paid must be full, none or an amount'; end if;
  v_paid := least(v_paid, v_total);
  if v_mode not in ('cash', 'upi', 'card', 'other') then
    raise exception 'Payment mode must be cash, upi, card or other';
  end if;

  if coalesce(p ->> 'customer_id', '') <> '' then
    if p ->> 'customer_id' !~ v_uuid then raise exception 'customer_id must be an id from find_customers'; end if;
    select * into v_cust from public.customers
      where id = (p ->> 'customer_id')::uuid and business_id = v_business and is_active;
    if v_cust.id is null then raise exception 'Customer not found in your shop'; end if;
  end if;
  if v_paid < v_total and v_cust.id is null then
    raise exception 'A sale not fully paid needs a customer — find or add them first';
  end if;

  if coalesce(p ->> 'sale_ref', '') <> '' then
    if p ->> 'sale_ref' !~ v_uuid then raise exception 'sale_ref must be the one from the preview'; end if;
    v_ref := (p ->> 'sale_ref')::uuid;
  end if;

  return jsonb_build_object(
    'payload', jsonb_strip_nulls(jsonb_build_object(
      'invoice_type', case when v_gst then 'gst' else 'non_gst' end,
      'customer_id', v_cust.id,
      'customer_name', coalesce(v_cust.name, btrim(coalesce(p ->> 'customer_name', ''))),
      'customer_phone', coalesce(v_cust.phone, ''),
      'discount_amount', round(v_bill_disc, 2),
      'round_off', round(v_round, 2),
      'paid_amount', v_paid,
      'payment_mode', case when v_paid = 0 then 'credit' else v_mode end,
      'notes', coalesce(p ->> 'notes', ''),
      'due_date', nullif(p ->> 'due_date', ''),
      'items', v_items,
      'local_id', v_ref,
      'offline_created', false,
      'owner_ack', case when coalesce((p ->> 'owner_ack')::boolean, false) then true end)),
    'summary', jsonb_strip_nulls(jsonb_build_object(
      'bill_type', case when v_gst then 'GST bill' else 'bill' end,
      'customer', coalesce(v_cust.name, nullif(btrim(coalesce(p ->> 'customer_name', '')), ''), 'Walk-in customer'),
      'lines', v_show,
      'bill_discount', nullif(round(v_bill_disc, 2), 0),
      'round_off', nullif(round(v_round, 2), 0),
      'total', v_total,
      'paid', v_paid,
      'payment_mode', case when v_paid = 0 then null else v_mode end,
      'due', v_total - v_paid,
      'due_date', nullif(p ->> 'due_date', ''))));
end $$;

-- ------------------------------------------------------------
-- 3. Dry run
-- ------------------------------------------------------------
create or replace function public.ai_preview_sale(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_built  jsonb := public.ai_build_sale(p - 'owner_ack');
  v_res    jsonb;
  v_err    text;
  v_saved  text;
  v_warn   jsonb;
  v_owner  boolean := public.has_permission('owner');
begin
  begin
    v_res := public.create_invoice(v_built -> 'payload');
    if coalesce((v_res ->> 'already_synced')::boolean, false) then
      v_saved := v_res ->> 'invoice_no';
    end if;
    raise exception 'AI_PREVIEW_DONE';
  exception when others then
    if sqlerrm <> 'AI_PREVIEW_DONE' then v_err := sqlerrm; end if;
  end;

  if v_saved is not null then
    return jsonb_build_object('already_saved', true, 'bill_no', v_saved);
  end if;
  if v_err like 'APPROVAL_REQUIRED %' then
    v_warn := substr(v_err, length('APPROVAL_REQUIRED ') + 1)::jsonb;
    return jsonb_build_object(
      'ok', v_owner, 'summary', v_built -> 'summary', 'warnings', v_warn,
      'needs', case when v_owner then 'owner_ack' else 'owner_approval' end);
  end if;
  if v_err is not null then
    return jsonb_build_object('ok', false, 'error', v_err, 'summary', v_built -> 'summary');
  end if;
  return jsonb_build_object('ok', true, 'summary', v_built -> 'summary', 'warnings', '[]'::jsonb);
end $$;

-- ------------------------------------------------------------
-- 4. The real sale
-- ------------------------------------------------------------
create or replace function public.ai_create_sale(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_built jsonb;
  v_res   jsonb;
begin
  if coalesce(p ->> 'sale_ref', '') = '' then
    raise exception 'Preview the sale first and confirm it with its sale_ref';
  end if;
  v_built := public.ai_build_sale(p);
  if nullif(p ->> 'expected_total', '') is not null
     and (v_built #>> '{summary,total}')::numeric <> (p ->> 'expected_total')::numeric then
    raise exception 'The total is now ₹% instead of ₹% — preview the sale again',
      v_built #>> '{summary,total}', p ->> 'expected_total';
  end if;
  v_res := public.create_invoice(v_built -> 'payload');
  return jsonb_build_object(
    'bill_id', v_res ->> 'id',
    'bill_no', v_res ->> 'invoice_no',
    'already_saved', coalesce((v_res ->> 'already_synced')::boolean, false),
    'summary', v_built -> 'summary');
end $$;

revoke execute on function public.ai_build_sale(jsonb) from public, anon, authenticated;
revoke execute on function public.ai_preview_sale(jsonb) from public, anon;
revoke execute on function public.ai_create_sale(jsonb) from public, anon;
grant execute on function public.ai_preview_sale(jsonb) to authenticated;
grant execute on function public.ai_create_sale(jsonb) to authenticated;
