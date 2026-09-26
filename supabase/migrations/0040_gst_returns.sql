-- ============================================================
-- 0040_gst_returns.sql — release R1, GST batch (LAUNCH_SPECIFICATION.md
-- "GST and tax", D40, PD26)
--
--   A. Helpers: Indian business dates, financial-year document numbers,
--      GSTIN check-digit validation, GST unit codes (UQC)
--   B. Bill discounts reduce the taxable value. Prices are tax-inclusive
--      and the bill discount comes off the tax-inclusive total, so each
--      line's taxable value and tax are scaled by the same share. The
--      amount the customer pays doesn't change — only the split between
--      value and tax, which was overstated before.
--   C. Invoices keep the customer's GSTIN as it was when billed
--   D. Credit notes for returns on tax invoices (own series per financial
--      year) and debit notes for purchase returns, with the tax split
--   E. Reports: GST summary (updated), GSTR-1, GSTR-3B, purchase register
--
-- Run AFTER 0039.
-- ============================================================

-- ============================================================
-- A. Helpers
-- ============================================================

-- Shops work in Indian time; a bill at 00:30 IST belongs to that day,
-- not to the previous UTC day.
create or replace function public.ist_date(p timestamptz)
returns date language sql immutable as $$
  select (p at time zone 'Asia/Kolkata')::date;
$$;

-- Financial year (April–March) label: 2026-09-26 → '26-27'.
create or replace function public.fy_label(p date)
returns text language sql immutable as $$
  select lpad((fy % 100)::text, 2, '0') || '-' || lpad(((fy + 1) % 100)::text, 2, '0')
  from (select case when extract(month from p) >= 4 then extract(year from p)::int
                    else extract(year from p)::int - 1 end as fy) t;
$$;

-- 'CN/26-27/00001' — a separate, gap-free series per financial year,
-- at most 16 characters as GST rules require.
create or replace function public.next_fy_doc_no(
  p_business uuid, p_doc_type text, p_prefix text, p_date date)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_fy      text := public.fy_label(p_date);
  v_counter bigint;
begin
  insert into public.doc_counters (business_id, doc_type, counter)
  values (p_business, p_doc_type || ':' || v_fy, 1)
  on conflict (business_id, doc_type)
  do update set counter = public.doc_counters.counter + 1
  returning counter into v_counter;
  return p_prefix || '/' || v_fy || '/' || lpad(v_counter::text, 5, '0');
end $$;

-- GSTIN: 15 characters, valid state code, correct check digit (mod-36).
-- Mirrors isValidGstin() in apps/mobile/lib/core/gst.dart.
create or replace function public.is_valid_gstin(p text)
returns boolean language plpgsql immutable as $$
declare
  v     text := upper(trim(coalesce(p, '')));
  chars constant text := '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  s     int := 0;
  prod  int;
begin
  if v !~ '^[0-9]{2}[A-Z0-9]{13}$' or not public.is_gst_state_code(left(v, 2)) then
    return false;
  end if;
  for i in 1..14 loop
    prod := (strpos(chars, substr(v, i, 1)) - 1) * (case when i % 2 = 0 then 2 else 1 end);
    s := s + prod / 36 + prod % 36;
  end loop;
  return substr(chars, (36 - s % 36) % 36 + 1, 1) = substr(v, 15, 1);
end $$;

-- GST unit quantity code for the HSN summary. Services (SAC 99…) use NA.
create or replace function public.gst_uqc(p_unit text, p_hsn text default '')
returns text language sql immutable as $$
  select case
    when coalesce(p_hsn, '') like '99%' then 'NA'
    else case lower(trim(coalesce(p_unit, '')))
      when 'pcs' then 'PCS' when 'pc' then 'PCS' when 'piece' then 'PCS' when 'pieces' then 'PCS'
      when 'nos' then 'NOS' when 'no' then 'NOS' when 'number' then 'NOS'
      when 'kg' then 'KGS' when 'kgs' then 'KGS' when 'kilogram' then 'KGS'
      when 'g' then 'GMS' when 'gm' then 'GMS' when 'gram' then 'GMS' when 'grams' then 'GMS'
      when 'm' then 'MTR' when 'mtr' then 'MTR' when 'metre' then 'MTR' when 'meter' then 'MTR'
      when 'cm' then 'CMS' when 'mm' then 'OTH'
      when 'l' then 'LTR' when 'ltr' then 'LTR' when 'litre' then 'LTR' when 'liter' then 'LTR'
      when 'ml' then 'MLT'
      when 'box' then 'BOX' when 'dz' then 'DOZ' when 'doz' then 'DOZ' when 'dozen' then 'DOZ'
      when 'set' then 'SET' when 'pair' then 'PRS' when 'prs' then 'PRS'
      when 'roll' then 'ROL' when 'bag' then 'BAG' when 'bundle' then 'BDL'
      when 'pack' then 'PAC' when 'pkt' then 'PAC' when 'packet' then 'PAC'
      when 'bottle' then 'BTL' when 'can' then 'CAN' when 'carton' then 'CTN' when 'tube' then 'TUB'
      when 'sqft' then 'SQF' when 'sq ft' then 'SQF' when 'sqm' then 'SQM' when 'sq m' then 'SQM'
      when 'ton' then 'TON' when 'tonne' then 'TON' when 'quintal' then 'QTL'
      else 'OTH' end
  end;
