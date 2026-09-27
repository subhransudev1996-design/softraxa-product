-- ============================================================
-- 0051_opening_balances_and_imports.sql — release R1, batch 12
-- (LAUNCH_SPECIFICATION.md onboarding "Migration from paper or other
-- software"; PD20, PD21)
--
-- 1. Opening balances — what a customer owed (or had paid in advance),
--    or what the shop owed a supplier, before the shop started on
--    Dukania.
--      * Customer due: an 'opening' bill (OB-00001) with no items, dated
--        on the opening date. It is a real receivable: receipts settle it
--        first (it is the oldest bill, PD21), its due date is the opening
--        date plus the shop's payment terms (PD20), and overdue and
--        credit-limit checks count it. It is not a sale: sales reports
--        and GST returns leave it out. Correct a wrong one by cancelling
--        it (owner) and entering it again; it can't be edited.
--      * Customer advance (negative opening): the advance ledger's
--        'opening' entry.
--      * Supplier due: an opening purchase (is_opening) with no items;
--        supplier payments settle it first; the GST purchase register
--        (which reads purchase items) never includes it.
--    The opening date must be before today, so today's figures are
--    never affected. Owner only.
-- 2. Imports from Excel (the app reads the sheet): import_customers()
--    and import_suppliers() create the parties with their opening
--    balances. Rows matching an existing party (same phone, or same name
--    when there is no phone) are skipped; a bad row is reported and the
--    others still import.
--
-- Run AFTER 0050, on its own ('opening' is a new bill type), then run
-- supabase/tests/r1_opening_imports.sql.
-- ============================================================

alter type public.invoice_type add value if not exists 'opening';

alter table public.purchases add column if not exists is_opening boolean not null default false;

-- ============================================================
-- A. Opening balances
-- ============================================================
-- p_party: 'customer' or 'supplier'. p_amount > 0: they owe us (customer)
-- or we owe them (supplier); < 0 (customers only): their advance.
create or replace function public.set_opening_balance(
  p_party text, p_party_id uuid, p_amount numeric, p_as_of date default null,
  p_note text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_as_of    date := coalesce(p_as_of, public.ist_date(now()) - 1);
  v_party    record;
  v_id       uuid;
  v_no       text;
  v_note     text := coalesce(nullif(btrim(p_note), ''), 'Opening balance');
begin
  perform public.assert_can('owner');
  if coalesce(p_amount, 0) = 0 then return null; end if;
  if v_as_of >= public.ist_date(now()) then
    raise exception 'The opening date must be before today';
  end if;

  if p_party = 'customer' then
    select * into v_party from public.customers
      where id = p_party_id and business_id = v_business for update;
    if v_party.id is null then raise exception 'Customer not found'; end if;

    if p_amount < 0 then
      insert into public.customer_advance_entries (business_id, customer_id, amount, kind, note, created_by)
        values (v_business, v_party.id, -p_amount, 'opening', v_note, auth.uid());
      update public.customers set advance_amount = advance_amount - p_amount where id = v_party.id;
      perform public.log_audit('customer.opening_advance', 'customer', v_party.id::text,
        jsonb_build_object('amount', -p_amount));
      return jsonb_build_object('advance', -p_amount);
    end if;

    if exists (select 1 from public.invoices where customer_id = v_party.id
               and invoice_type = 'opening' and not is_cancelled) then
      raise exception '% already has an opening balance — cancel it first to change it', v_party.name;
    end if;
    v_no := public.next_doc_no(v_business, 'opening', 'OB');
    insert into public.invoices
      (business_id, invoice_no, invoice_type, invoice_date, customer_id, customer_name,
       customer_phone, subtotal, discount_amount, tax_amount, round_off, total, paid_amount,
       payment_status, payment_mode, notes, created_by)
    values
      (v_business, v_no, 'opening', (v_as_of::timestamp + time '12:00') at time zone 'Asia/Kolkata',
       v_party.id, v_party.name, v_party.phone, p_amount, 0, 0, 0, p_amount, 0,
       'unpaid', 'credit', v_note, auth.uid())
    returning id into v_id;
    update public.customers set due_amount = due_amount + p_amount where id = v_party.id;
    perform public.log_audit('customer.opening_due', 'invoice', v_id::text,
      jsonb_build_object('customer_id', v_party.id, 'amount', p_amount, 'as_of', v_as_of));
    return jsonb_build_object('invoice_id', v_id, 'invoice_no', v_no);

  elsif p_party = 'supplier' then
    if p_amount < 0 then
      raise exception 'A supplier''s opening balance is what you owe them (more than 0)';
    end if;
    select * into v_party from public.suppliers
      where id = p_party_id and business_id = v_business for update;
    if v_party.id is null then raise exception 'Supplier not found'; end if;
    if exists (select 1 from public.purchases where supplier_id = v_party.id and is_opening) then
      raise exception '% already has an opening balance', v_party.name;
    end if;
    v_no := public.next_doc_no(v_business, 'opening_purchase', 'OB');
    insert into public.purchases
      (business_id, purchase_no, supplier_id, supplier_name, purchase_date, subtotal, total,
       paid_amount, payment_status, payment_mode, notes, is_opening, created_by)
    values
      (v_business, v_no, v_party.id, v_party.name, v_as_of, p_amount, p_amount, 0,
       'unpaid', 'credit', v_note, true, auth.uid())
    returning id into v_id;
    update public.suppliers set due_amount = due_amount + p_amount where id = v_party.id;
    perform public.log_audit('supplier.opening_due', 'purchase', v_id::text,
      jsonb_build_object('supplier_id', v_party.id, 'amount', p_amount, 'as_of', v_as_of));
    return jsonb_build_object('purchase_id', v_id, 'purchase_no', v_no);
  end if;

  raise exception 'Choose customer or supplier';
end $$;

-- Opening bills can't be edited (0044's wrapper, plus this check).
create or replace function public.update_invoice(p_invoice_id uuid, payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v         jsonb;
  v_pricing jsonb;
  v_ex      jsonb;
begin
  if (select invoice_type::text from public.invoices where id = p_invoice_id) = 'opening' then
    raise exception 'An opening balance can''t be edited — cancel it and enter it again';
  end if;
  v := public.update_invoice_impl(p_invoice_id, payload);
  v_pricing := public.check_invoice_pricing(p_invoice_id);
  v_ex := public.sale_exceptions(p_invoice_id, v_pricing);
  perform public.settle_sale_exceptions(p_invoice_id, payload - 'approval_id' - 'offline_created', v_ex);
  return v;
end $$;

-- Sales report without opening balances (0023's report; wrapped by
-- 0037's permission check as get_sales_report).
create or replace function public.get_sales_report_impl(p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
begin
  return jsonb_build_object(
    'total_sales', coalesce((select sum(total) from public.invoices
      where business_id = v_business and not is_cancelled and invoice_type not in ('estimate', 'opening')
        and invoice_date::date between p_from and p_to), 0),
    'invoice_count', coalesce((select count(*) from public.invoices
      where business_id = v_business and not is_cancelled and invoice_type not in ('estimate', 'opening')
        and invoice_date::date between p_from and p_to), 0),
    'total_paid', coalesce((select sum(paid_amount) from public.invoices
      where business_id = v_business and not is_cancelled and invoice_type not in ('estimate', 'opening')
        and invoice_date::date between p_from and p_to), 0),
    'total_due', coalesce((select sum(due_amount) from public.invoices
      where business_id = v_business and not is_cancelled and invoice_type not in ('estimate', 'opening')
        and invoice_date::date between p_from and p_to), 0),
    'total_tax', coalesce((select sum(tax_amount) from public.invoices
      where business_id = v_business and not is_cancelled and invoice_type not in ('estimate', 'opening')
        and invoice_date::date between p_from and p_to), 0),
    'by_day', coalesce((select jsonb_agg(row_to_json(d)) from (
      select invoice_date::date as day, sum(total) as sales, count(*) as invoices
      from public.invoices
      where business_id = v_business and not is_cancelled and invoice_type not in ('estimate', 'opening')
        and invoice_date::date between p_from and p_to
      group by 1 order by 1) d), '[]'::jsonb),
    'by_mode', coalesce((select jsonb_agg(row_to_json(m)) from (
      select ip.payment_mode,
             sum(ip.amount) as sales,
             count(distinct ip.invoice_id) as invoices
      from public.invoice_payments ip
      join public.invoices i on i.id = ip.invoice_id
      where i.business_id = v_business and not i.is_cancelled
        and i.invoice_type not in ('estimate', 'opening')
        and i.invoice_date::date between p_from and p_to
      group by 1 order by 2 desc) m), '[]'::jsonb)
  );
end $$;

-- ============================================================
-- B. Imports
-- ============================================================
-- Customers: [{name, phone, gst_number, address, state_code,
-- credit_limit, opening_balance}]. Returns {created, skipped, errors}.
create or replace function public.import_customers(p_rows jsonb, p_as_of date default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_row      jsonb;
  v_i        integer := 0;
  v_name     text;
  v_phone    text;
  v_gstin    text;
  v_id       uuid;
  v_created  integer := 0;
  v_skipped  jsonb := '[]';
  v_errors   jsonb := '[]';
  v_opening  numeric;
begin
  perform public.assert_can('owner');
  if jsonb_typeof(p_rows) is distinct from 'array' then raise exception 'Nothing to import'; end if;

  for v_row in select * from jsonb_array_elements(p_rows) loop
    v_i := v_i + 1;
    v_name := btrim(coalesce(v_row ->> 'name', ''));
    v_phone := regexp_replace(coalesce(v_row ->> 'phone', ''), '[^0-9+]', '', 'g');
    v_gstin := upper(btrim(coalesce(v_row ->> 'gst_number', '')));
    begin
      if v_name = '' then raise exception 'Name is missing'; end if;
      if v_gstin <> '' and not public.is_valid_gstin(v_gstin) then
        raise exception 'GSTIN % is not valid', v_gstin;
      end if;
      if exists (select 1 from public.customers c where c.business_id = v_business
                 and ((v_phone <> '' and c.phone = v_phone)
                      or (v_phone = '' and lower(c.name) = lower(v_name)))) then
        v_skipped := v_skipped || jsonb_build_object('row', v_i, 'name', v_name,
          'reason', 'already exists');
        continue;
      end if;
      v_opening := coalesce(nullif(v_row ->> 'opening_balance', '')::numeric, 0);
      insert into public.customers
        (business_id, name, phone, gst_number, address, state_code, credit_limit)
      values
        (v_business, v_name, v_phone, v_gstin, btrim(coalesce(v_row ->> 'address', '')),
         coalesce(nullif(left(v_gstin, 2), ''), btrim(coalesce(v_row ->> 'state_code', ''))),
         nullif(v_row ->> 'credit_limit', '')::numeric)
      returning id into v_id;
      perform public.set_opening_balance('customer', v_id, v_opening, p_as_of);
      v_created := v_created + 1;
    exception when others then
      v_errors := v_errors || jsonb_build_object('row', v_i, 'name', v_name, 'error', sqlerrm);
    end;
  end loop;

  perform public.log_audit('customer.imported', 'business', v_business::text,
    jsonb_build_object('created', v_created, 'errors', jsonb_array_length(v_errors)));
  return jsonb_build_object('created', v_created, 'skipped', v_skipped, 'errors', v_errors);
end $$;

-- Suppliers: [{name, phone, gst_number, address, state_code,
-- opening_balance}].
create or replace function public.import_suppliers(p_rows jsonb, p_as_of date default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_row      jsonb;
  v_i        integer := 0;
  v_name     text;
  v_phone    text;
  v_gstin    text;
  v_id       uuid;
  v_created  integer := 0;
  v_skipped  jsonb := '[]';
  v_errors   jsonb := '[]';
begin
  perform public.assert_can('owner');
  if jsonb_typeof(p_rows) is distinct from 'array' then raise exception 'Nothing to import'; end if;

  for v_row in select * from jsonb_array_elements(p_rows) loop
    v_i := v_i + 1;
    v_name := btrim(coalesce(v_row ->> 'name', ''));
    v_phone := regexp_replace(coalesce(v_row ->> 'phone', ''), '[^0-9+]', '', 'g');
    v_gstin := upper(btrim(coalesce(v_row ->> 'gst_number', '')));
    begin
      if v_name = '' then raise exception 'Name is missing'; end if;
      if v_gstin <> '' and not public.is_valid_gstin(v_gstin) then
        raise exception 'GSTIN % is not valid', v_gstin;
      end if;
      if exists (select 1 from public.suppliers s where s.business_id = v_business
                 and ((v_phone <> '' and s.phone = v_phone)
                      or (v_phone = '' and lower(s.name) = lower(v_name)))) then
        v_skipped := v_skipped || jsonb_build_object('row', v_i, 'name', v_name,
          'reason', 'already exists');
        continue;
      end if;
      insert into public.suppliers (business_id, name, phone, gst_number, address, state_code)
      values
        (v_business, v_name, v_phone, v_gstin, btrim(coalesce(v_row ->> 'address', '')),
         coalesce(nullif(left(v_gstin, 2), ''), btrim(coalesce(v_row ->> 'state_code', ''))))
      returning id into v_id;
      perform public.set_opening_balance('supplier', v_id,
        coalesce(nullif(v_row ->> 'opening_balance', '')::numeric, 0), p_as_of);
      v_created := v_created + 1;
    exception when others then
      v_errors := v_errors || jsonb_build_object('row', v_i, 'name', v_name, 'error', sqlerrm);
    end;
  end loop;

  perform public.log_audit('supplier.imported', 'business', v_business::text,
    jsonb_build_object('created', v_created, 'errors', jsonb_array_length(v_errors)));
  return jsonb_build_object('created', v_created, 'skipped', v_skipped, 'errors', v_errors);
end $$;

-- ============================================================
-- Grants
-- ============================================================
revoke execute on function public.set_opening_balance(text, uuid, numeric, date, text) from public, anon;
revoke execute on function public.import_customers(jsonb, date) from public, anon;
revoke execute on function public.import_suppliers(jsonb, date) from public, anon;
grant execute on function public.set_opening_balance(text, uuid, numeric, date, text) to authenticated;
grant execute on function public.import_customers(jsonb, date) to authenticated;
grant execute on function public.import_suppliers(jsonb, date) to authenticated;
