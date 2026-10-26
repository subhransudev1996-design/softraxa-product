-- ============================================================
-- 0089_ai_sales_more.sql — Dukania AI: discount cards, offers and coupons,
-- split payments, quotations / cash memos and editing a bill.
--
-- Replaces ai_build_sale / ai_preview_sale / ai_create_sale (0087) with
-- the same maths as the app's cart (pos/cart.dart):
--   * p.card — a discount card's number (or its ending, as at the counter):
--     its % comes off each line it covers (after the line's own discount),
--     exactly as CartNotifier._withCard does; the server checks the card
--     (apply_invoice_discount_card) and allows that reduction.
--   * p.offer_code (a coupon / voucher / scratch-card code) or p.offer_id
--     (a counter offer without a code), p.offer_amount for a scratch card's
--     prize: worked out like AppliedOffer.discountOn — % of the bill after
--     the typed bill discount, capped, nothing under the minimum bill — and
--     checked by apply_invoice_offer.
--   * p.payments — [{mode, amount}] for a bill paid partly by cash, partly
--     by UPI…
--   * p.bill_type — 'bill' (the shop's usual GST / non-GST bill),
--     'cash_memo' or 'estimate' (a quotation: no stock, no payment).
--   * p.edit_bill_id — the new lines for an existing bill, through the
--     app's update_invoice: its type and customer stay; payments already
--     taken stay; its card / offer stay unless p says otherwise
--     ('none' removes them).
-- ============================================================

create or replace function public.ai_build_sale(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_uuid     constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_biz      public.businesses;
  v_edit     public.invoices;
  v_type     text;
  v_gst      boolean;
  v_line     jsonb;
  v_prod     public.products;
  v_var      public.product_variants;
  v_unit     text;
  v_qty      numeric;
  v_price    numeric;
  v_disc     numeric;
  v_cardd    numeric;
  v_rate     numeric;
  v_div      numeric;
  v_gross    numeric;
  v_items    jsonb := '[]'::jsonb;
  v_show     jsonb := '[]'::jsonb;
  v_sum      numeric := 0;
  v_card_sum numeric := 0;
  v_bill_disc numeric := coalesce(nullif(p ->> 'bill_discount', '')::numeric, 0);
  v_grand    numeric;
  v_round    numeric;
  v_total    numeric;
  v_paid     numeric;
  v_mode     text := lower(coalesce(nullif(p ->> 'payment_mode', ''), 'cash'));
  v_pays     jsonb;
  v_pay      jsonb;
  v_cust     public.customers;
  v_ref      uuid;
  -- discount card
  v_card     jsonb;
  v_card_id  uuid;
  v_card_no  text;
  v_card_name text;
  v_card_pct numeric := 0;
  v_card_to  text;
  v_card_cats uuid[];
  v_card_set boolean := false;   -- the payload says which card (or none)
  -- offer
  v_offer    public.offers;
  v_found    jsonb;
  v_ocode    text := '';
  v_oamount  numeric;
  v_ochosen  numeric := nullif(p ->> 'offer_amount', '')::numeric;
  v_ocodeamt numeric;
  v_ogross   numeric;
  v_offer_set boolean := false;
  v_payload  jsonb;
begin
  if v_business is null then raise exception 'No shop selected'; end if;
  select * into v_biz from public.businesses where id = v_business;

  -- New bill or an edit of one; its type.
  if coalesce(p ->> 'edit_bill_id', '') <> '' then
    if p ->> 'edit_bill_id' !~ v_uuid then raise exception 'edit_bill_id must be a bill id from list_bills'; end if;
    select * into v_edit from public.invoices
      where id = (p ->> 'edit_bill_id')::uuid and business_id = v_business;
    if v_edit.id is null then raise exception 'Bill not found in your shop'; end if;
    if v_edit.is_cancelled then raise exception 'Bill % is cancelled — it can''t be edited', v_edit.invoice_no; end if;
    v_type := v_edit.invoice_type::text;
    if v_type = 'opening' then raise exception 'An opening balance can''t be edited'; end if;
    if coalesce(p ->> 'customer_id', '') <> '' and p ->> 'customer_id' <> coalesce(v_edit.customer_id::text, '') then
      raise exception 'Changing a bill''s customer is done in the Dukania app';
    end if;
    select * into v_cust from public.customers where id = v_edit.customer_id;
  else
    v_type := case coalesce(nullif(p ->> 'bill_type', ''), 'bill')
      when 'bill' then case when v_biz.tax_preference = 'gst' and public.feature_enabled('gst_billing')
                            then 'gst' else 'non_gst' end
      when 'cash_memo' then 'cash_memo'
      when 'estimate' then 'estimate'
      else null end;
    if v_type is null then raise exception 'bill_type must be bill, cash_memo or estimate'; end if;
  end if;
  v_gst := v_type = 'gst';

  if jsonb_typeof(p -> 'lines') is distinct from 'array' or jsonb_array_length(p -> 'lines') = 0 then
    raise exception 'Add at least one item to the sale';
  end if;
  if jsonb_array_length(p -> 'lines') > 100 then raise exception 'At most 100 items in one sale'; end if;

  -- The customer (a new bill).
  if v_edit.id is null and coalesce(p ->> 'customer_id', '') <> '' then
    if p ->> 'customer_id' !~ v_uuid then raise exception 'customer_id must be an id from find_customers'; end if;
    select * into v_cust from public.customers
      where id = (p ->> 'customer_id')::uuid and business_id = v_business and is_active;
    if v_cust.id is null then raise exception 'Customer not found in your shop'; end if;
  end if;

  -- The discount card: given, removed ('none'), or kept from the bill.
  if lower(coalesce(p ->> 'card', '')) in ('none', 'remove') then
    v_card_set := true;
  elsif btrim(coalesce(p ->> 'card', '')) <> '' then
    v_card := public.find_discount_card(p ->> 'card');
    if not coalesce((v_card ->> 'found')::boolean, false) then
      raise exception 'No discount card % in this shop', btrim(p ->> 'card');
    end if;
    if not (v_card ->> 'usable')::boolean then raise exception '%', v_card ->> 'problem'; end if;
    v_card_set := true;
    v_card_id := (v_card ->> 'id')::uuid;
    v_card_no := v_card ->> 'card_no';
    v_card_name := v_card ->> 'type_name';
    v_card_pct := (v_card ->> 'discount_pct')::numeric;
    v_card_to := v_card ->> 'applies_to';
    v_card_cats := array(select jsonb_array_elements_text(coalesce(v_card -> 'category_ids', '[]'::jsonb))::uuid);
  elsif v_edit.discount_card_id is not null then
    select d.id, d.card_no, t.name, v_edit.discount_card_pct, t.applies_to, t.category_ids
      into v_card_id, v_card_no, v_card_name, v_card_pct, v_card_to, v_card_cats
      from public.discount_cards d join public.discount_card_types t on t.id = d.card_type_id
      where d.id = v_edit.discount_card_id;
  end if;
  if v_type = 'estimate' and v_card_id is not null then
    raise exception 'A discount card can''t be used on a quotation';
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

    -- The card's % of what is left after the line's own discount.
    v_cardd := 0;
    if v_card_id is not null and v_card_pct > 0
       and (v_card_to = 'all'
            or (v_card_to = 'only' and v_prod.category_id = any (v_card_cats))
            or (v_card_to = 'except' and not coalesce(v_prod.category_id = any (v_card_cats), false))) then
      v_cardd := (v_qty * v_price - v_disc) * v_card_pct / 100;
    end if;

    v_rate  := case when v_gst then v_prod.gst_rate else 0 end;
    v_div   := 1 + v_rate / 100;
    v_gross := v_qty * v_price - v_disc - v_cardd;
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
      'discount_amount', round((v_disc + v_cardd) / v_div, 2),
      'gst_rate', v_rate,
      'tax_amount', round(v_gross - v_gross / v_div, 2),
      'line_total', round(v_gross, 2)));
    v_show := v_show || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'item', v_prod.name || coalesce(' (' || v_var.name || ')', ''),
      'quantity', v_qty, 'unit', v_unit, 'price', v_price,
      'discount', nullif(round(v_disc, 2), 0), 'card_discount', nullif(round(v_cardd, 2), 0),
      'gst_rate', nullif(v_rate, 0), 'amount', round(v_gross, 2))));
    v_sum := v_sum + round(v_gross, 2);
    v_card_sum := v_card_sum + v_cardd;
  end loop;

  if v_bill_disc < 0 or v_bill_disc > v_sum then
    raise exception 'The bill discount must be between 0 and the bill amount';
  end if;

  -- The offer / coupon: given, removed ('none'), or kept from the bill.
  if lower(coalesce(p ->> 'offer_code', p ->> 'offer_id', '')) in ('none', 'remove') then
    v_offer_set := true;
  elsif btrim(coalesce(p ->> 'offer_code', '')) <> '' then
    v_found := public.find_offer_code(p ->> 'offer_code');
    if not coalesce((v_found ->> 'found')::boolean, false) then
      raise exception 'No offer or coupon with the code % in this shop', btrim(p ->> 'offer_code');
    end if;
    if not (v_found ->> 'usable')::boolean then raise exception '%', v_found ->> 'problem'; end if;
    select * into v_offer from public.offers where id = (v_found ->> 'offer_id')::uuid;
    v_ocode := coalesce(v_found ->> 'code', '');
    v_ocodeamt := nullif(v_found ->> 'code_amount', '')::numeric;
    v_offer_set := true;
  elsif coalesce(p ->> 'offer_id', '') <> '' then
    if p ->> 'offer_id' !~ v_uuid then raise exception 'offer_id must be an id from list_offers'; end if;
    select * into v_offer from public.offers where id = (p ->> 'offer_id')::uuid and business_id = v_business;
    if v_offer.id is null then raise exception 'Offer not found in your shop'; end if;
    if v_offer.code_mode <> 'none' and v_offer.id is distinct from v_edit.offer_id then
      raise exception 'The offer "%" needs its code — give offer_code', v_offer.name;
    end if;
    if v_offer.id is distinct from v_edit.offer_id then
      if not v_offer.is_active then raise exception 'The offer "%" is switched off', v_offer.name; end if;
      if (v_offer.valid_from is not null and v_offer.valid_from > public.ist_date(now()))
         or (v_offer.valid_until is not null and v_offer.valid_until < public.ist_date(now())) then
        raise exception 'The offer "%" isn''t open today', v_offer.name;
      end if;
    else
      v_ocode := v_edit.offer_code;
    end if;
    v_offer_set := true;
  elsif v_edit.offer_id is not null then
    select * into v_offer from public.offers where id = v_edit.offer_id;
    v_ocode := v_edit.offer_code;
    v_ochosen := coalesce(v_ochosen, v_edit.offer_amount);
    v_offer_set := true;
  end if;
  if v_offer.id is not null then
    if v_type = 'estimate' then raise exception 'An offer can''t be used on a quotation'; end if;
    v_ogross := v_sum - v_bill_disc;
    if v_ogross + 0.005 < v_offer.min_bill then
      raise exception 'The offer "%" needs a bill of at least ₹%', v_offer.name, v_offer.min_bill;
    end if;
    if v_offer.kind = 'percent' then
      v_oamount := round(v_ogross * v_offer.percent / 100, 2);
      if v_offer.max_discount is not null then v_oamount := least(v_oamount, v_offer.max_discount); end if;
    else
      v_oamount := coalesce(v_ochosen, v_ocodeamt,
        case when cardinality(v_offer.amounts) = 1 then v_offer.amounts[1] end);
      if v_oamount is null then
        raise exception 'Which prize does the card show? The offer "%" gives ₹% — give offer_amount',
          v_offer.name, array_to_string(v_offer.amounts, ', ₹');
      end if;
    end if;
    v_oamount := least(v_oamount, greatest(v_ogross, 0));
  end if;

  v_grand := v_sum - v_bill_disc - coalesce(v_oamount, 0);
  v_round := round(v_grand) - v_grand;
  v_total := round(v_grand);

  -- What is paid now.
  if v_type = 'estimate' then
    v_paid := 0;
  elsif v_edit.id is not null then
    v_paid := least(v_edit.paid_amount, v_total);
  elsif jsonb_typeof(p -> 'payments') = 'array' and jsonb_array_length(p -> 'payments') > 0 then
    v_pays := '[]'::jsonb;
    v_paid := 0;
    for v_pay in select * from jsonb_array_elements(p -> 'payments') loop
      if lower(coalesce(v_pay ->> 'mode', '')) not in ('cash', 'upi', 'card', 'other') then
        raise exception 'Each payment''s mode must be cash, upi, card or other';
      end if;
      if coalesce(nullif(v_pay ->> 'amount', '')::numeric, 0) <= 0 then
        raise exception 'Each payment needs an amount more than 0';
      end if;
      v_pays := v_pays || jsonb_build_array(jsonb_build_object(
        'mode', lower(v_pay ->> 'mode'), 'amount', (v_pay ->> 'amount')::numeric));
      v_paid := v_paid + (v_pay ->> 'amount')::numeric;
    end loop;
    if v_paid > v_total + 0.005 then
      raise exception 'The payments (₹%) are more than the bill (₹%)', v_paid, v_total;
    end if;
  else
    v_paid := case
      when coalesce(p ->> 'paid', 'full') = 'full' then v_total
      when p ->> 'paid' = 'none' then 0
      else nullif(p ->> 'paid', '')::numeric end;
    if v_paid is null or v_paid < 0 then raise exception 'paid must be full, none or an amount'; end if;
    v_paid := least(v_paid, v_total);
    if v_mode not in ('cash', 'upi', 'card', 'other') then
      raise exception 'Payment mode must be cash, upi, card or other';
    end if;
  end if;
  if v_type <> 'estimate' and v_edit.id is null and v_paid < v_total and v_cust.id is null then
    raise exception 'A sale not fully paid needs a customer — find or add them first';
  end if;

  if v_edit.id is null and coalesce(p ->> 'sale_ref', '') <> '' then
    if p ->> 'sale_ref' !~ v_uuid then raise exception 'sale_ref must be the one from the preview'; end if;
    v_ref := (p ->> 'sale_ref')::uuid;
  end if;

  v_payload := jsonb_strip_nulls(jsonb_build_object(
    'invoice_type', v_type,
    'customer_id', v_cust.id,
    'customer_name', coalesce(v_cust.name, btrim(coalesce(p ->> 'customer_name', ''))),
    'customer_phone', coalesce(v_cust.phone, ''),
    'discount_amount', round(v_bill_disc + coalesce(v_oamount, 0), 2),
    'round_off', round(v_round, 2),
    'paid_amount', v_paid,
    'payment_mode', case when v_pays is not null then 'other' when v_paid = 0 then 'credit' else v_mode end,
    'payments', v_pays,
    'notes', coalesce(p ->> 'notes', v_edit.notes, ''),
    'due_date', nullif(p ->> 'due_date', ''),
    'items', v_items,
    'local_id', v_ref,
    'offline_created', false,
    'owner_ack', case when coalesce((p ->> 'owner_ack')::boolean, false) then true end));
  -- Card / offer keys: present (even null, to remove) only when decided.
  if v_card_set or v_card_id is not null then
    v_payload := v_payload || jsonb_build_object('discount_card_id', v_card_id);
  end if;
  if v_offer_set or v_offer.id is not null then
    v_payload := v_payload || jsonb_build_object(
      'offer_id', v_offer.id, 'offer_code', v_ocode, 'offer_amount', coalesce(round(v_oamount, 2), 0));
  end if;

  return jsonb_build_object(
    'payload', v_payload,
    'summary', jsonb_strip_nulls(jsonb_build_object(
      'editing_bill', v_edit.invoice_no,
      'bill_type', case v_type when 'gst' then 'GST bill' when 'non_gst' then 'bill'
                               when 'cash_memo' then 'cash memo' else 'quotation (estimate)' end,
      'customer', coalesce(v_cust.name, nullif(btrim(coalesce(p ->> 'customer_name', '')), ''), 'Walk-in customer'),
      'lines', v_show,
      'discount_card', case when v_card_id is not null then jsonb_build_object(
         'card', v_card_no, 'type', v_card_name, 'percent', v_card_pct, 'discount', round(v_card_sum, 2)) end,
      'bill_discount', nullif(round(v_bill_disc, 2), 0),
      'offer', case when v_offer.id is not null then jsonb_build_object(
         'name', v_offer.name, 'code', nullif(v_ocode, ''), 'discount', round(v_oamount, 2)) end,
      'round_off', nullif(round(v_round, 2), 0),
      'total', v_total,
      'paid', case when v_type <> 'estimate' then v_paid end,
      'payments', v_pays,
      'payment_mode', case when v_pays is null and v_paid > 0 and v_edit.id is null then v_mode end,
      'due', case when v_type <> 'estimate' then v_total - v_paid end,
      'due_date', nullif(p ->> 'due_date', ''),
      'note', case when v_edit.id is not null then 'Payments already taken on this bill stay as they are.'
                   when v_type = 'estimate' then 'A quotation: no stock moves and nothing is paid.' end)));