$$;

revoke execute on function public.next_fy_doc_no(uuid, text, text, date) from public, anon, authenticated;

-- ============================================================
-- B. Bill discount inside the taxable value
-- ============================================================
alter table public.invoice_items add column if not exists taxable_value numeric(14,2) not null default 0;

-- Share of the tax-inclusive total that remains after the bill discount.
create or replace function public.invoice_discount_factor(p_invoice uuid)
returns numeric language sql stable security definer set search_path = public as $$
  select case when (subtotal + tax_amount) > 0
              then greatest(subtotal + tax_amount - discount_amount, 0) / (subtotal + tax_amount)
              else 1 end
  from public.invoices where id = p_invoice;
$$;

-- Replaces 0036's version: taxable value and tax after the bill discount,
-- then CGST + SGST or IGST by place of supply.
create or replace function public.split_invoice_item_tax()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_pos    text;
  v_factor numeric;
  v_tax    numeric(12,2);
begin
  select place_of_supply into v_pos from public.invoices where id = new.invoice_id;
  v_factor := coalesce(public.invoice_discount_factor(new.invoice_id), 1);
  new.taxable_value := round((new.quantity * new.unit_price - new.discount_amount) * v_factor, 2);
  v_tax := round(new.tax_amount * v_factor, 2);
  if public.gst_is_inter_state(new.business_id, v_pos) then
    new.igst_amount := v_tax;
    new.cgst_amount := 0;
    new.sgst_amount := 0;
  else
    new.igst_amount := 0;
    new.cgst_amount := round(v_tax / 2, 2);
    new.sgst_amount := v_tax - round(v_tax / 2, 2);
  end if;
  return new;
end $$;

drop trigger if exists trg_invoice_items_tax_split on public.invoice_items;
create trigger trg_invoice_items_tax_split
  before insert or update of tax_amount, quantity, unit_price, discount_amount on public.invoice_items
  for each row execute function public.split_invoice_item_tax();

-- A new place of supply or new bill totals (update_invoice) re-split the
-- lines. Naming tax_amount in SET fires the line trigger above.
create or replace function public.resplit_invoice_on_pos_change()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.place_of_supply is distinct from old.place_of_supply
     or new.discount_amount is distinct from old.discount_amount
     or new.subtotal is distinct from old.subtotal
     or new.tax_amount is distinct from old.tax_amount then
    update public.invoice_items set tax_amount = tax_amount where invoice_id = new.id;
  end if;
  return new;
end $$;

drop trigger if exists trg_invoices_pos_resplit on public.invoices;
create trigger trg_invoices_pos_resplit
  after update of place_of_supply, discount_amount, subtotal, tax_amount on public.invoices
  for each row execute function public.resplit_invoice_on_pos_change();

-- ============================================================
-- C. Customer / supplier GSTIN snapshots
-- ============================================================
alter table public.invoices add column if not exists customer_gstin text not null default '';
alter table public.purchases add column if not exists supplier_gstin text not null default '';

create or replace function public.snapshot_invoice_customer_gstin()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' or new.customer_id is distinct from old.customer_id then
    new.customer_gstin := coalesce((
      select upper(trim(gst_number)) from public.customers
      where id = new.customer_id and business_id = new.business_id), '');
  end if;
  return new;
end $$;

drop trigger if exists trg_invoices_customer_gstin on public.invoices;
create trigger trg_invoices_customer_gstin before insert or update of customer_id on public.invoices
  for each row execute function public.snapshot_invoice_customer_gstin();

create or replace function public.snapshot_purchase_supplier_gstin()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' or new.supplier_id is distinct from old.supplier_id then
    new.supplier_gstin := coalesce((
      select upper(trim(gst_number)) from public.suppliers
      where id = new.supplier_id and business_id = new.business_id), '');
  end if;
  return new;
end $$;

drop trigger if exists trg_purchases_supplier_gstin on public.purchases;
create trigger trg_purchases_supplier_gstin before insert or update of supplier_id on public.purchases
  for each row execute function public.snapshot_purchase_supplier_gstin();

