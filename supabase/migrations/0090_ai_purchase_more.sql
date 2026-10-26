-- ============================================================
-- 0090_ai_purchase_more.sql — Dukania AI: more on purchases.
--
-- ai_purchase (0088) now also:
--   * takes free goods on a line (free_quantity, in bill units): their own
--     ₹0 line that doesn't change the cost price (update_cost false);
--   * sets an existing product's (or variant's) new selling price / MRP
--     from the bill (new_selling_price, new_mrp), shown in the preview;
--   * changes a purchase already entered (edit_purchase_id) through the
--     app's update_purchase: the same checks (no returns on it, stock
--     already sold, payments made later stay); what was paid with it stays
--     unless p.paid says otherwise.
--   * creates a new product WITH variants from a bill (new_product.variant:
--     lines sharing new_product.name become one product), or adds a new
--     variant to an existing product (new_variant);
--   * takes IMEI / serial numbers for tracked items (serial_nos, one per
--     piece), registered by create_purchase;
--   * splits what is paid with it (payments: cash + UPI…): the first
--     payment goes with the purchase, the rest are supplier payments
--     against it.
-- ai_build_sale / ai_return: IMEI / serial items (one serial per piece;
-- each must be in stock for that product), as the app bills them.
-- ai_purchase_return: goods sent back to the supplier against a purchase,
-- through the app's create_purchase_return (valued at that purchase's cost
-- and GST, stock must cover it, the supplier's due goes down or they
-- refund); preview = rolled-back dry run, p.ref against repeats.
-- ============================================================