end $$;

-- Dry run of the real sale (or the edit), rolled back.
create or replace function public.ai_preview_sale(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_built  jsonb := public.ai_build_sale(p - 'owner_ack');
  v_res    jsonb;
  v_err    text;
  v_saved  text;
  v_warn   jsonb;
  v_owner  boolean := public.has_permission('owner');
  v_edit   uuid := nullif(p ->> 'edit_bill_id', '')::uuid;
begin
  if v_edit is not null then perform public.assert_can('can_edit_invoices', false); end if;
  begin
    if v_edit is not null then
      perform public.update_invoice(v_edit, v_built -> 'payload');
    else
      v_res := public.create_invoice(v_built -> 'payload');
      if coalesce((v_res ->> 'already_synced')::boolean, false) then
        v_saved := v_res ->> 'invoice_no';
      end if;
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

-- The real sale, or the edit.
create or replace function public.ai_create_sale(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_built jsonb;
  v_res   jsonb;
  v_edit  uuid := nullif(p ->> 'edit_bill_id', '')::uuid;
begin
  if v_edit is null and coalesce(p ->> 'sale_ref', '') = '' then
    raise exception 'Preview the sale first and confirm it with its sale_ref';
  end if;
  v_built := public.ai_build_sale(p);
  if nullif(p ->> 'expected_total', '') is not null
     and (v_built #>> '{summary,total}')::numeric <> (p ->> 'expected_total')::numeric then
    raise exception 'The total is now ₹% instead of ₹% — preview it again',
      v_built #>> '{summary,total}', p ->> 'expected_total';
  end if;
  if v_edit is not null then
    perform public.update_invoice(v_edit, v_built -> 'payload');
    return jsonb_build_object(
      'bill_id', v_edit,
      'bill_no', (select invoice_no from public.invoices where id = v_edit),
      'edited', true,
      'summary', v_built -> 'summary');
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