-- ============================================================
-- D. Credit notes (sale returns) and debit notes (purchase returns)
-- ============================================================
alter table public.sale_returns add column if not exists credit_note_no text;
alter table public.sale_returns add column if not exists place_of_supply text not null default '';
alter table public.sale_returns add column if not exists customer_gstin text not null default '';
create unique index if not exists uq_sale_returns_credit_note
  on public.sale_returns (business_id, credit_note_no) where credit_note_no is not null;

alter table public.sale_return_items add column if not exists gst_rate numeric(5,2) not null default 0;
alter table public.sale_return_items add column if not exists hsn_code text not null default '';
alter table public.sale_return_items add column if not exists unit_name text not null default '';
alter table public.sale_return_items add column if not exists taxable_value numeric(14,2) not null default 0;
alter table public.sale_return_items add column if not exists cgst_amount numeric(12,2) not null default 0;
alter table public.sale_return_items add column if not exists sgst_amount numeric(12,2) not null default 0;
alter table public.sale_return_items add column if not exists igst_amount numeric(12,2) not null default 0;

alter table public.purchase_returns add column if not exists debit_note_no text;
alter table public.purchase_returns add column if not exists supplier_state text not null default '';
alter table public.purchase_returns add column if not exists supplier_gstin text not null default '';
create unique index if not exists uq_purchase_returns_debit_note
  on public.purchase_returns (business_id, debit_note_no) where debit_note_no is not null;

alter table public.purchase_return_items add column if not exists gst_rate numeric(5,2) not null default 0;
alter table public.purchase_return_items add column if not exists hsn_code text not null default '';
alter table public.purchase_return_items add column if not exists unit_name text not null default '';
alter table public.purchase_return_items add column if not exists taxable_value numeric(14,2) not null default 0;
alter table public.purchase_return_items add column if not exists cgst_amount numeric(12,2) not null default 0;
alter table public.purchase_return_items add column if not exists sgst_amount numeric(12,2) not null default 0;
alter table public.purchase_return_items add column if not exists igst_amount numeric(12,2) not null default 0;

-- A return against a tax invoice gets a credit note number and inherits
-- the invoice's place of supply and customer GSTIN.
create or replace function public.set_sale_return_credit_note()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_inv record;
begin
  if new.invoice_id is not null then
    select invoice_type, place_of_supply, customer_gstin into v_inv
      from public.invoices where id = new.invoice_id and business_id = new.business_id;
    new.place_of_supply := coalesce(v_inv.place_of_supply, '');
    new.customer_gstin := coalesce(v_inv.customer_gstin, '');
    if v_inv.invoice_type = 'gst' and new.credit_note_no is null then
      new.credit_note_no := public.next_fy_doc_no(
        new.business_id, 'credit_note', 'CN', public.ist_date(new.return_date));
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_sale_returns_credit_note on public.sale_returns;
create trigger trg_sale_returns_credit_note before insert on public.sale_returns
  for each row execute function public.set_sale_return_credit_note();

-- Return lines: rate/HSN/unit from the original bill (else the product);
-- line_total and tax_amount already carry the bill-discount share (0038).
create or replace function public.set_sale_return_item_gst()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_ret  record;
  v_rate numeric;
  v_hsn  text;
  v_unit text;
begin
  select invoice_id, place_of_supply into v_ret
    from public.sale_returns where id = new.sale_return_id;
  if v_ret.invoice_id is not null then
    select max(gst_rate), max(hsn_code), max(unit_name) into v_rate, v_hsn, v_unit
      from public.invoice_items
      where invoice_id = v_ret.invoice_id
        and product_id is not distinct from new.product_id
        and variant_id is not distinct from new.variant_id;
  end if;
  if v_rate is null and new.product_id is not null then
    select p.gst_rate, p.hsn_code, u.short_name into v_rate, v_hsn, v_unit
      from public.products p left join public.units u on u.id = p.unit_id
      where p.id = new.product_id;
  end if;
  new.gst_rate := coalesce(v_rate, 0);
  new.hsn_code := coalesce(v_hsn, '');
  new.unit_name := coalesce(v_unit, '');
  new.taxable_value := new.line_total - new.tax_amount;
  if public.gst_is_inter_state(new.business_id, v_ret.place_of_supply) then
    new.igst_amount := new.tax_amount;
    new.cgst_amount := 0;
    new.sgst_amount := 0;
  else
    new.igst_amount := 0;
    new.cgst_amount := round(new.tax_amount / 2, 2);
    new.sgst_amount := new.tax_amount - round(new.tax_amount / 2, 2);
  end if;
  return new;
end $$;

drop trigger if exists trg_sale_return_items_gst on public.sale_return_items;
create trigger trg_sale_return_items_gst
  before insert or update of tax_amount, line_total on public.sale_return_items
  for each row execute function public.set_sale_return_item_gst();

