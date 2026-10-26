-- ============================================================
-- 0088_ai_purchases_returns.sql — Dukania AI phase 3/4: supplier bills
-- and sale returns through the AI assistant.
--
-- ChatGPT / Claude read the supplier's bill (photo or PDF) themselves and
-- send its lines; nothing of the bill is stored. ai_purchase() then does in
-- ONE transaction what the app's bill reader + purchase form do:
--   * each line is the shop's product: given (product_id), remembered for
--     this item name (supplier_bill_items, the same memory the app's bill
--     reader uses — the connector sends the app's key, billItemKey), found
--     by barcode, or a new product described on the line;
--   * a new supplier is added when the bill's supplier isn't in the shop;
--   * the purchase is made with the app's own create_purchase;
--   * the item names are remembered for next time (remember_bill).
-- With p_commit = false the same work is done and rolled back: the preview
-- shows the exact purchase, what is new, what isn't matched yet and whether
-- it adds up to the bill's printed total. p.ref (from the preview) makes a
-- repeated confirm return the same purchase instead of a second one.
--
-- ai_return() does the same for a sale return against a bill, through the
-- app's create_sale_return (values from the bill lines, return window,
-- refund), preview = rolled-back dry run, p.ref against repeats.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Made by the AI; one purchase / return per preview
-- ------------------------------------------------------------
alter table public.purchases    add column if not exists created_via text not null default 'app';
alter table public.suppliers    add column if not exists created_via text not null default 'app';
alter table public.sale_returns add column if not exists created_via text not null default 'app';
alter table public.purchases    alter column created_via set default public.request_source();
alter table public.suppliers    alter column created_via set default public.request_source();
alter table public.sale_returns alter column created_via set default public.request_source();

alter table public.purchases    add column if not exists ai_ref uuid;
alter table public.sale_returns add column if not exists ai_ref uuid;
create unique index if not exists uq_purchases_ai_ref
  on public.purchases (business_id, ai_ref) where ai_ref is not null;
create unique index if not exists uq_sale_returns_ai_ref
  on public.sale_returns (business_id, ai_ref) where ai_ref is not null;

