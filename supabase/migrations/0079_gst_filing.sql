-- ============================================================
-- 0079_gst_filing.sql — GST returns the portal accepts
--
--   A. GST type of a product: taxable, nil-rated, exempt or non-GST. Each
--      bill line keeps its type when billed ('untaxed': a taxable product
--      sold on a bill of supply or cash memo, without GST).
--   B. Composition shops: their rate (1% traders and manufacturers, 5%
--      restaurants, 6% services).
--   C. GSTR-1 (replaces 0040's):
--      * bills of supply and cash memos of a regular shop are outward
--        supplies too — they were left out;
--      * nil-rated, exempt and non-GST lines go to Table 8 (nil), not into
--        B2B / B2C at 0%;
--      * B2C large: over ₹1 lakh from 1 Aug 2024, ₹2.5 lakh before;
--      * HSN summary (Table 12) split B2B / B2C, description at most 30
--        characters, no negative quantity (the portal rejects it), services
--        with no quantity;
--      * documents issued (Table 13) per series, with the portal's codes;
--      * checks for what the portal would reject or the law needs.
--   D. GSTR-3B (replaces 0040's): Table 3.1(c) nil/exempt and 3.1(e)
--      non-GST include bills of supply; Table 5 inward nil/exempt.
--   E. Composition return (CMP-08 for a quarter, GSTR-4 for a year).
--
-- Run AFTER 0078.
-- ============================================================

-- ============================================================
-- A. GST type
-- ============================================================
alter table public.products add column if not exists gst_category text not null default 'taxable';
alter table public.products drop constraint if exists products_gst_category_check;
alter table public.products add constraint products_gst_category_check
  check (gst_category in ('taxable', 'nil', 'exempt', 'non_gst'));

alter table public.invoice_items add column if not exists gst_category text not null default 'taxable';
alter table public.invoice_items drop constraint if exists invoice_items_gst_category_check;
alter table public.invoice_items add constraint invoice_items_gst_category_check
  check (gst_category in ('taxable', 'nil', 'exempt', 'non_gst', 'untaxed'));

alter table public.sale_return_items add column if not exists gst_category text not null default 'taxable';
alter table public.sale_return_items drop constraint if exists sale_return_items_gst_category_check;
alter table public.sale_return_items add constraint sale_return_items_gst_category_check
  check (gst_category in ('taxable', 'nil', 'exempt', 'non_gst', 'untaxed'));

-- A line's GST type: taxed → taxable; at 0% → the product's type, or
-- 'untaxed' when the product is taxable (sold without GST on a bill of
-- supply / cash memo); no product (a cutting charge) → nil.
create or replace function public.line_gst_category(p_rate numeric, p_product uuid)
returns text language sql stable security definer set search_path = public as $$
  select case
    when coalesce(p_rate, 0) > 0 then 'taxable'
    else coalesce((
      select case when p.gst_category in ('nil', 'exempt', 'non_gst') then p.gst_category
                  when p.gst_rate > 0 then 'untaxed'
                  else 'nil' end
      from public.products p where p.id = p_product), 'nil')
  end;
$$;

create or replace function public.set_line_gst_category()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.gst_category := public.line_gst_category(new.gst_rate, new.product_id);
  return new;
end $$;

drop trigger if exists trg_invoice_items_gst_type on public.invoice_items;
create trigger trg_invoice_items_gst_type
  before insert or update of gst_rate, product_id on public.invoice_items
  for each row execute function public.set_line_gst_category();

-- Named after trg_sale_return_items_gst, which sets the line's rate first.
drop trigger if exists trg_sale_return_items_gst_type on public.sale_return_items;
create trigger trg_sale_return_items_gst_type
  before insert or update of gst_rate, product_id on public.sale_return_items
  for each row execute function public.set_line_gst_category();

revoke execute on function public.line_gst_category(numeric, uuid) from public, anon, authenticated;
revoke execute on function public.set_line_gst_category() from public, anon, authenticated;

-- Backfill: earlier 0% lines get their type (from the product as it is
-- now). No references change, so the tenant check is paused (as in 0040).
alter table public.invoice_items     disable trigger trg_00_tenant_refs;
alter table public.sale_return_items disable trigger trg_00_tenant_refs;
update public.invoice_items
   set gst_category = public.line_gst_category(gst_rate, product_id)
 where gst_rate = 0;
update public.sale_return_items
   set gst_category = public.line_gst_category(gst_rate, product_id)
 where gst_rate = 0;
alter table public.invoice_items     enable trigger trg_00_tenant_refs;
alter table public.sale_return_items enable trigger trg_00_tenant_refs;

-- ============================================================
-- B. Composition rate
-- ============================================================
alter table public.businesses add column if not exists composition_rate numeric(4,2) not null default 1;
alter table public.businesses drop constraint if exists businesses_composition_rate_check;
alter table public.businesses add constraint businesses_composition_rate_check
  check (composition_rate in (1, 5, 6));

-- ============================================================
-- C. GSTR-1
-- ============================================================
-- Sections (field names as 0040, plus):
--   b2cs  : supply_type INTRA / INTER
--   nil   : [{supply_type INTRB2B|INTRAB2B|INTRB2C|INTRAB2C, nil_amount,
--            exempt_amount, non_gst_amount}]
--   hsn   : supply B2B / B2C; quantity never negative, 0 for services
--   docs  : [{doc_num 1 (invoices) | 5 (credit notes), nature, series,
--            from_no, to_no, total, cancelled}]
--   warnings: see the end
--   hsn_digits: 4 (turnover up to ₹5 crore) or 6
create or replace function public.get_gstr1_impl(p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_home     text;
  v_digits   int;
  v_result   jsonb;
begin
  select state_code, case when turnover_band = 'above_5cr' then 6 else 4 end
    into v_home, v_digits
    from public.businesses where id = v_business;

  with inv as (
    select i.id, i.invoice_no, public.ist_date(i.invoice_date) as doc_date, i.total,
           coalesce(nullif(c.name, ''), i.customer_name) as party_name,
           i.customer_gstin as gstin,
           coalesce(nullif(i.place_of_supply, ''), v_home) as pos,
           public.is_valid_gstin(i.customer_gstin) as registered,
           public.gst_is_inter_state(i.business_id, i.place_of_supply) as inter
    from public.invoices i
    left join public.customers c on c.id = i.customer_id
    where i.business_id = v_business and not i.is_cancelled
      and i.invoice_type in ('gst', 'non_gst', 'cash_memo')
      and public.ist_date(i.invoice_date) between p_from and p_to),
  inv_k as (
    select inv.*, case when registered then 'b2b'
                       when inter and total > (case when doc_date < date '2024-08-01'
                                                    then 250000 else 100000 end) then 'b2cl'
                       else 'b2cs' end as kind
    from inv),
  inv_l as (
    select k.id, k.kind, k.registered, k.inter, k.pos, ii.gst_rate, ii.gst_category,
           ii.taxable_value, ii.igst_amount, ii.cgst_amount, ii.sgst_amount,
           ii.hsn_code, ii.product_name, ii.unit_name, ii.quantity, 1 as sign
    from inv_k k join public.invoice_items ii on ii.invoice_id = k.id),
  -- Returns: on a tax invoice a credit note; on a bill of supply or cash
  -- memo (no credit note) they still reduce Table 8 and the HSN summary.
  cn as (
    select sr.id, sr.credit_note_no, public.ist_date(sr.return_date) as doc_date, sr.total,
           coalesce(nullif(c.name, ''), i.customer_name) as party_name,
           coalesce(nullif(sr.customer_gstin, ''), i.customer_gstin) as gstin,
           coalesce(nullif(coalesce(nullif(sr.place_of_supply, ''), i.place_of_supply), ''), v_home) as pos,
           public.is_valid_gstin(coalesce(nullif(sr.customer_gstin, ''), i.customer_gstin)) as registered,
           public.gst_is_inter_state(sr.business_id,
             coalesce(nullif(sr.place_of_supply, ''), i.place_of_supply)) as inter,
           i.invoice_no, public.ist_date(i.invoice_date) as invoice_date, i.total as invoice_total
    from public.sale_returns sr
    join public.invoices i on i.id = sr.invoice_id
    left join public.customers c on c.id = i.customer_id
    where sr.business_id = v_business
      and i.invoice_type in ('gst', 'non_gst', 'cash_memo')
      and public.ist_date(sr.return_date) between p_from and p_to),
  cn_k as (
    select cn.*, case when credit_note_no is null then (case when registered then 'b2b' else 'b2cs' end)
                      when registered then 'cdnr'
                      when inter and invoice_total > (case when invoice_date < date '2024-08-01'
                                                           then 250000 else 100000 end) then 'cdnur'
                      else 'b2cs' end as kind
    from cn),
  cn_l as (
    select k.id, k.kind, k.registered, k.inter, k.pos, sri.gst_rate, sri.gst_category,
           sri.taxable_value, sri.igst_amount, sri.cgst_amount, sri.sgst_amount,
           sri.hsn_code, sri.product_name, sri.unit_name, sri.quantity, -1 as sign
    from cn_k k join public.sale_return_items sri on sri.sale_return_id = k.id),
  all_l as (
    select * from inv_l
    union all
    select * from cn_l),
  hsn_g as (
    select case when registered then 'B2B' else 'B2C' end as supply,
           hsn_code, left(min(product_name), 30) as description,
           public.gst_uqc(unit_name, hsn_code) as uqc,
           gst_rate,
           sum(sign * quantity) as net_quantity,
           sum(sign * taxable_value) as taxable_value, sum(sign * igst_amount) as igst_amount,
           sum(sign * cgst_amount) as cgst_amount, sum(sign * sgst_amount) as sgst_amount
    from all_l
    where gst_category in ('taxable', 'nil', 'exempt')
    group by 1, hsn_code, public.gst_uqc(unit_name, hsn_code), gst_rate),
  inv_series as (
    select i.invoice_no, i.is_cancelled,
           regexp_replace(i.invoice_no, '[0-9]+$', '') as series
    from public.invoices i
    where i.business_id = v_business
      and i.invoice_type in ('gst', 'non_gst', 'cash_memo')
      and public.ist_date(i.invoice_date) between p_from and p_to),
  cn_series as (
    select sr.credit_note_no as invoice_no, false as is_cancelled,
           regexp_replace(sr.credit_note_no, '[0-9]+$', '') as series
    from public.sale_returns sr
    where sr.business_id = v_business and sr.credit_note_no is not null
      and public.ist_date(sr.return_date) between p_from and p_to)
  select jsonb_build_object(
    'b2b', coalesce((select jsonb_agg(row_to_json(t)) from (
      select l.gstin, l.party_name as receiver_name, l.invoice_no, l.doc_date as invoice_date,
             l.total as invoice_value, l.pos as place_of_supply, 'N' as reverse_charge,
             'Regular B2B' as invoice_type, l.inter, ii.gst_rate,
             sum(ii.taxable_value) as taxable_value, sum(ii.igst_amount) as igst_amount,
             sum(ii.cgst_amount) as cgst_amount, sum(ii.sgst_amount) as sgst_amount, 0 as cess_amount
      from inv_k l join public.invoice_items ii on ii.invoice_id = l.id
      where l.kind = 'b2b' and ii.gst_category = 'taxable'
      group by l.id, l.gstin, l.party_name, l.invoice_no, l.doc_date, l.total, l.pos, l.inter, ii.gst_rate
      order by l.doc_date, l.invoice_no, ii.gst_rate) t), '[]'::jsonb),
    'b2cl', coalesce((select jsonb_agg(row_to_json(t)) from (
      select l.invoice_no, l.doc_date as invoice_date, l.total as invoice_value,
             l.pos as place_of_supply, ii.gst_rate,
             sum(ii.taxable_value) as taxable_value, sum(ii.igst_amount) as igst_amount, 0 as cess_amount
      from inv_k l join public.invoice_items ii on ii.invoice_id = l.id
      where l.kind = 'b2cl' and ii.gst_category = 'taxable'
      group by l.id, l.invoice_no, l.doc_date, l.total, l.pos, ii.gst_rate
      order by l.doc_date, l.invoice_no, ii.gst_rate) t), '[]'::jsonb),
    'b2cs', coalesce((select jsonb_agg(row_to_json(t)) from (
      select 'OE' as type, pos as place_of_supply,
             case when inter then 'INTER' else 'INTRA' end as supply_type, gst_rate,
             sum(sign * taxable_value) as taxable_value, sum(sign * igst_amount) as igst_amount,
             sum(sign * cgst_amount) as cgst_amount, sum(sign * sgst_amount) as sgst_amount,
             0 as cess_amount
      from all_l where kind = 'b2cs' and gst_category = 'taxable'
      group by pos, inter, gst_rate
      order by pos, gst_rate) t), '[]'::jsonb),
    'cdnr', coalesce((select jsonb_agg(row_to_json(t)) from (
      select k.gstin, k.party_name as receiver_name, k.credit_note_no as note_no, k.doc_date as note_date,
             'C' as note_type, k.pos as place_of_supply, 'N' as reverse_charge,
             'Regular B2B' as note_supply_type, k.total as note_value, k.inter,
             k.invoice_no, k.invoice_date, sri.gst_rate,
             sum(sri.taxable_value) as taxable_value, sum(sri.igst_amount) as igst_amount,
             sum(sri.cgst_amount) as cgst_amount, sum(sri.sgst_amount) as sgst_amount, 0 as cess_amount
      from cn_k k join public.sale_return_items sri on sri.sale_return_id = k.id
      where k.kind = 'cdnr' and sri.gst_category = 'taxable'
      group by k.id, k.gstin, k.party_name, k.credit_note_no, k.doc_date, k.pos, k.total, k.inter,
               k.invoice_no, k.invoice_date, sri.gst_rate
      order by k.doc_date, k.credit_note_no, sri.gst_rate) t), '[]'::jsonb),
    'cdnur', coalesce((select jsonb_agg(row_to_json(t)) from (
      select 'B2CL' as ur_type, k.credit_note_no as note_no, k.doc_date as note_date,
             'C' as note_type, k.pos as place_of_supply, k.total as note_value,
             k.invoice_no, k.invoice_date, sri.gst_rate,
             sum(sri.taxable_value) as taxable_value, sum(sri.igst_amount) as igst_amount, 0 as cess_amount
      from cn_k k join public.sale_return_items sri on sri.sale_return_id = k.id
      where k.kind = 'cdnur' and sri.gst_category = 'taxable'
      group by k.id, k.credit_note_no, k.doc_date, k.pos, k.total, k.invoice_no, k.invoice_date, sri.gst_rate
      order by k.doc_date, k.credit_note_no, sri.gst_rate) t), '[]'::jsonb),
    'nil', coalesce((select jsonb_agg(row_to_json(t)) from (
      select case when inter and registered then 'INTRB2B'
                  when not inter and registered then 'INTRAB2B'
                  when inter then 'INTRB2C'
                  else 'INTRAB2C' end as supply_type,
             coalesce(sum(sign * taxable_value) filter (where gst_category = 'nil'), 0) as nil_amount,
             coalesce(sum(sign * taxable_value) filter (where gst_category = 'exempt'), 0) as exempt_amount,
             coalesce(sum(sign * taxable_value) filter (where gst_category = 'non_gst'), 0) as non_gst_amount
      from all_l where gst_category in ('nil', 'exempt', 'non_gst')
      group by 1 order by 1) t), '[]'::jsonb),
    'hsn', coalesce((select jsonb_agg(row_to_json(t)) from (
      select supply, hsn_code, description, uqc,
             case when uqc = 'NA' then 0 else greatest(net_quantity, 0) end as quantity,
             taxable_value + igst_amount + cgst_amount + sgst_amount as total_value,
             gst_rate, taxable_value, igst_amount, cgst_amount, sgst_amount, 0 as cess_amount
      from hsn_g
      order by supply, hsn_code, gst_rate) t), '[]'::jsonb),
    'docs', coalesce((select jsonb_agg(row_to_json(t)) from (
      select 1 as doc_num, 'Invoices for outward supply' as nature, series,
             (array_agg(invoice_no order by length(invoice_no), invoice_no))[1] as from_no,
             (array_agg(invoice_no order by length(invoice_no) desc, invoice_no desc))[1] as to_no,
             count(*) as total, count(*) filter (where is_cancelled) as cancelled
      from inv_series group by series
      union all
      select 5, 'Credit notes', series,
             (array_agg(invoice_no order by length(invoice_no), invoice_no))[1],
             (array_agg(invoice_no order by length(invoice_no) desc, invoice_no desc))[1],
             count(*), 0
      from cn_series group by series
      order by 1, 3) t), '[]'::jsonb),
    'hsn_digits', v_digits,
    'warnings', jsonb_build_object(
      -- B2B lines must carry HSN (4 digits up to ₹5 crore); above ₹5 crore
      -- every line needs 6.
      'lines_without_hsn', (select count(*) from all_l
        where sign = 1 and gst_category in ('taxable', 'nil', 'exempt') and hsn_code = ''
          and (registered or v_digits = 6)),
      'short_hsn_codes', (select count(*) from all_l
        where sign = 1 and gst_category in ('taxable', 'nil', 'exempt') and hsn_code <> ''
          and length(hsn_code) < v_digits and (registered or v_digits = 6)),
      'invalid_customer_gstins', (select count(*) from inv where gstin <> '' and not registered),
      'invoices_without_state', (select count(*) from inv where coalesce(pos, '') = ''),
      -- Taxable products sold without GST on a bill of supply or cash memo.
      'untaxed_bills', (select count(distinct id) from inv_l where gst_category = 'untaxed'),
      'untaxed_value', (select coalesce(sum(taxable_value), 0) from inv_l where gst_category = 'untaxed'),
      -- More returned than sold in the period: reported as 0.
      'hsn_negative_quantity', (select count(*) from hsn_g where net_quantity < 0 and uqc <> 'NA'),
      'b2cs_negative', (select count(*) from (
          select sum(sign * taxable_value) as v from all_l
          where kind = 'b2cs' and gst_category = 'taxable'
          group by pos, gst_rate) s where v < 0))
  ) into v_result;

  return v_result;
end $$;

-- ============================================================
-- D. GSTR-3B
-- ============================================================
create or replace function public.get_gstr3b_impl(p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_home     text;
  v_result   jsonb;
begin
  select state_code into v_home from public.businesses where id = v_business;

  with out_l as (
    select ii.gst_category, ii.taxable_value, ii.igst_amount, ii.cgst_amount, ii.sgst_amount,
           i.place_of_supply as pos, public.is_valid_gstin(i.customer_gstin) as registered,
           public.gst_is_inter_state(i.business_id, i.place_of_supply) as inter, 1 as sign
    from public.invoice_items ii join public.invoices i on i.id = ii.invoice_id
    where i.business_id = v_business and not i.is_cancelled
      and i.invoice_type in ('gst', 'non_gst', 'cash_memo')
      and public.ist_date(i.invoice_date) between p_from and p_to
    union all
    select sri.gst_category, sri.taxable_value, sri.igst_amount, sri.cgst_amount, sri.sgst_amount,
           coalesce(nullif(sr.place_of_supply, ''), i.place_of_supply),
           public.is_valid_gstin(coalesce(nullif(sr.customer_gstin, ''), i.customer_gstin)),
           public.gst_is_inter_state(sr.business_id, coalesce(nullif(sr.place_of_supply, ''), i.place_of_supply)),
           -1
    from public.sale_return_items sri
    join public.sale_returns sr on sr.id = sri.sale_return_id
    join public.invoices i on i.id = sr.invoice_id
    where sr.business_id = v_business
      and i.invoice_type in ('gst', 'non_gst', 'cash_memo')
      and public.ist_date(sr.return_date) between p_from and p_to),
  in_l as (
    select pi.igst_amount, pi.cgst_amount, pi.sgst_amount, pi.gst_rate,
           pi.quantity * pi.unit_price - pi.discount_amount as taxable_value,
           public.is_valid_gstin(p.supplier_gstin) as eligible,
           (coalesce(p.supplier_state, '') not in ('', coalesce(v_home, ''))) as inter, 1 as sign
    from public.purchase_items pi join public.purchases p on p.id = pi.purchase_id
    where p.business_id = v_business and p.purchase_date between p_from and p_to
    union all
    select pri.igst_amount, pri.cgst_amount, pri.sgst_amount, pri.gst_rate, pri.taxable_value,
           public.is_valid_gstin(pr.supplier_gstin),
           (coalesce(pr.supplier_state, '') not in ('', coalesce(v_home, ''))), -1
    from public.purchase_return_items pri join public.purchase_returns pr on pr.id = pri.purchase_return_id
    where pr.business_id = v_business and pr.debit_note_no is not null
      and pr.return_date between p_from and p_to)
  select jsonb_build_object(
    'outward_taxable', (select jsonb_build_object(
        'taxable_value', coalesce(sum(sign * taxable_value), 0),
        'igst_amount', coalesce(sum(sign * igst_amount), 0),
        'cgst_amount', coalesce(sum(sign * cgst_amount), 0),
        'sgst_amount', coalesce(sum(sign * sgst_amount), 0))
      from out_l where gst_category = 'taxable'),
    'outward_nil_exempt', (select jsonb_build_object(
        'taxable_value', coalesce(sum(sign * taxable_value), 0))
      from out_l where gst_category in ('nil', 'exempt')),
    'outward_non_gst', (select jsonb_build_object(
        'taxable_value', coalesce(sum(sign * taxable_value), 0))
      from out_l where gst_category = 'non_gst'),
    'untaxed_value', (select coalesce(sum(sign * taxable_value), 0)
      from out_l where gst_category = 'untaxed'),
    'inter_state_unregistered', coalesce((select jsonb_agg(row_to_json(t)) from (
      select pos as place_of_supply,
             sum(sign * taxable_value) as taxable_value, sum(sign * igst_amount) as igst_amount
      from out_l where inter and not registered and gst_category = 'taxable'
      group by pos order by pos) t), '[]'::jsonb),
    'itc_available', (select jsonb_build_object(
        'igst_amount', coalesce(sum(sign * igst_amount), 0),
        'cgst_amount', coalesce(sum(sign * cgst_amount), 0),
        'sgst_amount', coalesce(sum(sign * sgst_amount), 0))
      from in_l where eligible),
    'tax_on_unregistered_purchases', (select coalesce(sum(sign * (igst_amount + cgst_amount + sgst_amount)), 0)
      from in_l where not eligible),
    -- Table 5: purchases of nil-rated / exempt goods, inter / intra state.
    'inward_nil_exempt', (select jsonb_build_object(
        'inter', coalesce(sum(sign * taxable_value) filter (where inter), 0),
        'intra', coalesce(sum(sign * taxable_value) filter (where not inter), 0))
      from in_l where gst_rate = 0)
  ) into v_result;

  return v_result;
end $$;

-- ============================================================
-- E. Composition return: CMP-08 (a quarter) / GSTR-4 (a year)
-- ============================================================
-- Turnover from every bill (net of returns); tax on the taxable part at
-- the shop's composition rate, half CGST, half SGST. Purchases split by
-- registered / unregistered supplier (GSTR-4 Table 4).
create or replace function public.get_composition_return_impl(p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_rate     numeric;
  v_turn     numeric;
  v_taxable  numeric;
  v_tax      numeric;
  v_result   jsonb;
begin
  select composition_rate into v_rate from public.businesses where id = v_business;

  with l as (
    select ii.gst_category, ii.taxable_value as value, 1 as sign
    from public.invoice_items ii join public.invoices i on i.id = ii.invoice_id
    where i.business_id = v_business and not i.is_cancelled
      and i.invoice_type in ('gst', 'non_gst', 'cash_memo')
      and public.ist_date(i.invoice_date) between p_from and p_to
    union all
    select sri.gst_category, sri.taxable_value, -1
    from public.sale_return_items sri
    join public.sale_returns sr on sr.id = sri.sale_return_id
    join public.invoices i on i.id = sr.invoice_id
    where sr.business_id = v_business
      and i.invoice_type in ('gst', 'non_gst', 'cash_memo')
      and public.ist_date(sr.return_date) between p_from and p_to)
  select coalesce(sum(sign * value), 0),
         coalesce(sum(sign * value) filter (where gst_category not in ('nil', 'exempt', 'non_gst')), 0)
    into v_turn, v_taxable
    from l;

  v_tax := round(greatest(v_taxable, 0) * coalesce(v_rate, 1) / 100, 2);

  select jsonb_build_object(
    'rate', coalesce(v_rate, 1),
    'turnover', v_turn,
    'taxable_turnover', v_taxable,
    'exempt_turnover', v_turn - v_taxable,
    'tax', v_tax,
    'cgst', round(v_tax / 2, 2),
    'sgst', v_tax - round(v_tax / 2, 2),
    'inward_registered', (select jsonb_build_object(
        'taxable_value', coalesce(sum(pi.quantity * pi.unit_price - pi.discount_amount), 0),
        'igst_amount', coalesce(sum(pi.igst_amount), 0),
        'cgst_amount', coalesce(sum(pi.cgst_amount), 0),
        'sgst_amount', coalesce(sum(pi.sgst_amount), 0))
      from public.purchase_items pi join public.purchases p on p.id = pi.purchase_id
      where p.business_id = v_business and p.purchase_date between p_from and p_to
        and public.is_valid_gstin(p.supplier_gstin)),
    'inward_unregistered', (select jsonb_build_object(
        'taxable_value', coalesce(sum(pi.quantity * pi.unit_price - pi.discount_amount), 0))
      from public.purchase_items pi join public.purchases p on p.id = pi.purchase_id
      where p.business_id = v_business and p.purchase_date between p_from and p_to
        and not public.is_valid_gstin(p.supplier_gstin))
  ) into v_result;
  return v_result;
end $$;

revoke execute on function public.get_composition_return_impl(date, date) from public, anon, authenticated;

create or replace function public.get_composition_return(p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_reports();
  return public.get_composition_return_impl(p_from, p_to);
end $$;

revoke execute on function public.get_composition_return(date, date) from public, anon;
grant execute on function public.get_composition_return(date, date) to authenticated;
