-- ============================================================
-- 0047_categories_and_setup.sql — release R1, batch 8
-- (LAUNCH_SPECIFICATION.md D01, D03, D06, D40; onboarding "Setup wizard")
--
-- R1 shop categories: mobile, mobile repair, garment, hardware,
-- electrical, car workshop, bike garage (plus "other").
--
-- First-time setup: a new shop (self-signup or created by SOFTRAXA)
-- starts with onboarding_done = false and the owner goes through the
-- setup wizard. complete_onboarding() checks and saves:
--   * category — which also sets category defaults (below);
--   * GST registration: a valid GSTIN (its first two digits set the
--     state) and the annual turnover band. Businesses above the ₹5 crore
--     e-invoicing threshold can't be onboarded until R3 (D40);
--   * UPI ID (printed on bills as a "scan to pay" code) and invoice prefix.
--
-- Category defaults (applied on first setup or when the category
-- changes; nothing already set up is removed):
--   * repair shops and garages: estimates required before repair work
--     (D37) and a few starter services at price 0 for the owner to price;
--   * electrical: starter installation/repair services; coil and feet units;
--   * hardware: feet and bag units;
--   * others: estimates off.
--
-- Shops that existed before this migration are marked as set up.
--
-- Run AFTER 0046. The new category values can only be used after this
-- migration is committed, so run its test as a separate step.
-- ============================================================

-- ============================================================
-- A. Categories and setup fields
-- ============================================================
alter type public.business_type add value if not exists 'mobile_repair';
alter type public.business_type add value if not exists 'electrical';
alter type public.business_type add value if not exists 'car_workshop';
alter type public.business_type add value if not exists 'bike_garage';

-- Existing shops: already set up (true). New shops: wizard first.
alter table public.businesses add column if not exists onboarding_done boolean not null default true;
alter table public.businesses alter column onboarding_done set default false;

alter table public.businesses add column if not exists turnover_band text;
alter table public.businesses add column if not exists upi_id text not null default '';

alter table public.businesses drop constraint if exists businesses_turnover_band_check;
alter table public.businesses add constraint businesses_turnover_band_check
  check (turnover_band is null or turnover_band in ('up_to_5cr', 'above_5cr'));
alter table public.businesses drop constraint if exists businesses_upi_id_check;
alter table public.businesses add constraint businesses_upi_id_check
  check (upi_id = '' or upi_id ~ '^[A-Za-z0-9._-]{2,255}@[A-Za-z][A-Za-z0-9]{1,63}$');

-- ============================================================
-- B. Category defaults
-- ============================================================
create or replace function public.apply_category_defaults(p_business uuid, p_category text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_services text[];
  v_units    text[][];
  v_i        integer;
begin
  update public.businesses
     set require_repair_estimate = p_category in ('mobile_repair', 'car_workshop', 'bike_garage')
   where id = p_business;

  v_services := case p_category
    when 'mobile_repair' then array['Diagnosis', 'Screen replacement (labour)',
      'Battery replacement (labour)', 'Charging port repair', 'Software update / flashing',
      'Water damage cleaning']
    when 'bike_garage' then array['Diagnosis', 'General service', 'Oil change (labour)',
      'Brake adjustment', 'Chain cleaning and lubrication', 'Puncture repair']
    when 'car_workshop' then array['Diagnosis', 'General service', 'Oil change (labour)',
      'Wheel alignment', 'Wheel balancing', 'AC service']
    when 'electrical' then array['Visit charge', 'Installation charge', 'Wiring (labour)',
      'Fan / appliance repair']
    else array[]::text[]
  end;
  -- Price 0: the owner sets real prices in the service catalog.
  insert into public.services (business_id, name, category, price, gst_rate)
  select p_business, s, 'Starter', 0, 18
  from unnest(v_services) s
  where not exists (select 1 from public.services x
                    where x.business_id = p_business and lower(x.name) = lower(s));

  v_units := case p_category
    when 'electrical' then array[['Coil', 'coil', 'false'], ['Feet', 'ft', 'true']]
    when 'hardware' then array[['Feet', 'ft', 'true'], ['Bag', 'bag', 'false']]
    else null
  end;
  if v_units is not null then
    for v_i in 1 .. array_length(v_units, 1) loop
      insert into public.units (business_id, name, short_name, allow_decimal)
      select p_business, v_units[v_i][1], v_units[v_i][2], v_units[v_i][3]::boolean
      where not exists (select 1 from public.units u
                        where u.business_id = p_business and lower(u.name) = lower(v_units[v_i][1]));
    end loop;
  end if;
end $$;

-- ============================================================
-- C. Finish the setup wizard (owner only)
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
  if v_tax not in ('gst', 'non_gst') then raise exception 'Choose GST or non-GST billing'; end if;
  v_gstin := upper(btrim(coalesce(payload ->> 'gst_number', v_old.gst_number, '')));
  v_state := coalesce(nullif(payload ->> 'state_code', ''), v_old.state_code);
  v_band := coalesce(nullif(payload ->> 'turnover_band', ''), v_old.turnover_band);

  if v_tax = 'gst' then
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

  -- Invoice numbers must stay within 16 characters (GST rules).
  v_prefix := upper(btrim(coalesce(nullif(payload ->> 'invoice_prefix', ''), v_old.invoice_prefix, 'INV')));
  if v_prefix !~ '^[A-Z0-9]{1,6}$' then
    raise exception 'Invoice prefix: 1–6 letters or digits, for example INV';
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
revoke execute on function public.apply_category_defaults(uuid, text) from public, anon, authenticated;
revoke execute on function public.complete_onboarding(jsonb) from public, anon;
grant execute on function public.complete_onboarding(jsonb) to authenticated;