alter table public.purchase_returns add column if not exists created_via text not null default 'app';
alter table public.purchase_returns alter column created_via set default public.request_source();
alter table public.purchase_returns add column if not exists ai_ref uuid;
create unique index if not exists uq_purchase_returns_ai_ref
  on public.purchase_returns (business_id, ai_ref) where ai_ref is not null;

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
  -- 0090
  v_edit      public.purchases;
  v_sp_init   numeric := 0;   -- paid with the purchase (an edit)
  v_sp_later  numeric := 0;   -- paid to the supplier later against it
  v_free      numeric;
  v_newsp     numeric;
  v_newmrp    numeric;
  v_prices    jsonb := '[]'::jsonb;
  v_pc        jsonb;
  v_bill_no   text;
  v_bill_date text;
  v_newmap    jsonb := '{}'::jsonb;   -- new products made on this bill, by name
  v_nv        jsonb;
  v_serials   jsonb;
  v_pays      jsonb;
  v_pay       jsonb;
  v_first     jsonb;
  v_pay_sum   numeric;
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
  elsif p_commit and coalesce(p ->> 'edit_purchase_id', '') = '' then
    raise exception 'Preview the purchase first and confirm it with its ref';
  end if;

  -- Changing a purchase already entered (the app's update_purchase).
  if coalesce(p ->> 'edit_purchase_id', '') <> '' then
    if p ->> 'edit_purchase_id' !~ v_uuid then raise exception 'edit_purchase_id must be an id from list_purchases'; end if;
    select * into v_edit from public.purchases
      where id = (p ->> 'edit_purchase_id')::uuid and business_id = v_business;
    if v_edit.id is null then raise exception 'Purchase not found in your shop'; end if;
    select initial, later into v_sp_init, v_sp_later from public.purchase_paid_split(v_edit);
  end if;
  v_bill_no := btrim(coalesce(p ->> 'bill_no', v_edit.bill_no, ''));
  v_bill_date := coalesce(nullif(p ->> 'bill_date', ''), v_edit.purchase_date::text, public.ist_date(now())::text);

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
    elsif v_edit.supplier_id is not null then
      select * into v_supplier from public.suppliers where id = v_edit.supplier_id;
    end if;

    for v_line in select * from jsonb_array_elements(p -> 'lines') loop
      v_n := v_n + 1;
      v_prod := null; v_var := null; v_how := null;
      v_mem_prod := null; v_mem_var := null; v_mem_fac := null; v_nv := null;

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
        if v_newmap ? lower(btrim(v_np ->> 'name')) then
          -- Another variant of a product made on an earlier line.
          select * into v_prod from public.products where id = (v_newmap ->> lower(btrim(v_np ->> 'name')))::uuid;
        else
        select id into v_unit_id from public.units
          where business_id = v_business and nullif(btrim(coalesce(v_np ->> 'unit', '')), '') is not null
            and (lower(name) = lower(btrim(v_np ->> 'unit')) or lower(short_name) = lower(btrim(v_np ->> 'unit')))
          limit 1;
        insert into public.products
          (business_id, name, selling_price, mrp, purchase_price, gst_rate, hsn_code, barcode, unit_id)
        values (v_business, btrim(v_np ->> 'name'), (v_np ->> 'selling_price')::numeric,
                coalesce(nullif(v_np ->> 'mrp', '')::numeric, 0), 0,
                coalesce(nullif(v_np ->> 'gst_rate', '')::numeric, nullif(v_line ->> 'gst_rate', '')::numeric, 0),
                btrim(coalesce(v_np ->> 'hsn', '')),
                case when btrim(coalesce(v_np ->> 'variant', '')) = ''
                     then btrim(coalesce(v_np ->> 'barcode', v_line ->> 'barcode', '')) else '' end,
                v_unit_id)
        returning * into v_prod;
        v_newmap := v_newmap || jsonb_build_object(lower(btrim(v_np ->> 'name')), v_prod.id);
        v_new_prods := v_new_prods || jsonb_build_array(v_prod.name);
        end if;
        v_how := 'new';
        if btrim(coalesce(v_np ->> 'variant', '')) <> '' then
          -- The new product's variant on this line.
          v_nv := jsonb_build_object('name', v_np ->> 'variant',
            'selling_price', v_np -> 'variant_selling_price', 'mrp', v_np -> 'variant_mrp',
            'barcode', coalesce(v_np ->> 'barcode', v_line ->> 'barcode'));
        end if;
      end if;
      -- A new variant of an existing product (a new size, a new colour).
      if v_prod.id is not null and v_how <> 'new' and jsonb_typeof(v_line -> 'new_variant') = 'object' then
        perform public.assert_can('can_manage_products');
        v_nv := v_line -> 'new_variant';
      end if;
      if v_nv is not null then
        if btrim(coalesce(v_nv ->> 'name', '')) = '' then raise exception 'Line %: the new variant needs a name', v_n; end if;
        select * into v_var from public.product_variants
          where product_id = v_prod.id and is_active and lower(name) = lower(btrim(v_nv ->> 'name'));
        if v_var.id is null then
          insert into public.product_variants
            (business_id, product_id, name, barcode, selling_price, mrp)
          values (v_business, v_prod.id, btrim(v_nv ->> 'name'), btrim(coalesce(v_nv ->> 'barcode', '')),
                  nullif(v_nv ->> 'selling_price', '')::numeric, nullif(v_nv ->> 'mrp', '')::numeric)
          returning * into v_var;
          if not v_prod.has_variants then
            update public.products set has_variants = true where id = v_prod.id returning * into v_prod;
          end if;
          v_new_prods := v_new_prods || jsonb_build_array(v_prod.name || ' (' || v_var.name || ')');
        end if;
        v_nv := null;
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

      -- Quantities in the shop's unit; prices before GST, per shop unit.
      v_pack := coalesce(nullif(v_line ->> 'pack_size', '')::numeric,
                         case when v_how = 'remembered' then v_mem_fac end, 1);
      v_qty  := nullif(v_line ->> 'quantity', '')::numeric;
      v_rate := nullif(v_line ->> 'rate', '')::numeric;
      v_gst  := coalesce(nullif(v_line ->> 'gst_rate', '')::numeric, v_prod.gst_rate, 0);
      v_disc := coalesce(nullif(v_line ->> 'discount', '')::numeric, 0);
      v_free := coalesce(nullif(v_line ->> 'free_quantity', '')::numeric, 0);
      v_newsp := nullif(v_line ->> 'new_selling_price', '')::numeric;
      v_newmrp := nullif(v_line ->> 'new_mrp', '')::numeric;
      if v_free < 0 then raise exception 'Line %: free quantity can''t be negative', v_n; end if;
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
      v_free := v_free * v_pack;
      -- IMEI / serial items: one number per piece.
      v_serials := coalesce(v_line -> 'serial_nos', '[]'::jsonb);
      if jsonb_typeof(v_serials) <> 'array' then raise exception 'Line %: serial_nos must be a list', v_n; end if;
      if v_prod.track_serial then
        if v_free > 0 then raise exception 'Line %: enter free IMEI items as their own line at ₹0', v_n; end if;
        if jsonb_array_length(v_serials) <> v_qty then
          raise exception 'Line % (%): give % IMEI / serial numbers, one per piece (got %)',
            v_n, v_prod.name, v_qty, jsonb_array_length(v_serials);
        end if;
        if (select count(distinct btrim(x)) from jsonb_array_elements_text(v_serials) x where btrim(x) <> '') <> v_qty then
          raise exception 'Line % (%): an IMEI / serial number is empty or repeated', v_n, v_prod.name;
        end if;
      elsif jsonb_array_length(v_serials) > 0 then
        raise exception 'Line %: % isn''t tracked by IMEI / serial number', v_n, v_prod.name;
      end if;
      v_taxable := round(v_qty * v_unit_price - v_disc, 2);
      if v_taxable < 0 then raise exception 'Line %: the discount is more than the line', v_n; end if;
      v_tax := round(v_taxable * v_gst / 100, 2);

      v_items := v_items || jsonb_build_array(jsonb_build_object(
        'product_id', v_prod.id, 'variant_id', v_var.id,
        'product_name', v_prod.name || coalesce(' (' || v_var.name || ')', ''),
        'quantity', v_qty, 'unit_price', v_unit_price, 'discount_amount', round(v_disc, 2),
        'gst_rate', v_gst, 'tax_amount', v_tax, 'line_total', v_taxable + v_tax,
        'serial_nos', (select coalesce(jsonb_agg(btrim(x)), '[]'::jsonb) from jsonb_array_elements_text(v_serials) x)));
      -- Free goods: their own line at ₹0 that doesn't change the cost price.
      if v_free > 0 then
        v_items := v_items || jsonb_build_array(jsonb_build_object(
          'product_id', v_prod.id, 'variant_id', v_var.id,
          'product_name', v_prod.name || coalesce(' (' || v_var.name || ')', '') || ' (free)',
          'quantity', v_free, 'unit_price', 0, 'discount_amount', 0,
          'gst_rate', v_gst, 'tax_amount', 0, 'line_total', 0,
          'update_cost', false, 'serial_nos', '[]'::jsonb));
      end if;
      -- New selling price / MRP from the bill (existing products).
      if (v_newsp is not null or v_newmrp is not null) and v_how <> 'new' then
        if v_newsp is not null and v_newsp < 0 or v_newmrp is not null and v_newmrp < 0 then
          raise exception 'Line %: a price can''t be negative', v_n;
        end if;
        v_prices := v_prices || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
          'product_id', v_prod.id, 'variant_id', v_var.id,
          'item', v_prod.name || coalesce(' (' || v_var.name || ')', ''),
          'selling_price', v_newsp, 'old_selling_price', case when v_newsp is not null
            then coalesce(v_var.selling_price, v_prod.selling_price) end,
          'mrp', v_newmrp, 'old_mrp', case when v_newmrp is not null
            then coalesce(nullif(v_var.mrp, 0), v_prod.mrp) end)));
      end if;
      v_show := v_show || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
        'line', v_n, 'bill_name', nullif(v_line ->> 'bill_name', ''),
        'product', v_prod.name || coalesce(' (' || v_var.name || ')', ''),
        'how', v_how, 'quantity', v_qty, 'pack_size', nullif(v_pack, 1),
        'cost_before_gst', v_unit_price, 'discount', nullif(round(v_disc, 2), 0),
        'free', nullif(v_free, 0),
        'serial_nos', case when jsonb_array_length(v_serials) > 0 then v_serials end,
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
    if jsonb_typeof(p -> 'payments') = 'array' and jsonb_array_length(p -> 'payments') > 0 then
      if v_edit.id is not null then raise exception 'A split payment is for a new purchase — use pay_supplier for a purchase already entered'; end if;
      v_pays := '[]'::jsonb;
      v_pay_sum := 0;
      for v_pay in select * from jsonb_array_elements(p -> 'payments') loop
        if lower(coalesce(v_pay ->> 'mode', '')) not in ('cash', 'upi', 'card', 'other') then
          raise exception 'Each payment''s mode must be cash, upi, card or other';
        end if;
        if coalesce(nullif(v_pay ->> 'amount', '')::numeric, 0) <= 0 then
          raise exception 'Each payment needs an amount more than 0';
        end if;
        v_pays := v_pays || jsonb_build_array(jsonb_build_object(
          'mode', lower(v_pay ->> 'mode'), 'amount', round((v_pay ->> 'amount')::numeric, 2)));
        v_pay_sum := v_pay_sum + round((v_pay ->> 'amount')::numeric, 2);
      end loop;
      if v_pay_sum > v_total + 0.005 then
        raise exception 'The payments (₹%) are more than the purchase (₹%)', v_pay_sum, v_total;
      end if;
      v_paid := v_pay_sum;
    elsif v_edit.id is not null and coalesce(p ->> 'paid', '') = '' then
      -- An edit keeps what was paid with the purchase; later payments stay too.
      v_paid := least(v_sp_init, greatest(v_total - v_sp_later, 0));
    else
      v_paid := case
        when coalesce(p ->> 'paid', 'full') = 'full' then v_total - v_sp_later
        when p ->> 'paid' = 'none' then 0
        else nullif(p ->> 'paid', '')::numeric end;
      if v_paid is null or v_paid < 0 then raise exception 'paid must be full, none or an amount'; end if;
      v_paid := least(v_paid, greatest(v_total - v_sp_later, 0));
    end if;
    if v_paid + v_sp_later < v_total and v_supplier.id is null then
      raise exception 'A purchase not fully paid needs a supplier';
    end if;
    if v_pays is not null and v_supplier.id is null then
      raise exception 'A split payment needs the supplier';
    end if;

    v_summary := jsonb_strip_nulls(jsonb_build_object(
      'editing_purchase', v_edit.purchase_no,
      'supplier', coalesce(v_supplier.name, 'no supplier'),
      'new_supplier', case when v_new_sup then true end,
      'bill_no', nullif(v_bill_no, ''),
      'bill_date', v_bill_date,
      'lines', v_show,
      'new_products', case when jsonb_array_length(v_new_prods) > 0 then v_new_prods end,
      'not_matched', case when jsonb_array_length(v_unmatched) > 0 then v_unmatched end,
      'before_gst', round(v_sub, 2), 'gst', round(v_taxsum, 2),
      'bill_discount', nullif(round(v_bill_disc, 2), 0), 'extra_charges', nullif(round(v_extra, 2), 0),
      'round_off', nullif(round(v_total - v_grand, 2), 0),
      'total', v_total, 'paid', v_paid + v_sp_later,
      'still_to_pay', v_total - v_paid - v_sp_later,
      'payments', v_pays,
      'price_changes', case when jsonb_array_length(v_prices) > 0 then v_prices end,
      'printed_total', nullif(p ->> 'bill_total', '')::numeric,
      'matches_printed_total', case when nullif(p ->> 'bill_total', '') is not null
        then abs(v_total - (p ->> 'bill_total')::numeric) <= 1 end));

    if jsonb_array_length(v_unmatched) > 0 then
      if p_commit then
        raise exception 'Some lines aren''t matched to a product yet: %', v_unmatched::text;
      end if;
      raise exception 'AI_PREVIEW_DONE';
    end if;

    v_res := jsonb_build_object(
      'supplier_id', v_supplier.id,
      'supplier_name', coalesce(v_supplier.name, ''),
      'bill_no', v_bill_no,
      'purchase_date', v_bill_date,
      'discount_amount', round(v_bill_disc, 2),
      'extra_charges', round(v_extra, 2),
      'round_off', round(v_total - v_grand, 2),
      'paid_amount', case when v_pays is not null then (v_pays -> 0 ->> 'amount')::numeric else v_paid end,
      'payment_mode', case when v_pays is not null then v_pays -> 0 ->> 'mode'
                           when v_paid = 0 then 'credit' else v_mode end,
      'notes', coalesce(p ->> 'notes', v_edit.notes, ''),
      'items', v_items);
    if v_edit.id is not null then
      perform public.update_purchase(v_edit.id, v_res);
      v_res := jsonb_build_object('id', v_edit.id, 'purchase_no', v_edit.purchase_no,
        'total', (select total from public.purchases where id = v_edit.id));
    else
      v_res := public.create_purchase(v_res);
      update public.purchases set ai_ref = v_ref where id = (v_res ->> 'id')::uuid;
      -- A split payment: the rest goes to the supplier against this purchase.
      if v_pays is not null then
        for v_pay in select x.v from jsonb_array_elements(v_pays) with ordinality as x(v, n) where x.n > 1 loop
          perform public.record_supplier_payment(v_supplier.id, (v_pay ->> 'amount')::numeric,
            (v_pay ->> 'mode')::public.payment_mode, v_bill_date::date, 'Paid with purchase (split)',
            (v_res ->> 'id')::uuid);
        end loop;
      end if;
    end if;
    -- The bill's new selling prices / MRPs.
    if jsonb_array_length(v_prices) > 0 then
      perform public.assert_can('can_manage_products');
      for v_pc in select * from jsonb_array_elements(v_prices) loop
        if v_pc ? 'variant_id' then
          update public.product_variants set
            selling_price = coalesce((v_pc ->> 'selling_price')::numeric, selling_price),
            mrp = coalesce((v_pc ->> 'mrp')::numeric, mrp)
          where id = (v_pc ->> 'variant_id')::uuid;
        else
          update public.products set
            selling_price = coalesce((v_pc ->> 'selling_price')::numeric, selling_price),
            mrp = coalesce((v_pc ->> 'mrp')::numeric, mrp)
          where id = (v_pc ->> 'product_id')::uuid;
        end if;
      end loop;
    end if;
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


