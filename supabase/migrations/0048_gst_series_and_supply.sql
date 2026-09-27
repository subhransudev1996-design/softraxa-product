-- ============================================================
-- 0048_gst_series_and_supply.sql — release R1, batch 9
-- (LAUNCH_SPECIFICATION.md D40, "GST and tax": numbering, bill of
-- supply, HSN/SAC)
--
-- 1. Invoice numbers restart every financial year (April–March):
--    'INV/26-27/0001'. At most 16 characters (GST rule): the prefix is
--    cut to its first 4 characters in the number, and the running number
--    has 4 digits (5 from the 10,000th bill). A bill's year comes from its
--    own date, so an offline bill made on 31 March and synced on 1 April
--    still gets the old year's number. Cash memos get their own yearly
--    series ('CM/26-27/0001'). Earlier bills keep their numbers.
-- 2. Composition shops (tax_preference 'composition') can't collect GST:
--    they issue bills of supply (non-GST bills with the composition
--    declaration, printed by the app); a GST tax invoice is refused.
-- 3. HSN (goods) / SAC (services): format checked when entered (HSN 4, 6
--    or 8 digits; SAC 6 digits starting 99). Every line of a tax invoice
--    to a GST-registered customer (B2B) must carry an HSN/SAC of at least
--    4 digits — the rule for turnover up to ₹5 crore (larger businesses
--    aren't onboarded until R3). Bills to consumers (B2C) don't need it.
--
-- Run AFTER 0047, on its own ('composition' is a new enum value), then
-- run supabase/tests/r1_gst_series.sql.
-- ============================================================

alter type public.tax_preference add value if not exists 'composition';

-- ============================================================
-- A. Yearly invoice numbers
-- ============================================================

-- The date whose financial year a new document number belongs to.
-- create_invoice sets it from the bill's date for the rest of the
-- transaction; everything else uses today (Indian time).
create or replace function public.doc_number_date()
returns date language sql stable as $$
  select coalesce(nullif(current_setting('app.doc_date', true), '')::date,
                  public.ist_date(now()));
$$;

-- Replaces 0008's version. Invoices and cash memos: a yearly series.
-- Other documents (purchases, returns, job cards, estimates) unchanged.
create or replace function public.next_doc_no(p_business uuid, p_doc_type text, p_prefix text)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_counter bigint;
  v_fy      text;
begin
  if p_doc_type in ('invoice', 'cash_memo') then
    v_fy := public.fy_label(public.doc_number_date());
    insert into public.doc_counters (business_id, doc_type, counter)
    values (p_business, p_doc_type || ':' || v_fy, 1)
    on conflict (business_id, doc_type)
    do update set counter = public.doc_counters.counter + 1
    returning counter into v_counter;
    return left(upper(coalesce(nullif(btrim(p_prefix), ''), 'INV')), 4)
      || '/' || v_fy || '/' || lpad(v_counter::text, 4, '0');
  end if;

  insert into public.doc_counters (business_id, doc_type, counter)
  values (p_business, p_doc_type, 1)
  on conflict (business_id, doc_type)
  do update set counter = public.doc_counters.counter + 1
  returning counter into v_counter;
  return p_prefix || '-' || lpad(v_counter::text, 5, '0');
end $$;

-- 0044's wrapper, plus: number the bill in the financial year of its
-- own date (offline bills carry the date they were made).
create or replace function public.create_invoice(payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v         jsonb;
  v_id      uuid;
  v_pricing jsonb;
  v_ex      jsonb;
begin
  perform set_config('app.doc_date',
    public.ist_date(coalesce(nullif(payload ->> 'invoice_date', '')::timestamptz, now()))::text,
    true);
  v := public.create_invoice_impl(payload);
  perform set_config('app.doc_date', '', true);
  if coalesce((v ->> 'already_synced')::boolean, false) then return v; end if;
  v_id := (v ->> 'id')::uuid;
  v_pricing := public.check_invoice_pricing(v_id);
  v_ex := public.sale_exceptions(v_id, v_pricing);
  perform public.settle_sale_exceptions(v_id, payload, v_ex);
  return v;
end $$;

-- ============================================================
-- B. Composition shops: bills of supply only
-- ============================================================
create or replace function public.guard_composition_invoice()
returns trigger language plpgsql as $$
begin
  if new.invoice_type = 'gst'
     and (select tax_preference::text from public.businesses where id = new.business_id) = 'composition' then
    raise exception 'A composition shop can''t charge GST — issue a bill of supply (non-GST bill) instead';
  end if;
  return new;
end $$;

drop trigger if exists trg_invoices_composition on public.invoices;
create trigger trg_invoices_composition before insert or update of invoice_type on public.invoices
  for each row execute function public.guard_composition_invoice();

-- ============================================================
-- C. HSN / SAC
-- ============================================================
create or replace function public.is_valid_hsn(p text)
returns boolean language sql immutable as $$
  select coalesce(p, '') ~ '^[0-9]{4}([0-9]{2}){0,2}$';
$$;

create or replace function public.is_valid_sac(p text)
returns boolean language sql immutable as $$
  select coalesce(p, '') ~ '^99[0-9]{4}$';
$$;

-- Format only when a code is entered or changed; codes typed before this
-- migration are left alone until edited.
create or replace function public.guard_product_hsn()
returns trigger language plpgsql as $$
begin
  new.hsn_code := btrim(coalesce(new.hsn_code, ''));
  if new.hsn_code <> '' and not public.is_valid_hsn(new.hsn_code)
     and (tg_op = 'INSERT' or new.hsn_code is distinct from old.hsn_code) then
    raise exception 'HSN code of %: 4, 6 or 8 digits', new.name;
  end if;
  return new;
end $$;

drop trigger if exists trg_products_hsn on public.products;
create trigger trg_products_hsn before insert or update of hsn_code on public.products
  for each row execute function public.guard_product_hsn();

create or replace function public.guard_service_sac()
returns trigger language plpgsql as $$
begin
  new.sac_code := btrim(coalesce(new.sac_code, ''));
  if new.sac_code <> '' and not public.is_valid_sac(new.sac_code)
     and (tg_op = 'INSERT' or new.sac_code is distinct from old.sac_code) then
    raise exception 'SAC code of %: 6 digits starting with 99', new.name;
  end if;
  return new;
end $$;

drop trigger if exists trg_services_sac on public.services;
create trigger trg_services_sac before insert or update of sac_code on public.services
  for each row execute function public.guard_service_sac();

-- Tax invoice to a GST-registered customer: every line needs its HSN/SAC.
-- A blank line code is filled from the product.
create or replace function public.guard_invoice_item_hsn()
returns trigger language plpgsql as $$
declare
  v_inv record;
begin
  if coalesce(new.hsn_code, '') = '' and new.product_id is not null then
    new.hsn_code := coalesce((select p.hsn_code from public.products p where p.id = new.product_id), '');
  end if;
  select invoice_type, customer_gstin into v_inv from public.invoices where id = new.invoice_id;
  if v_inv.invoice_type = 'gst' and coalesce(v_inv.customer_gstin, '') <> ''
     and not public.is_valid_hsn(new.hsn_code) and not public.is_valid_sac(new.hsn_code) then
    raise exception 'Add the HSN/SAC code of "%" (at least 4 digits) — it is required on bills to GST-registered customers',
      new.product_name;
  end if;
  return new;
end $$;

drop trigger if exists trg_invoice_items_hsn on public.invoice_items;
create trigger trg_invoice_items_hsn before insert or update of hsn_code, product_id on public.invoice_items
  for each row execute function public.guard_invoice_item_hsn();

-- ============================================================
-- D. Setup wizard: composition, 4-character invoice prefix
--    (replaces 0047's complete_onboarding)
-- ============================================================
create or replace function public.complete_onboarding(payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_old      record;
  v_category text;
  v_tax      text;
  v_gstin    text;
  v_state    text;
  v_band     text;
  v_upi      text;
  v_prefix   text;
begin
  if v_business is null then raise exception 'Create your shop first'; end if;
  perform public.assert_can('owner');
  select * into v_old from public.businesses where id = v_business for update;

  v_category := coalesce(nullif(payload ->> 'business_type', ''), v_old.business_type::text);
  if v_category not in (select unnest(enum_range(null::public.business_type))::text) then
    raise exception 'Choose your type of shop';
  end if;

  v_tax := coalesce(nullif(payload ->> 'tax_preference', ''), v_old.tax_preference::text);
  if v_tax not in ('gst', 'composition', 'non_gst') then
    raise exception 'Choose regular GST, composition or not registered';
  end if;
  v_gstin := upper(btrim(coalesce(payload ->> 'gst_number', v_old.gst_number, '')));
  v_state := coalesce(nullif(payload ->> 'state_code', ''), v_old.state_code);
  v_band := coalesce(nullif(payload ->> 'turnover_band', ''), v_old.turnover_band);

  if v_tax in ('gst', 'composition') then
    if not public.is_valid_gstin(v_gstin) then
      raise exception 'Enter a valid 15-character GSTIN';
    end if;
    v_state := left(v_gstin, 2);
    if v_band is null then
      raise exception 'Choose your annual turnover';
    end if;
    if v_band = 'above_5cr' then
      raise exception 'Businesses with turnover above ₹5 crore need e-invoicing, which Dukania doesn''t support yet. Please contact SOFTRAXA support.';
    end if;
  else
    v_gstin := '';
  end if;

  v_upi := btrim(coalesce(payload ->> 'upi_id', v_old.upi_id, ''));
  if v_upi <> '' and v_upi !~ '^[A-Za-z0-9._-]{2,255}@[A-Za-z][A-Za-z0-9]{1,63}$' then
    raise exception 'Enter a valid UPI ID, for example shopname@okaxis';
  end if;

  -- 'INV/26-27/0001' must fit in 16 characters.
  v_prefix := upper(btrim(coalesce(nullif(payload ->> 'invoice_prefix', ''), v_old.invoice_prefix, 'INV')));
  if v_prefix !~ '^[A-Z0-9]{1,4}$' then
    raise exception 'Invoice prefix: 1–4 letters or digits, for example INV';
  end if;

  update public.businesses set
    business_type  = v_category::public.business_type,
    tax_preference = v_tax::public.tax_preference,
    gst_number     = v_gstin,
    state_code     = v_state,
    turnover_band  = v_band,
    upi_id         = v_upi,
    invoice_prefix = v_prefix,
    name           = coalesce(nullif(btrim(payload ->> 'name'), ''), name),
    owner_name     = coalesce(payload ->> 'owner_name', owner_name),
    phone          = coalesce(payload ->> 'phone', phone),
    address        = coalesce(payload ->> 'address', address),
    onboarding_done = true
  where id = v_business;

  if not v_old.onboarding_done or v_category <> v_old.business_type::text then
    perform public.apply_category_defaults(v_business, v_category);
  end if;

  perform public.log_audit('business.onboarded', 'business', v_business::text,
    jsonb_build_object('category', v_category, 'tax', v_tax, 'turnover_band', v_band));
  return (select to_jsonb(b) from public.businesses b where b.id = v_business);
end $$;

-- ============================================================
-- Grants
-- ============================================================
revoke execute on function public.doc_number_date() from public, anon, authenticated;
grant execute on function public.is_valid_hsn(text) to authenticated;
grant execute on function public.is_valid_sac(text) to authenticated;