-- ------------------------------------------------------------
-- 2. Supplier bill → purchase
-- ------------------------------------------------------------
-- p: { supplier_id? | new_supplier?: {name, phone?, gstin?},
--      bill_no?, bill_date?, ref?,
--      lines: [{ bill_name?, bill_key?, product_id?, variant_id?, barcode?,
--                new_product?: {name, selling_price, mrp?, gst_rate?, hsn?, unit?, barcode?},
--                quantity, pack_size? (shop units in one bill unit), rate (per bill unit),
--                rate_includes_gst?, gst_rate?, discount? (₹ off the line) }],
--      bill_discount?, extra_charges?, bill_total? (as printed),
--      paid?: 'full' | 'none' | amount, payment_mode?, notes? }
create or replace function public.ai_purchase(p jsonb, p_commit boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business  uuid := public.current_business_id();
  v_uuid      constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_ref       uuid;
  v_done      record;
  v_supplier  public.suppliers;
  v_new_sup   boolean := false;
  v_line      jsonb;
  v_np        jsonb;
  v_n         integer := 0;
  v_prod      public.products;
  v_var       public.product_variants;
  v_how       text;
  v_mem_prod  uuid;
  v_mem_var   uuid;
  v_mem_fac   numeric;
  v_pack      numeric;
  v_qty       numeric;
  v_rate      numeric;
  v_gst       numeric;
  v_unit_price numeric;
  v_disc      numeric;
  v_taxable   numeric;
  v_tax       numeric;
  v_items     jsonb := '[]'::jsonb;
  v_show      jsonb := '[]'::jsonb;
  v_unmatched jsonb := '[]'::jsonb;
  v_new_prods jsonb := '[]'::jsonb;
  v_remember  jsonb := '[]'::jsonb;
  v_sub       numeric := 0;
  v_taxsum    numeric := 0;
  v_bill_disc numeric := coalesce(nullif(p ->> 'bill_discount', '')::numeric, 0);
  v_extra     numeric := coalesce(nullif(p ->> 'extra_charges', '')::numeric, 0);
  v_grand     numeric;
  v_total     numeric;
  v_paid      numeric;
  v_mode      text := lower(coalesce(nullif(p ->> 'payment_mode', ''), 'cash'));
  v_unit_id   uuid;
  v_res       jsonb;
  v_summary   jsonb;
  v_err       text;
begin
  if v_business is null then raise exception 'No shop selected'; end if;
  perform public.assert_can('can_manage_purchases', p_commit);

  if coalesce(p ->> 'ref', '') <> '' then
    if p ->> 'ref' !~ v_uuid then raise exception 'ref must be the one from the preview'; end if;
    v_ref := (p ->> 'ref')::uuid;
    select id, purchase_no, total into v_done from public.purchases
      where business_id = v_business and ai_ref = v_ref;
    if v_done.id is not null then
      return jsonb_build_object('already_saved', true, 'purchase_id', v_done.id,
                                'purchase_no', v_done.purchase_no, 'total', v_done.total);
    end if;
  elsif p_commit then
    raise exception 'Preview the purchase first and confirm it with its ref';
  end if;

  if jsonb_typeof(p -> 'lines') is distinct from 'array' or jsonb_array_length(p -> 'lines') = 0 then
    raise exception 'Add the bill''s lines';
  end if;
  if jsonb_array_length(p -> 'lines') > 300 then raise exception 'At most 300 lines in one purchase'; end if;
  if v_mode not in ('cash', 'upi', 'card', 'other') then
    raise exception 'Payment mode must be cash, upi, card or other';
  end if;

  -- Everything below is undone for a preview (p_commit = false).
  begin
    -- The supplier: this shop's, or a new one from the bill.
    if coalesce(p ->> 'supplier_id', '') <> '' then
      if p ->> 'supplier_id' !~ v_uuid then raise exception 'supplier_id must be an id from find_suppliers'; end if;
      select * into v_supplier from public.suppliers
        where id = (p ->> 'supplier_id')::uuid and business_id = v_business and is_active;
      if v_supplier.id is null then raise exception 'Supplier not found in your shop'; end if;
    elsif btrim(coalesce(p #>> '{new_supplier,name}', '')) <> '' then
      -- The same GSTIN or name already in the shop is that supplier.
      select * into v_supplier from public.suppliers
        where business_id = v_business and is_active
          and ((nullif(upper(btrim(coalesce(p #>> '{new_supplier,gstin}', ''))), '') is not null
                and upper(gst_number) = upper(btrim(p #>> '{new_supplier,gstin}')))
               or lower(name) = lower(btrim(p #>> '{new_supplier,name}')))
        order by (upper(gst_number) = upper(btrim(coalesce(p #>> '{new_supplier,gstin}', '')))) desc
        limit 1;
      if v_supplier.id is null then
        insert into public.suppliers (business_id, name, phone, gst_number)
        values (v_business, btrim(p #>> '{new_supplier,name}'),
                btrim(coalesce(p #>> '{new_supplier,phone}', '')),
                upper(btrim(coalesce(p #>> '{new_supplier,gstin}', ''))))
        returning * into v_supplier;
        v_new_sup := true;
      end if;
    end if;

    for v_line in select * from jsonb_array_elements(p -> 'lines') loop
      v_n := v_n + 1;
      v_prod := null; v_var := null; v_how := null;
      v_mem_prod := null; v_mem_var := null; v_mem_fac := null;

      -- Which product: given, remembered, by barcode, or new.
      if coalesce(v_line ->> 'product_id', '') ~ v_uuid then
        select * into v_prod from public.products
          where id = (v_line ->> 'product_id')::uuid and business_id = v_business and is_active;
        if v_prod.id is null then raise exception 'Line %: product not found in your shop', v_n; end if;
        v_how := 'chosen';
      end if;
      if v_prod.id is null and btrim(coalesce(v_line ->> 'bill_key', '')) <> '' then
        select i.product_id, i.variant_id, i.factor into v_mem_prod, v_mem_var, v_mem_fac
          from public.supplier_bill_items i
          join public.products pr on pr.id = i.product_id and pr.is_active
          where i.business_id = v_business and i.item_key = lower(btrim(v_line ->> 'bill_key'))
          order by (v_supplier.id is not null and i.supplier_id = v_supplier.id) desc, i.updated_at desc
          limit 1;
        if v_mem_prod is not null then
          select * into v_prod from public.products where id = v_mem_prod;
          select * into v_var from public.product_variants where id = v_mem_var;
          v_how := 'remembered';
        end if;
      end if;
      if v_prod.id is null and btrim(coalesce(v_line ->> 'barcode', '')) <> '' then
        select * into v_prod from public.products
          where business_id = v_business and is_active and barcode = btrim(v_line ->> 'barcode') limit 1;
        if v_prod.id is null then
          select * into v_var from public.product_variants v
            where v.business_id = v_business and v.is_active and v.barcode = btrim(v_line ->> 'barcode') limit 1;
          if v_var.id is not null then select * into v_prod from public.products where id = v_var.product_id; end if;
        end if;
        if v_prod.id is not null then v_how := 'barcode'; end if;
      end if;
      if v_prod.id is null and jsonb_typeof(v_line -> 'new_product') = 'object' then
        v_np := v_line -> 'new_product';
        if btrim(coalesce(v_np ->> 'name', '')) = '' then
          raise exception 'Line %: the new product needs a name', v_n;
        end if;
        if nullif(v_np ->> 'selling_price', '') is null then
          raise exception 'Line % (%): give the new product a selling price', v_n, v_np ->> 'name';
        end if;
        perform public.assert_can('can_manage_products');
        select id into v_unit_id from public.units
          where business_id = v_business and nullif(btrim(coalesce(v_np ->> 'unit', '')), '') is not null
            and (lower(name) = lower(btrim(v_np ->> 'unit')) or lower(short_name) = lower(btrim(v_np ->> 'unit')))
          limit 1;
        insert into public.products
          (business_id, name, selling_price, mrp, purchase_price, gst_rate, hsn_code, barcode, unit_id)
        values (v_business, btrim(v_np ->> 'name'), (v_np ->> 'selling_price')::numeric,
                coalesce(nullif(v_np ->> 'mrp', '')::numeric, 0), 0,
                coalesce(nullif(v_np ->> 'gst_rate', '')::numeric, nullif(v_line ->> 'gst_rate', '')::numeric, 0),
                btrim(coalesce(v_np ->> 'hsn', '')), btrim(coalesce(v_np ->> 'barcode', v_line ->> 'barcode', '')),
                v_unit_id)
        returning * into v_prod;
        v_how := 'new';
        v_new_prods := v_new_prods || jsonb_build_array(v_prod.name);
      end if;

      if v_prod.id is null then
        v_unmatched := v_unmatched || jsonb_build_array(jsonb_build_object(
          'line', v_n, 'bill_name', coalesce(v_line ->> 'bill_name', '')));
        continue;
      end if;

      if v_prod.has_variants and v_var.id is null then
        if coalesce(v_line ->> 'variant_id', '') ~ v_uuid then
          select * into v_var from public.product_variants
            where id = (v_line ->> 'variant_id')::uuid and product_id = v_prod.id and is_active;
        end if;
        if v_var.id is null then
          raise exception 'Line % (%): % comes in variants (%) — say which one', v_n,
            coalesce(v_line ->> 'bill_name', ''), v_prod.name,
            (select string_agg(name, ', ' order by name) from public.product_variants
             where product_id = v_prod.id and is_active);
        end if;
      end if;
      if v_prod.track_serial then
        raise exception 'Line %: % needs IMEI / serial numbers — enter this purchase in the Dukania app', v_n, v_prod.name;
      end if;

      -- Quantities in the shop's unit; prices before GST, per shop unit.
      v_pack := coalesce(nullif(v_line ->> 'pack_size', '')::numeric,
                         case when v_how = 'remembered' then v_mem_fac end, 1);
      v_qty  := nullif(v_line ->> 'quantity', '')::numeric;
      v_rate := nullif(v_line ->> 'rate', '')::numeric;
      v_gst  := coalesce(nullif(v_line ->> 'gst_rate', '')::numeric, v_prod.gst_rate, 0);
      v_disc := coalesce(nullif(v_line ->> 'discount', '')::numeric, 0);
      if v_pack <= 0 then raise exception 'Line %: pack size must be more than 0', v_n; end if;
      if v_qty is null or v_qty <= 0 then raise exception 'Line %: quantity must be more than 0', v_n; end if;
      if v_rate is null or v_rate < 0 then raise exception 'Line %: give the rate', v_n; end if;
      if v_gst < 0 or v_gst > 40 then raise exception 'Line %: GST % %% isn''t a GST rate', v_n, v_gst; end if;
      if coalesce((v_line ->> 'rate_includes_gst')::boolean, false) then
        v_rate := v_rate / (1 + v_gst / 100);
        v_disc := v_disc / (1 + v_gst / 100);
      end if;
      v_unit_price := round(v_rate / v_pack, 2);
      v_qty := v_qty * v_pack;
      v_taxable := round(v_qty * v_unit_price - v_disc, 2);
      if v_taxable < 0 then raise exception 'Line %: the discount is more than the line', v_n; end if;
      v_tax := round(v_taxable * v_gst / 100, 2);

      v_items := v_items || jsonb_build_array(jsonb_build_object(
        'product_id', v_prod.id, 'variant_id', v_var.id,
        'product_name', v_prod.name || coalesce(' (' || v_var.name || ')', ''),
        'quantity', v_qty, 'unit_price', v_unit_price, 'discount_amount', round(v_disc, 2),
        'gst_rate', v_gst, 'tax_amount', v_tax, 'line_total', v_taxable + v_tax,
        'serial_nos', '[]'::jsonb));
      v_show := v_show || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
        'line', v_n, 'bill_name', nullif(v_line ->> 'bill_name', ''),
        'product', v_prod.name || coalesce(' (' || v_var.name || ')', ''),
        'how', v_how, 'quantity', v_qty, 'pack_size', nullif(v_pack, 1),
        'cost_before_gst', v_unit_price, 'discount', nullif(round(v_disc, 2), 0),
        'gst_rate', v_gst, 'amount', v_taxable + v_tax)));
      if btrim(coalesce(v_line ->> 'bill_key', '')) <> '' then
        v_remember := v_remember || jsonb_build_array(jsonb_build_object(
          'key', lower(btrim(v_line ->> 'bill_key')), 'product_id', v_prod.id,
          'variant_id', v_var.id, 'factor', v_pack));
      end if;
      v_sub := v_sub + v_taxable;
      v_taxsum := v_taxsum + v_tax;
    end loop;

    v_grand := v_sub + v_taxsum - v_bill_disc + v_extra;
    v_total := round(v_grand);
    v_paid := case
      when coalesce(p ->> 'paid', 'full') = 'full' then v_total
      when p ->> 'paid' = 'none' then 0
      else nullif(p ->> 'paid', '')::numeric end;
    if v_paid is null or v_paid < 0 then raise exception 'paid must be full, none or an amount'; end if;
    v_paid := least(v_paid, v_total);
    if v_paid < v_total and v_supplier.id is null then
      raise exception 'A purchase not fully paid needs a supplier';
    end if;

    v_summary := jsonb_strip_nulls(jsonb_build_object(
      'supplier', coalesce(v_supplier.name, 'no supplier'),
      'new_supplier', case when v_new_sup then true end,
      'bill_no', nullif(btrim(coalesce(p ->> 'bill_no', '')), ''),
      'bill_date', coalesce(nullif(p ->> 'bill_date', ''), public.ist_date(now())::text),
      'lines', v_show,
      'new_products', case when jsonb_array_length(v_new_prods) > 0 then v_new_prods end,
      'not_matched', case when jsonb_array_length(v_unmatched) > 0 then v_unmatched end,
      'before_gst', round(v_sub, 2), 'gst', round(v_taxsum, 2),
      'bill_discount', nullif(round(v_bill_disc, 2), 0), 'extra_charges', nullif(round(v_extra, 2), 0),
      'round_off', nullif(round(v_total - v_grand, 2), 0),
      'total', v_total, 'paid', v_paid, 'still_to_pay', v_total - v_paid,
      'printed_total', nullif(p ->> 'bill_total', '')::numeric,
      'matches_printed_total', case when nullif(p ->> 'bill_total', '') is not null
        then abs(v_total - (p ->> 'bill_total')::numeric) <= 1 end));

    if jsonb_array_length(v_unmatched) > 0 then
      if p_commit then
        raise exception 'Some lines aren''t matched to a product yet: %', v_unmatched::text;
      end if;
      raise exception 'AI_PREVIEW_DONE';
    end if;

    v_res := public.create_purchase(jsonb_build_object(
      'supplier_id', v_supplier.id,
      'supplier_name', coalesce(v_supplier.name, ''),
      'bill_no', btrim(coalesce(p ->> 'bill_no', '')),
      'purchase_date', coalesce(nullif(p ->> 'bill_date', ''), public.ist_date(now())::text),
      'discount_amount', round(v_bill_disc, 2),
      'extra_charges', round(v_extra, 2),
      'round_off', round(v_total - v_grand, 2),
      'paid_amount', v_paid,
      'payment_mode', case when v_paid = 0 then 'credit' else v_mode end,
      'notes', coalesce(p ->> 'notes', ''),
      'items', v_items));
    update public.purchases set ai_ref = v_ref where id = (v_res ->> 'id')::uuid;
    if jsonb_array_length(v_remember) > 0 then
      perform public.remember_bill(v_supplier.id, v_remember, null);
    end if;
    v_summary := v_summary || jsonb_build_object('total', (v_res ->> 'total')::numeric);

    if not p_commit then raise exception 'AI_PREVIEW_DONE'; end if;
  exception when others then
    if sqlerrm <> 'AI_PREVIEW_DONE' then raise; end if;
    return jsonb_build_object('preview', true,
      'ok', jsonb_array_length(v_unmatched) = 0, 'summary', v_summary);
  end;

  return jsonb_build_object('purchase_id', v_res ->> 'id', 'purchase_no', v_res ->> 'purchase_no',
                            'summary', v_summary);
end $$;

-- ------------------------------------------------------------
-- 3. Sale return against a bill
-- ------------------------------------------------------------
-- p: { bill_id, ref?, lines: [{ bill_line_id, quantity, condition? }],
--      refund?: 'full' | 'none' | amount, refund_mode?, notes?, late_reason? }
-- condition: sellable (back to stock) | damaged | inspection | scrap.
-- refund 'none': the value comes off what the customer owes (or becomes
-- their advance) — as in the app.
create or replace function public.ai_return(p jsonb, p_commit boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_uuid     constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_ref      uuid;
  v_done     record;
  v_inv      public.invoices;
  v_line     jsonb;
  v_ii       public.invoice_items;
  v_items    jsonb := '[]'::jsonb;
  v_mode     text := lower(coalesce(nullif(p ->> 'refund_mode', ''), 'cash'));
  v_res      jsonb;
  v_ret      public.sale_returns;
  v_summary  jsonb;
begin
  if v_business is null then raise exception 'No shop selected'; end if;
  perform public.assert_can('can_manage_returns', p_commit);

  if coalesce(p ->> 'ref', '') <> '' then
    if p ->> 'ref' !~ v_uuid then raise exception 'ref must be the one from the preview'; end if;
    v_ref := (p ->> 'ref')::uuid;
    select id, return_no, total into v_done from public.sale_returns
      where business_id = v_business and ai_ref = v_ref;
    if v_done.id is not null then
      return jsonb_build_object('already_saved', true, 'return_id', v_done.id,
                                'return_no', v_done.return_no, 'total', v_done.total);
    end if;
  elsif p_commit then
    raise exception 'Preview the return first and confirm it with its ref';
  end if;

  if coalesce(p ->> 'bill_id', '') !~ v_uuid then raise exception 'Give the bill_id of the bill being returned'; end if;
  select * into v_inv from public.invoices where id = (p ->> 'bill_id')::uuid and business_id = v_business;
  if v_inv.id is null then raise exception 'Bill not found in your shop'; end if;
  if v_mode not in ('cash', 'upi', 'card', 'other') then
    raise exception 'Refund mode must be cash, upi, card or other';
  end if;
  if jsonb_typeof(p -> 'lines') is distinct from 'array' or jsonb_array_length(p -> 'lines') = 0 then
    raise exception 'Say which items come back';
  end if;

  for v_line in select * from jsonb_array_elements(p -> 'lines') loop
    if coalesce(v_line ->> 'bill_line_id', '') !~ v_uuid then
      raise exception 'Each returned item needs its bill_line_id from get_bill';
    end if;
    select * into v_ii from public.invoice_items
      where id = (v_line ->> 'bill_line_id')::uuid and invoice_id = v_inv.id;
    if v_ii.id is null then raise exception 'That item is not on bill %', v_inv.invoice_no; end if;
    if v_ii.serial_no <> '' then
      raise exception '% was sold with IMEI / serial % — return it in the Dukania app', v_ii.product_name, v_ii.serial_no;
    end if;
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'product_id', v_ii.product_id, 'variant_id', v_ii.variant_id,
      'product_name', v_ii.product_name, 'serial_no', '',
      'quantity', nullif(v_line ->> 'quantity', '')::numeric,
      'condition', coalesce(nullif(v_line ->> 'condition', ''), 'sellable'),
      'invoice_item_id', v_ii.id, 'unit_price', 0, 'tax_amount', 0, 'line_total', 0));
  end loop;

  begin
    -- Valued from the bill lines by create_sale_return; refund capped by it.
    v_res := public.create_sale_return(jsonb_build_object(
      'invoice_id', v_inv.id, 'customer_id', v_inv.customer_id,
      'notes', coalesce(p ->> 'notes', ''),
      'window_override_reason', btrim(coalesce(p ->> 'late_reason', '')),
      'refund_amount', case
         when coalesce(p ->> 'refund', 'full') = 'full' then 999999999
         when p ->> 'refund' = 'none' then 0
         else nullif(p ->> 'refund', '')::numeric end,
      'refund_mode', v_mode,
      'items', v_items));
    select * into v_ret from public.sale_returns where id = (v_res ->> 'id')::uuid;
    update public.sale_returns set ai_ref = v_ref where id = v_ret.id;
    select jsonb_build_object(
             'bill_no', v_inv.invoice_no, 'customer', nullif(v_inv.customer_name, ''),
             'items', (select jsonb_agg(jsonb_build_object(
                         'item', product_name, 'quantity', quantity, 'condition', condition,
                         'value', line_total)) from public.sale_return_items where sale_return_id = v_ret.id),
             'return_value', v_ret.total, 'refund_now', v_ret.refund_amount,
             'refund_mode', case when v_ret.refund_amount > 0 then v_ret.refund_mode end,
             'taken_off_this_bill', nullif((v_res ->> 'applied_to_bill')::numeric, 0),
             'kept_as_customer_advance', nullif((v_res ->> 'advance')::numeric, 0))
      into v_summary;
    if not p_commit then raise exception 'AI_PREVIEW_DONE'; end if;
  exception when others then
    if sqlerrm <> 'AI_PREVIEW_DONE' then raise; end if;
    return jsonb_build_object('preview', true, 'ok', true, 'summary', jsonb_strip_nulls(v_summary));
  end;

  return jsonb_build_object('return_id', v_ret.id, 'return_no', v_ret.return_no,
                            'summary', jsonb_strip_nulls(v_summary));
end $$;

revoke execute on function public.ai_purchase(jsonb, boolean) from public, anon;
revoke execute on function public.ai_return(jsonb, boolean) from public, anon;
grant execute on function public.ai_purchase(jsonb, boolean) to authenticated;
grant execute on function public.ai_return(jsonb, boolean) to authenticated;