-- A return of a taxed purchase gets a debit note number (the document the
-- shop sends its supplier) and the purchase's supplier state and GSTIN.
create or replace function public.set_purchase_return_debit_note()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_pur record;
begin
  if new.purchase_id is not null then
    select supplier_state, supplier_gstin, tax_amount into v_pur
      from public.purchases where id = new.purchase_id and business_id = new.business_id;
    new.supplier_state := coalesce(v_pur.supplier_state, '');
    new.supplier_gstin := coalesce(v_pur.supplier_gstin, '');
    if coalesce(v_pur.tax_amount, 0) > 0 and new.debit_note_no is null then
      new.debit_note_no := public.next_fy_doc_no(new.business_id, 'debit_note', 'DN', new.return_date);
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_purchase_returns_debit_note on public.purchase_returns;
create trigger trg_purchase_returns_debit_note before insert on public.purchase_returns
  for each row execute function public.set_purchase_return_debit_note();

create or replace function public.set_purchase_return_item_gst()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_ret  record;
  v_rate numeric;
begin
  select purchase_id, supplier_state into v_ret
    from public.purchase_returns where id = new.purchase_return_id;
  if v_ret.purchase_id is not null then
    select max(gst_rate) into v_rate from public.purchase_items
      where purchase_id = v_ret.purchase_id
        and product_id is not distinct from new.product_id
        and variant_id is not distinct from new.variant_id;
  end if;
  if new.product_id is not null then
    select coalesce(v_rate, p.gst_rate), p.hsn_code, u.short_name
      into v_rate, new.hsn_code, new.unit_name
      from public.products p left join public.units u on u.id = p.unit_id
      where p.id = new.product_id;
  end if;
  new.gst_rate := coalesce(v_rate, 0);
  new.hsn_code := coalesce(new.hsn_code, '');
  new.unit_name := coalesce(new.unit_name, '');
  new.taxable_value := new.line_total - new.tax_amount;
  if public.gst_is_inter_state(new.business_id, v_ret.supplier_state) then
    new.igst_amount := new.tax_amount;
    new.cgst_amount := 0;
    new.sgst_amount := 0;
  else
    new.igst_amount := 0;
    new.cgst_amount := round(new.tax_amount / 2, 2);
    new.sgst_amount := new.tax_amount - round(new.tax_amount / 2, 2);
  end if;
  return new;
end $$;

drop trigger if exists trg_purchase_return_items_gst on public.purchase_return_items;
create trigger trg_purchase_return_items_gst
  before insert or update of tax_amount, line_total on public.purchase_return_items
  for each row execute function public.set_purchase_return_item_gst();

-- ---------- backfill ----------
-- The backfill changes no references, so the tenant-reference check (0037)
-- is paused for it: rows written before 0037 must not block this migration.
alter table public.invoices              disable trigger trg_00_tenant_refs;
alter table public.invoice_items         disable trigger trg_00_tenant_refs;
alter table public.purchases             disable trigger trg_00_tenant_refs;
alter table public.sale_returns          disable trigger trg_00_tenant_refs;
alter table public.sale_return_items     disable trigger trg_00_tenant_refs;
alter table public.purchase_returns      disable trigger trg_00_tenant_refs;
alter table public.purchase_return_items disable trigger trg_00_tenant_refs;

update public.invoices i set customer_gstin = upper(trim(c.gst_number))
  from public.customers c
  where c.id = i.customer_id and i.customer_gstin = '' and c.gst_number <> '';
update public.purchases p set supplier_gstin = upper(trim(s.gst_number))
  from public.suppliers s
  where s.id = p.supplier_id and p.supplier_gstin = '' and s.gst_number <> '';

-- Every existing line gets its after-discount taxable value and split.
update public.invoice_items set tax_amount = tax_amount;

update public.sale_returns sr
   set place_of_supply = i.place_of_supply, customer_gstin = i.customer_gstin
  from public.invoices i
  where i.id = sr.invoice_id;
update public.purchase_returns pr
   set supplier_state = p.supplier_state, supplier_gstin = p.supplier_gstin
  from public.purchases p
  where p.id = pr.purchase_id;

-- Credit/debit note numbers for earlier returns, in date order.
do $$
declare r record;
begin
  for r in
    select sr.id, sr.business_id, sr.return_date
    from public.sale_returns sr join public.invoices i on i.id = sr.invoice_id
    where sr.credit_note_no is null and i.invoice_type = 'gst'
    order by sr.return_date, sr.created_at
  loop
    update public.sale_returns
       set credit_note_no = public.next_fy_doc_no(r.business_id, 'credit_note', 'CN', public.ist_date(r.return_date))
     where id = r.id;
  end loop;
  for r in
    select pr.id, pr.business_id, pr.return_date
    from public.purchase_returns pr join public.purchases p on p.id = pr.purchase_id
    where pr.debit_note_no is null and p.tax_amount > 0
    order by pr.return_date, pr.created_at
  loop
    update public.purchase_returns
       set debit_note_no = public.next_fy_doc_no(r.business_id, 'debit_note', 'DN', r.return_date)
     where id = r.id;
  end loop;