-- p: { purchase_id, ref?, lines: [{ product_id, variant_id?, quantity }],
--      received?: 'full' | 'none' | amount (money the supplier gives back now;
--      the rest comes off what the shop owes them), notes? }
create or replace function public.ai_purchase_return(p jsonb, p_commit boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_uuid     constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_ref      uuid;
  v_done     record;
  v_pur      public.purchases;
  v_line     jsonb;
  v_name     text;
  v_items    jsonb := '[]'::jsonb;
  v_res      jsonb;
  v_ret      public.purchase_returns;
  v_summary  jsonb;
begin
  if v_business is null then raise exception 'No shop selected'; end if;
  perform public.assert_can('can_manage_purchases', p_commit);

  if coalesce(p ->> 'ref', '') <> '' then
    if p ->> 'ref' !~ v_uuid then raise exception 'ref must be the one from the preview'; end if;
    v_ref := (p ->> 'ref')::uuid;
    select id, return_no, total into v_done from public.purchase_returns
      where business_id = v_business and ai_ref = v_ref;
    if v_done.id is not null then
      return jsonb_build_object('already_saved', true, 'return_id', v_done.id,
                                'return_no', v_done.return_no, 'total', v_done.total);
    end if;
  elsif p_commit then
    raise exception 'Preview the return first and confirm it with its ref';
  end if;

  if coalesce(p ->> 'purchase_id', '') !~ v_uuid then
    raise exception 'Give the purchase_id of the purchase the goods came on (list_purchases)';
  end if;
  select * into v_pur from public.purchases where id = (p ->> 'purchase_id')::uuid and business_id = v_business;
  if v_pur.id is null then raise exception 'Purchase not found in your shop'; end if;
  if jsonb_typeof(p -> 'lines') is distinct from 'array' or jsonb_array_length(p -> 'lines') = 0 then
    raise exception 'Say which items go back';
  end if;

  for v_line in select * from jsonb_array_elements(p -> 'lines') loop
    if coalesce(v_line ->> 'product_id', '') !~ v_uuid then
      raise exception 'Each item needs its product_id (get_purchase shows them)';
    end if;
    select min(pi.product_name) into v_name from public.purchase_items pi
      where pi.purchase_id = v_pur.id and pi.product_id = (v_line ->> 'product_id')::uuid
        and pi.variant_id is not distinct from nullif(v_line ->> 'variant_id', '')::uuid;
    if v_name is null then raise exception 'That item is not on purchase %', v_pur.purchase_no; end if;
    if exists (select 1 from public.products where id = (v_line ->> 'product_id')::uuid and track_serial) then
      raise exception '% has IMEI / serial numbers — return it in the Dukania app', v_name;
    end if;
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'product_id', (v_line ->> 'product_id')::uuid,
      'variant_id', nullif(v_line ->> 'variant_id', '')::uuid,
      'product_name', regexp_replace(v_name, ' \(free\)$', ''),
      'quantity', nullif(v_line ->> 'quantity', '')::numeric));
  end loop;

  begin
    v_res := public.create_purchase_return(jsonb_build_object(
      'purchase_id', v_pur.id, 'supplier_id', v_pur.supplier_id,
      'notes', coalesce(p ->> 'notes', ''),
      'received_amount', case
         when coalesce(p ->> 'received', 'none') = 'full' then 999999999
         when p ->> 'received' = 'none' then 0
         else nullif(p ->> 'received', '')::numeric end,
      'items', v_items));
    select * into v_ret from public.purchase_returns where id = (v_res ->> 'id')::uuid;
    update public.purchase_returns set ai_ref = v_ref where id = v_ret.id;
    select jsonb_strip_nulls(jsonb_build_object(
             'purchase_no', v_pur.purchase_no, 'supplier_bill_no', nullif(v_pur.bill_no, ''),
             'supplier', nullif(v_pur.supplier_name, ''),
             'items', (select jsonb_agg(jsonb_build_object(
                         'item', product_name, 'quantity', quantity, 'value', line_total))
                       from public.purchase_return_items where purchase_return_id = v_ret.id),
             'return_value', v_ret.total,
             'taken_off_this_purchase', nullif((v_res ->> 'applied_to_bill')::numeric, 0),
             'supplier_refunds_now', nullif(v_ret.received_amount, 0),
             'off_what_you_owe_them', nullif(v_ret.total - v_ret.received_amount, 0)))
      into v_summary;
    if not p_commit then raise exception 'AI_PREVIEW_DONE'; end if;
  exception when others then
    if sqlerrm <> 'AI_PREVIEW_DONE' then raise; end if;
    return jsonb_build_object('preview', true, 'ok', true, 'summary', v_summary);
  end;

  return jsonb_build_object('return_id', v_ret.id, 'return_no', v_ret.return_no, 'summary', v_summary);
