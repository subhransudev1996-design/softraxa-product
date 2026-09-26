-- ============================================================
-- 0036_gst_place_of_supply.sql — two launch-spec gaps (LAUNCH_SPECIFICATION.md)
--
-- 1. GST place of supply (D40): intra-state supplies show CGST + SGST,
--    inter-state supplies show IGST. Businesses, customers and suppliers get
--    a 2-digit GST state code (auto-filled from the GSTIN's first two digits).
--    Each invoice snapshots its place of supply; each invoice/purchase line
--    stores its tax split. Triggers do the work, so create_invoice /
--    update_invoice / create_purchase are unchanged.
--
-- 2. Explicit unlimited credit (PD17/PD18): credit_limit NULL used to mean
--    "no limit". It now means "unset" and is replaced by the store's default
--    limit (initially 0). Existing customers with no limit are migrated to an
--    explicit credit_unlimited flag, so current shops see no change.
-- ============================================================

-- ---------- state codes ----------
alter table public.businesses add column if not exists state_code text not null default '';
alter table public.customers  add column if not exists state_code text not null default '';
alter table public.suppliers  add column if not exists state_code text not null default '';

-- Valid GST state codes (01–38, 97 = other territory). '' = not set.
create or replace function public.is_gst_state_code(p text)
returns boolean language sql immutable as $$
  select p = '' or p in (
    '01','02','03','04','05','06','07','08','09','10','11','12','13','14','15',
    '16','17','18','19','20','21','22','23','24','26','27','29','30','31','32',
    '33','34','35','36','37','38','97');
$$;

alter table public.businesses drop constraint if exists businesses_state_code_check;
alter table public.businesses add constraint businesses_state_code_check check (public.is_gst_state_code(state_code));
alter table public.customers drop constraint if exists customers_state_code_check;
alter table public.customers add constraint customers_state_code_check check (public.is_gst_state_code(state_code));
alter table public.suppliers drop constraint if exists suppliers_state_code_check;
alter table public.suppliers add constraint suppliers_state_code_check check (public.is_gst_state_code(state_code));

-- Fill an empty state from the GSTIN (its first two digits are the state code).
create or replace function public.fill_state_from_gstin()
returns trigger language plpgsql as $$
begin
  if coalesce(new.state_code, '') = ''
     and left(coalesce(new.gst_number, ''), 2) ~ '^[0-9]{2}$'
     and public.is_gst_state_code(left(new.gst_number, 2)) then
    new.state_code := left(new.gst_number, 2);
  end if;
  return new;
end $$;

drop trigger if exists trg_businesses_state on public.businesses;
create trigger trg_businesses_state before insert or update of gst_number, state_code on public.businesses
  for each row execute function public.fill_state_from_gstin();
drop trigger if exists trg_customers_state on public.customers;
create trigger trg_customers_state before insert or update of gst_number, state_code on public.customers
  for each row execute function public.fill_state_from_gstin();
drop trigger if exists trg_suppliers_state on public.suppliers;
create trigger trg_suppliers_state before insert or update of gst_number, state_code on public.suppliers
  for each row execute function public.fill_state_from_gstin();

-- backfill states from existing GSTINs
update public.businesses set state_code = left(gst_number, 2)
  where state_code = '' and left(gst_number, 2) ~ '^[0-9]{2}$' and public.is_gst_state_code(left(gst_number, 2));
update public.customers set state_code = left(gst_number, 2)
  where state_code = '' and left(gst_number, 2) ~ '^[0-9]{2}$' and public.is_gst_state_code(left(gst_number, 2));
update public.suppliers set state_code = left(gst_number, 2)
  where state_code = '' and left(gst_number, 2) ~ '^[0-9]{2}$' and public.is_gst_state_code(left(gst_number, 2));

-- ---------- invoice / purchase columns ----------
alter table public.invoices add column if not exists place_of_supply text not null default '';
alter table public.invoices drop constraint if exists invoices_place_of_supply_check;
alter table public.invoices add constraint invoices_place_of_supply_check check (public.is_gst_state_code(place_of_supply));

alter table public.invoice_items add column if not exists cgst_amount numeric(12,2) not null default 0;
alter table public.invoice_items add column if not exists sgst_amount numeric(12,2) not null default 0;
alter table public.invoice_items add column if not exists igst_amount numeric(12,2) not null default 0;

-- For purchases the supplier's state decides intra vs inter.
alter table public.purchases add column if not exists supplier_state text not null default '';
alter table public.purchases drop constraint if exists purchases_supplier_state_check;
alter table public.purchases add constraint purchases_supplier_state_check check (public.is_gst_state_code(supplier_state));

alter table public.purchase_items add column if not exists cgst_amount numeric(12,2) not null default 0;
alter table public.purchase_items add column if not exists sgst_amount numeric(12,2) not null default 0;
alter table public.purchase_items add column if not exists igst_amount numeric(12,2) not null default 0;

-- Inter-state only when both states are known and differ; an unknown state
-- keeps the previous behaviour (CGST + SGST).
create or replace function public.gst_is_inter_state(p_business uuid, p_other_state text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(p_other_state, '') <> ''
     and coalesce(b.state_code, '') <> ''
     and b.state_code <> p_other_state
  from public.businesses b where b.id = p_business;
$$;

-- ---------- invoices: place of supply snapshot ----------
-- Default: the customer's state when recorded, otherwise the store's state.
-- The app may change it afterwards (e.g. goods delivered to another state);
-- the line split follows via trg_invoices_pos_resplit.
create or replace function public.set_invoice_place_of_supply()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if coalesce(new.place_of_supply, '') = '' then
    select coalesce(nullif(c.state_code, ''), '') into new.place_of_supply
      from public.customers c
      where c.id = new.customer_id and c.business_id = new.business_id;
    if coalesce(new.place_of_supply, '') = '' then
      select state_code into new.place_of_supply
        from public.businesses where id = new.business_id;
    end if;
    new.place_of_supply := coalesce(new.place_of_supply, '');
  end if;
  return new;
end $$;

drop trigger if exists trg_invoices_pos on public.invoices;
create trigger trg_invoices_pos before insert on public.invoices
  for each row execute function public.set_invoice_place_of_supply();

-- ---------- line split ----------
create or replace function public.split_invoice_item_tax()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_pos text;
begin
  select place_of_supply into v_pos from public.invoices where id = new.invoice_id;
  if public.gst_is_inter_state(new.business_id, v_pos) then
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

drop trigger if exists trg_invoice_items_tax_split on public.invoice_items;
create trigger trg_invoice_items_tax_split before insert or update of tax_amount on public.invoice_items
  for each row execute function public.split_invoice_item_tax();

-- Changing an invoice's place of supply re-splits its lines.
create or replace function public.resplit_invoice_on_pos_change()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.place_of_supply is distinct from old.place_of_supply then
    if public.gst_is_inter_state(new.business_id, new.place_of_supply) then
      update public.invoice_items
        set igst_amount = tax_amount, cgst_amount = 0, sgst_amount = 0
        where invoice_id = new.id;
    else
      update public.invoice_items
        set igst_amount = 0,
            cgst_amount = round(tax_amount / 2, 2),
            sgst_amount = tax_amount - round(tax_amount / 2, 2)
        where invoice_id = new.id;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_invoices_pos_resplit on public.invoices;
create trigger trg_invoices_pos_resplit after update of place_of_supply on public.invoices
  for each row execute function public.resplit_invoice_on_pos_change();

-- ---------- purchases: supplier state snapshot + line split ----------
create or replace function public.set_purchase_supplier_state()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if coalesce(new.supplier_state, '') = '' and new.supplier_id is not null then
    select state_code into new.supplier_state
      from public.suppliers where id = new.supplier_id and business_id = new.business_id;
    new.supplier_state := coalesce(new.supplier_state, '');
  end if;
  return new;
end $$;

drop trigger if exists trg_purchases_supplier_state on public.purchases;
create trigger trg_purchases_supplier_state before insert on public.purchases
  for each row execute function public.set_purchase_supplier_state();

create or replace function public.split_purchase_item_tax()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_state text;
begin
  select supplier_state into v_state from public.purchases where id = new.purchase_id;
  if public.gst_is_inter_state(new.business_id, v_state) then
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

drop trigger if exists trg_purchase_items_tax_split on public.purchase_items;
create trigger trg_purchase_items_tax_split before insert or update of tax_amount on public.purchase_items
  for each row execute function public.split_purchase_item_tax();

-- ---------- backfill existing documents ----------
-- Existing invoices were all printed as CGST + SGST, so they keep the store's
-- state as place of supply (intra-state). Only lines are re-split.
update public.invoices i set place_of_supply = b.state_code
  from public.businesses b
  where b.id = i.business_id and i.place_of_supply = '';
update public.invoice_items
  set cgst_amount = round(tax_amount / 2, 2),
      sgst_amount = tax_amount - round(tax_amount / 2, 2),
      igst_amount = 0
  where cgst_amount = 0 and sgst_amount = 0 and igst_amount = 0 and tax_amount <> 0;

update public.purchases p set supplier_state = s.state_code
  from public.suppliers s
  where s.id = p.supplier_id and p.supplier_state = '';
update public.purchase_items pi
  set igst_amount = case when public.gst_is_inter_state(pi.business_id, p.supplier_state) then pi.tax_amount else 0 end,
      cgst_amount = case when public.gst_is_inter_state(pi.business_id, p.supplier_state) then 0 else round(pi.tax_amount / 2, 2) end,
      sgst_amount = case when public.gst_is_inter_state(pi.business_id, p.supplier_state) then 0 else pi.tax_amount - round(pi.tax_amount / 2, 2) end
  from public.purchases p
  where p.id = pi.purchase_id
    and pi.cgst_amount = 0 and pi.sgst_amount = 0 and pi.igst_amount = 0 and pi.tax_amount <> 0;

-- ---------- GST report with the split ----------
create or replace function public.get_gst_report(p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
begin
  return jsonb_build_object(
    'output_tax', coalesce((select jsonb_agg(row_to_json(t)) from (
      select ii.gst_rate,
             sum(ii.quantity * ii.unit_price - ii.discount_amount) as taxable_value,
             sum(ii.tax_amount)  as tax_amount,
             sum(ii.cgst_amount) as cgst_amount,
             sum(ii.sgst_amount) as sgst_amount,
             sum(ii.igst_amount) as igst_amount
      from public.invoice_items ii join public.invoices i on i.id = ii.invoice_id
      where i.business_id = v_business and not i.is_cancelled and i.invoice_type = 'gst'
        and i.invoice_date::date between p_from and p_to
      group by ii.gst_rate order by ii.gst_rate) t), '[]'::jsonb),
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
      group by pi.gst_rate order by pi.gst_rate) t), '[]'::jsonb)
  );
end $$;

-- ============================================================
-- Part 2: explicit unlimited credit (PD17 / PD18)
-- ============================================================
alter table public.businesses add column if not exists default_credit_limit numeric(12,2) not null default 0
  check (default_credit_limit >= 0);
alter table public.customers add column if not exists credit_unlimited boolean not null default false;

-- PD18: existing customers with no limit keep "no limit", now stated explicitly.
update public.customers set credit_unlimited = true where credit_limit is null;

-- Unlimited ⇒ no numeric limit; otherwise an unset limit takes the store default.
create or replace function public.normalize_customer_credit()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.credit_unlimited then
    new.credit_limit := null;
  elsif new.credit_limit is null then
    select default_credit_limit into new.credit_limit
      from public.businesses where id = new.business_id;
    new.credit_limit := coalesce(new.credit_limit, 0);
  end if;
  return new;
end $$;

drop trigger if exists trg_customers_credit on public.customers;
create trigger trg_customers_credit before insert or update of credit_limit, credit_unlimited on public.customers
  for each row execute function public.normalize_customer_credit();