end $$;

update public.sale_return_items set tax_amount = tax_amount;
update public.purchase_return_items set tax_amount = tax_amount;

alter table public.invoices              enable trigger trg_00_tenant_refs;
alter table public.invoice_items         enable trigger trg_00_tenant_refs;
alter table public.purchases             enable trigger trg_00_tenant_refs;
alter table public.sale_returns          enable trigger trg_00_tenant_refs;
alter table public.sale_return_items     enable trigger trg_00_tenant_refs;
alter table public.purchase_returns      enable trigger trg_00_tenant_refs;
alter table public.purchase_return_items enable trigger trg_00_tenant_refs;

-- ============================================================
-- E. Reports
-- ============================================================

-- On-screen GST summary: sales and purchases by rate, plus credit and
-- debit notes, all by Indian date. (Wrapped by get_gst_report, 0037.)
create or replace function public.get_gst_report_impl(p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
begin
  return jsonb_build_object(
    'output_tax', coalesce((select jsonb_agg(row_to_json(t)) from (
      select ii.gst_rate,
             sum(ii.taxable_value) as taxable_value,
             sum(ii.cgst_amount + ii.sgst_amount + ii.igst_amount) as tax_amount,
             sum(ii.cgst_amount) as cgst_amount,
             sum(ii.sgst_amount) as sgst_amount,
             sum(ii.igst_amount) as igst_amount
      from public.invoice_items ii join public.invoices i on i.id = ii.invoice_id
      where i.business_id = v_business and not i.is_cancelled and i.invoice_type = 'gst'
        and public.ist_date(i.invoice_date) between p_from and p_to
      group by ii.gst_rate order by ii.gst_rate) t), '[]'::jsonb),
    'credit_notes', coalesce((select jsonb_agg(row_to_json(t)) from (
      select sri.gst_rate,
             sum(sri.taxable_value) as taxable_value,
             sum(sri.tax_amount)  as tax_amount,
             sum(sri.cgst_amount) as cgst_amount,
             sum(sri.sgst_amount) as sgst_amount,
             sum(sri.igst_amount) as igst_amount
      from public.sale_return_items sri join public.sale_returns sr on sr.id = sri.sale_return_id
      where sr.business_id = v_business and sr.credit_note_no is not null
        and public.ist_date(sr.return_date) between p_from and p_to
      group by sri.gst_rate order by sri.gst_rate) t), '[]'::jsonb),
    'input_tax', coalesce((select jsonb_agg(row_to_json(t)) from (
      select pi.gst_rate,
             sum(pi.quantity * pi.unit_price - pi.discount_amount) as taxable_value,
             sum(pi.tax_amount)  as tax_amount,
             sum(pi.cgst_amount) as cgst_amount,
             sum(pi.sgst_amount) as sgst_amount,
             sum(pi.igst_amount) as igst_amount
      from public.purchase_items pi join public.purchases p on p.id = pi.purchase_id
      where p.business_id = v_business
        and p.purchase_date between p_from and p_to
      group by pi.gst_rate order by pi.gst_rate) t), '[]'::jsonb),
    'debit_notes', coalesce((select jsonb_agg(row_to_json(t)) from (
      select pri.gst_rate,
             sum(pri.taxable_value) as taxable_value,
             sum(pri.tax_amount)  as tax_amount,
             sum(pri.cgst_amount) as cgst_amount,
             sum(pri.sgst_amount) as sgst_amount,
             sum(pri.igst_amount) as igst_amount
      from public.purchase_return_items pri join public.purchase_returns pr on pr.id = pri.purchase_return_id
      where pr.business_id = v_business and pr.debit_note_no is not null
        and pr.return_date between p_from and p_to
      group by pri.gst_rate order by pri.gst_rate) t), '[]'::jsonb)
  );
end $$;

-- GSTR-1 by section, for the shop's accountant. Tax invoices only
-- (bills of supply, cash memos and estimates are not outward tax supplies).
--   b2b   : customer has a valid GSTIN — per invoice and rate
--   b2cl  : unregistered, inter-state, invoice value above ₹1,00,000
--   b2cs  : all other unregistered supplies, by place of supply and rate,
--           net of their credit notes
--   cdnr  : credit notes on B2B invoices; cdnur: on B2CL invoices
--   hsn   : HSN summary net of credit notes, split B2B / B2C
--   docs  : document series issued in the period
create or replace function public.get_gstr1_impl(p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_limit    constant numeric := 100000;
  v_home     text;
  v_result   jsonb;
begin
  select state_code into v_home from public.businesses where id = v_business;

  with inv as (
    select i.id, i.invoice_no, public.ist_date(i.invoice_date) as doc_date, i.total,
           coalesce(nullif(c.name, ''), i.customer_name) as party_name,
           i.customer_gstin as gstin,
           coalesce(nullif(i.place_of_supply, ''), v_home) as pos,
           public.is_valid_gstin(i.customer_gstin) as registered,
           public.gst_is_inter_state(i.business_id, i.place_of_supply) as inter
    from public.invoices i
    left join public.customers c on c.id = i.customer_id
    where i.business_id = v_business and i.invoice_type = 'gst' and not i.is_cancelled
      and public.ist_date(i.invoice_date) between p_from and p_to),
  inv_k as (
    select inv.*, case when registered then 'b2b'
                       when inter and total > v_limit then 'b2cl'
                       else 'b2cs' end as kind
    from inv),
  inv_l as (
    select k.*, ii.gst_rate, ii.taxable_value, ii.igst_amount, ii.cgst_amount, ii.sgst_amount,
           ii.hsn_code, ii.product_name, ii.unit_name, ii.quantity, 1 as sign
    from inv_k k join public.invoice_items ii on ii.invoice_id = k.id),
  cn as (
    select sr.id, sr.credit_note_no, public.ist_date(sr.return_date) as doc_date, sr.total,
           coalesce(nullif(c.name, ''), i.customer_name) as party_name,
           sr.customer_gstin as gstin,
           coalesce(nullif(sr.place_of_supply, ''), v_home) as pos,
           public.is_valid_gstin(sr.customer_gstin) as registered,
           public.gst_is_inter_state(sr.business_id, sr.place_of_supply) as inter,
           i.invoice_no, public.ist_date(i.invoice_date) as invoice_date, i.total as invoice_total
    from public.sale_returns sr
    join public.invoices i on i.id = sr.invoice_id
    left join public.customers c on c.id = i.customer_id
    where sr.business_id = v_business and sr.credit_note_no is not null
      and public.ist_date(sr.return_date) between p_from and p_to),
  cn_k as (
    select cn.*, case when registered then 'cdnr'
                      when inter and invoice_total > v_limit then 'cdnur'
                      else 'b2cs' end as kind
    from cn),
  cn_l as (
    select k.*, sri.gst_rate, sri.taxable_value, sri.igst_amount, sri.cgst_amount, sri.sgst_amount,
           sri.hsn_code, sri.product_name, sri.unit_name, sri.quantity, -1 as sign
    from cn_k k join public.sale_return_items sri on sri.sale_return_id = k.id),
  all_l as (
    select kind, pos, gst_rate, taxable_value, igst_amount, cgst_amount, sgst_amount,
           hsn_code, product_name, unit_name, quantity, sign from inv_l
    union all
    select kind, pos, gst_rate, taxable_value, igst_amount, cgst_amount, sgst_amount,
           hsn_code, product_name, unit_name, quantity, sign from cn_l)
  select jsonb_build_object(
    'b2b', coalesce((select jsonb_agg(row_to_json(t)) from (
      select gstin, party_name as receiver_name, invoice_no, doc_date as invoice_date,
             total as invoice_value, pos as place_of_supply, 'N' as reverse_charge,
             'Regular B2B' as invoice_type, gst_rate,
             sum(taxable_value) as taxable_value, sum(igst_amount) as igst_amount,
             sum(cgst_amount) as cgst_amount, sum(sgst_amount) as sgst_amount, 0 as cess_amount
      from inv_l where kind = 'b2b'
      group by id, gstin, party_name, invoice_no, doc_date, total, pos, gst_rate
      order by doc_date, invoice_no, gst_rate) t), '[]'::jsonb),
    'b2cl', coalesce((select jsonb_agg(row_to_json(t)) from (
      select invoice_no, doc_date as invoice_date, total as invoice_value,
             pos as place_of_supply, gst_rate,
             sum(taxable_value) as taxable_value, sum(igst_amount) as igst_amount, 0 as cess_amount
      from inv_l where kind = 'b2cl'
      group by id, invoice_no, doc_date, total, pos, gst_rate
      order by doc_date, invoice_no, gst_rate) t), '[]'::jsonb),
    'b2cs', coalesce((select jsonb_agg(row_to_json(t)) from (
      select 'OE' as type, pos as place_of_supply, gst_rate,
             sum(sign * taxable_value) as taxable_value, sum(sign * igst_amount) as igst_amount,
             sum(sign * cgst_amount) as cgst_amount, sum(sign * sgst_amount) as sgst_amount,
             0 as cess_amount
      from all_l where kind = 'b2cs'
      group by pos, gst_rate
      order by pos, gst_rate) t), '[]'::jsonb),
    'cdnr', coalesce((select jsonb_agg(row_to_json(t)) from (
      select gstin, party_name as receiver_name, credit_note_no as note_no, doc_date as note_date,
             'C' as note_type, pos as place_of_supply, 'N' as reverse_charge,
             'Regular B2B' as note_supply_type, total as note_value,
             invoice_no, invoice_date, gst_rate,
             sum(taxable_value) as taxable_value, sum(igst_amount) as igst_amount,
             sum(cgst_amount) as cgst_amount, sum(sgst_amount) as sgst_amount, 0 as cess_amount
      from cn_l where kind = 'cdnr'
      group by id, gstin, party_name, credit_note_no, doc_date, pos, total, invoice_no, invoice_date, gst_rate
      order by doc_date, credit_note_no, gst_rate) t), '[]'::jsonb),
    'cdnur', coalesce((select jsonb_agg(row_to_json(t)) from (
      select 'B2CL' as ur_type, credit_note_no as note_no, doc_date as note_date,
             'C' as note_type, pos as place_of_supply, total as note_value,
             invoice_no, invoice_date, gst_rate,
             sum(taxable_value) as taxable_value, sum(igst_amount) as igst_amount, 0 as cess_amount
      from cn_l where kind = 'cdnur'
      group by id, credit_note_no, doc_date, pos, total, invoice_no, invoice_date, gst_rate
      order by doc_date, credit_note_no, gst_rate) t), '[]'::jsonb),
    'hsn', coalesce((select jsonb_agg(row_to_json(t)) from (
      select case when kind in ('b2b', 'cdnr') then 'B2B' else 'B2C' end as supply,
             hsn_code, min(product_name) as description,
             public.gst_uqc(unit_name, hsn_code) as uqc,
             sum(sign * quantity) as quantity,
             sum(sign * (taxable_value + igst_amount + cgst_amount + sgst_amount)) as total_value,
             gst_rate,
             sum(sign * taxable_value) as taxable_value, sum(sign * igst_amount) as igst_amount,
             sum(sign * cgst_amount) as cgst_amount, sum(sign * sgst_amount) as sgst_amount,
             0 as cess_amount
      from all_l
      group by 1, hsn_code, public.gst_uqc(unit_name, hsn_code), gst_rate
      order by 1, hsn_code, gst_rate) t), '[]'::jsonb),
    'docs', jsonb_build_array(
      (select jsonb_build_object(
         'nature', 'Invoices for outward supply',
         'from_no', min(invoice_no), 'to_no', max(invoice_no),
         'total', count(*), 'cancelled', count(*) filter (where is_cancelled))
       from public.invoices
       where business_id = v_business and invoice_type = 'gst'
         and public.ist_date(invoice_date) between p_from and p_to),
      (select jsonb_build_object(
         'nature', 'Credit notes',
         'from_no', min(credit_note_no), 'to_no', max(credit_note_no),
         'total', count(*), 'cancelled', 0)
       from cn)),
    'warnings', jsonb_build_object(
      'lines_without_hsn', (select count(*) from all_l where hsn_code = '' and gst_rate > 0),
      'invalid_customer_gstins', (select count(*) from inv where gstin <> '' and not registered),
      'invoices_without_state', (select count(*) from inv where coalesce(pos, '') = ''))
  ) into v_result;

  return v_result;
end $$;

-- GSTR-3B summary: outward supplies net of credit notes; input tax credit
-- from registered suppliers net of debit notes.
create or replace function public.get_gstr3b_impl(p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_result   jsonb;
begin
  with out_l as (
    select ii.gst_rate, ii.taxable_value, ii.igst_amount, ii.cgst_amount, ii.sgst_amount,
           i.place_of_supply as pos, public.is_valid_gstin(i.customer_gstin) as registered,
           public.gst_is_inter_state(i.business_id, i.place_of_supply) as inter, 1 as sign
    from public.invoice_items ii join public.invoices i on i.id = ii.invoice_id
    where i.business_id = v_business and i.invoice_type = 'gst' and not i.is_cancelled
      and public.ist_date(i.invoice_date) between p_from and p_to
    union all
    select sri.gst_rate, sri.taxable_value, sri.igst_amount, sri.cgst_amount, sri.sgst_amount,
           sr.place_of_supply, public.is_valid_gstin(sr.customer_gstin),
           public.gst_is_inter_state(sr.business_id, sr.place_of_supply), -1
    from public.sale_return_items sri join public.sale_returns sr on sr.id = sri.sale_return_id
    where sr.business_id = v_business and sr.credit_note_no is not null
      and public.ist_date(sr.return_date) between p_from and p_to),
  in_l as (
    select pi.igst_amount, pi.cgst_amount, pi.sgst_amount,
           public.is_valid_gstin(p.supplier_gstin) as eligible, 1 as sign
    from public.purchase_items pi join public.purchases p on p.id = pi.purchase_id
    where p.business_id = v_business and p.purchase_date between p_from and p_to
    union all
    select pri.igst_amount, pri.cgst_amount, pri.sgst_amount,
           public.is_valid_gstin(pr.supplier_gstin), -1
    from public.purchase_return_items pri join public.purchase_returns pr on pr.id = pri.purchase_return_id
    where pr.business_id = v_business and pr.debit_note_no is not null
      and pr.return_date between p_from and p_to)
  select jsonb_build_object(
    'outward_taxable', (select jsonb_build_object(
        'taxable_value', coalesce(sum(sign * taxable_value), 0),
        'igst_amount', coalesce(sum(sign * igst_amount), 0),
        'cgst_amount', coalesce(sum(sign * cgst_amount), 0),
        'sgst_amount', coalesce(sum(sign * sgst_amount), 0))
      from out_l where gst_rate > 0),
    'outward_nil_exempt', (select jsonb_build_object(
        'taxable_value', coalesce(sum(sign * taxable_value), 0))
      from out_l where gst_rate = 0),
    'inter_state_unregistered', coalesce((select jsonb_agg(row_to_json(t)) from (
      select pos as place_of_supply,
             sum(sign * taxable_value) as taxable_value, sum(sign * igst_amount) as igst_amount
      from out_l where inter and not registered and gst_rate > 0
      group by pos order by pos) t), '[]'::jsonb),
    'itc_available', (select jsonb_build_object(
        'igst_amount', coalesce(sum(sign * igst_amount), 0),
        'cgst_amount', coalesce(sum(sign * cgst_amount), 0),
        'sgst_amount', coalesce(sum(sign * sgst_amount), 0))
      from in_l where eligible),
    'tax_on_unregistered_purchases', (select coalesce(sum(sign * (igst_amount + cgst_amount + sgst_amount)), 0)
      from in_l where not eligible)
  ) into v_result;

  return v_result;
end $$;

-- Purchase register: one row per purchase bill (or debit note) and rate.
create or replace function public.get_purchase_register_impl(p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
begin
  return coalesce((select jsonb_agg(row_to_json(t)) from (
    select 'Purchase' as doc_type, p.purchase_date as doc_date, p.purchase_no as doc_no,
           p.bill_no as supplier_bill_no, p.supplier_name, p.supplier_gstin, p.supplier_state,
           pi.gst_rate,
           sum(pi.quantity * pi.unit_price - pi.discount_amount) as taxable_value,
           sum(pi.igst_amount) as igst_amount, sum(pi.cgst_amount) as cgst_amount,
           sum(pi.sgst_amount) as sgst_amount, p.total as bill_total
    from public.purchases p join public.purchase_items pi on pi.purchase_id = p.id
    where p.business_id = v_business and p.purchase_date between p_from and p_to
    group by p.id, p.purchase_date, p.purchase_no, p.bill_no, p.supplier_name,
             p.supplier_gstin, p.supplier_state, pi.gst_rate, p.total
    union all
    select 'Debit note', pr.return_date, pr.debit_note_no,
           coalesce(p.bill_no, ''), coalesce(s.name, ''), pr.supplier_gstin, pr.supplier_state,
           pri.gst_rate,
           -sum(pri.taxable_value), -sum(pri.igst_amount), -sum(pri.cgst_amount),
           -sum(pri.sgst_amount), -pr.total
    from public.purchase_returns pr
    join public.purchase_return_items pri on pri.purchase_return_id = pr.id
    left join public.purchases p on p.id = pr.purchase_id
    left join public.suppliers s on s.id = pr.supplier_id
    where pr.business_id = v_business and pr.debit_note_no is not null
      and pr.return_date between p_from and p_to
    group by pr.id, pr.return_date, pr.debit_note_no, p.bill_no, s.name,
             pr.supplier_gstin, pr.supplier_state, pri.gst_rate, pr.total
    order by 2, 3, 8) t), '[]'::jsonb);
end $$;

revoke execute on function public.get_gstr1_impl(date, date) from public, anon, authenticated;
revoke execute on function public.get_gstr3b_impl(date, date) from public, anon, authenticated;
revoke execute on function public.get_purchase_register_impl(date, date) from public, anon, authenticated;

create or replace function public.get_gstr1(p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_reports();
  return public.get_gstr1_impl(p_from, p_to);
end $$;

create or replace function public.get_gstr3b(p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_reports();
  return public.get_gstr3b_impl(p_from, p_to);
end $$;

create or replace function public.get_purchase_register(p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_reports();
  return public.get_purchase_register_impl(p_from, p_to);
end $$;

revoke execute on function public.get_gstr1(date, date) from public, anon;
revoke execute on function public.get_gstr3b(date, date) from public, anon;
revoke execute on function public.get_purchase_register(date, date) from public, anon;
grant execute on function public.get_gstr1(date, date) to authenticated;
grant execute on function public.get_gstr3b(date, date) to authenticated;
grant execute on function public.get_purchase_register(date, date) to authenticated;