end $$;

revoke execute on function public.ai_purchase_return(jsonb, boolean) from public, anon;
grant execute on function public.ai_purchase_return(jsonb, boolean) to authenticated;

-- ---------- sales and returns with IMEI / serial items
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
  v_serials  jsonb;
  v_sn       text;
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
    if exists (select 1 from public.invoice_items where invoice_id = v_edit.id and serial_no <> '') then
      raise exception 'Bill % has IMEI / serial items — change it in the Dukania app', v_edit.invoice_no;
    end if;
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

    -- IMEI / serial items: one number per piece, each in stock for it.
    v_serials := coalesce(v_line -> 'serial_nos', '[]'::jsonb);
    if v_prod.track_serial then
      if v_qty <> jsonb_array_length(v_serials) then
        raise exception '% is sold by IMEI / serial number: give % of them (serial_nos), one per piece — get_product lists those in stock',
          v_prod.name, v_qty;
      end if;
      for v_sn in select btrim(x) from jsonb_array_elements_text(v_serials) x loop
        if not exists (select 1 from public.product_serials s
                       where s.business_id = v_business and s.serial_no = v_sn and s.product_id = v_prod.id
                         and s.variant_id is not distinct from v_var.id and s.status in ('in_stock', 'returned')) then
          raise exception 'IMEI / serial % isn''t in stock for %', v_sn, v_prod.name;
        end if;
      end loop;
      if (select count(distinct btrim(x)) from jsonb_array_elements_text(v_serials) x) <> v_qty then
        raise exception 'An IMEI / serial number for % is repeated', v_prod.name;
      end if;
    elsif jsonb_array_length(v_serials) > 0 then
      raise exception '% isn''t tracked by IMEI / serial number', v_prod.name;
    end if;

    v_rate  := case when v_gst then v_prod.gst_rate else 0 end;
    v_div   := 1 + v_rate / 100;
    v_gross := v_qty * v_price - v_disc - v_cardd;
    if v_prod.track_serial then
      -- As the app bills them: one line per serial, the line's discount
      -- shared equally.
      for v_sn in select btrim(x) from jsonb_array_elements_text(v_serials) x loop
        v_items := v_items || jsonb_build_array(jsonb_build_object(
          'product_id', v_prod.id, 'variant_id', v_var.id, 'product_name', v_prod.name,
          'variant_name', coalesce(v_var.name, ''), 'hsn_code', v_prod.hsn_code,
          'serial_no', v_sn, 'quantity', 1, 'unit_name', coalesce(v_unit, ''),
          'unit_price', round(v_price / v_div, 2),
          'mrp', coalesce(nullif(v_var.mrp, 0), v_prod.mrp),
          'cost_price', coalesce(nullif(v_var.purchase_price, 0), v_prod.purchase_price),
          'discount_amount', round((v_disc + v_cardd) / v_qty / v_div, 2),
          'gst_rate', v_rate,
          'tax_amount', round(v_gross / v_qty - v_gross / v_qty / v_div, 2),
          'line_total', round(v_gross / v_qty, 2)));
      end loop;
    else
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
    end if;
    v_show := v_show || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'item', v_prod.name || coalesce(' (' || v_var.name || ')', ''),
      'quantity', v_qty, 'unit', v_unit, 'price', v_price,
      'discount', nullif(round(v_disc, 2), 0), 'card_discount', nullif(round(v_cardd, 2), 0),
      'gst_rate', nullif(v_rate, 0), 'amount', round(v_gross, 2),
      'serial_nos', case when v_prod.track_serial then v_serials end)));
    v_sum := v_sum + case when v_prod.track_serial then v_qty * round(v_gross / v_qty, 2) else round(v_gross, 2) end;
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
    if v_ii.serial_no <> '' and coalesce(nullif(v_line ->> 'quantity', '')::numeric, 0) <> 1 then
      raise exception '% was sold with IMEI / serial % — return it with quantity 1', v_ii.product_name, v_ii.serial_no;
    end if;
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'product_id', v_ii.product_id, 'variant_id', v_ii.variant_id,
      'product_name', v_ii.product_name, 'serial_no', v_ii.serial_no,
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
