-- ============================================================
-- R1 shop categories and setup wizard (migration 0047).
--
-- HOW TO RUN — on a STAGING copy, AFTER 0047 has been run (the new
-- categories only exist once that migration is committed):
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('abababab-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'r1-setup-repair@test.invalid'),
  ('abababab-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'r1-setup-garment@test.invalid'),
  ('abababab-0000-0000-0000-00000000000c', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'r1-setup-electric@test.invalid'),
  ('abababab-0000-0000-0000-00000000000d', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'r1-setup-staff@test.invalid');

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

do $$
declare
  repair   constant uuid := 'abababab-0000-0000-0000-00000000000a';
  garment  constant uuid := 'abababab-0000-0000-0000-00000000000b';
  electric constant uuid := 'abababab-0000-0000-0000-00000000000c';
  staff    constant uuid := 'abababab-0000-0000-0000-00000000000d';
  gstin    constant text := '27AAPFU0939F1ZV';
  b uuid; v jsonb; n integer;
begin
  -- 1. A new shop starts in the setup wizard.
  perform pg_temp.act(repair);
  b := public.create_business(jsonb_build_object('name', 'R1 Fix It', 'business_type', 'other'));
  if (select onboarding_done from public.businesses where id = b) then
    raise exception 'FAIL 1: new shop marked as set up';
  end if;
  raise notice 'PASS 1 (new shop goes to the setup wizard)';

  -- 2. GST checks: valid GSTIN, turnover band, no e-invoicing businesses.
  begin
    perform public.complete_onboarding(jsonb_build_object('business_type', 'mobile_repair',
      'tax_preference', 'gst', 'gst_number', '27AAPFU0939F1ZX', 'turnover_band', 'up_to_5cr'));
    raise exception 'FAIL 2a: invalid GSTIN accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    perform public.complete_onboarding(jsonb_build_object('business_type', 'mobile_repair',
      'tax_preference', 'gst', 'gst_number', gstin));
    raise exception 'FAIL 2b: GST shop without a turnover band';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    perform public.complete_onboarding(jsonb_build_object('business_type', 'mobile_repair',
      'tax_preference', 'gst', 'gst_number', gstin, 'turnover_band', 'above_5cr'));
    raise exception 'FAIL 2c: onboarded a business that needs e-invoicing';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 2 (GSTIN, turnover band; above ₹5 crore refused): %', sqlerrm;
  end;

  -- 3. UPI ID and invoice prefix are checked.
  begin
    perform public.complete_onboarding(jsonb_build_object('business_type', 'mobile_repair',
      'tax_preference', 'non_gst', 'upi_id', 'not a upi'));
    raise exception 'FAIL 3a: bad UPI ID accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    perform public.complete_onboarding(jsonb_build_object('business_type', 'mobile_repair',
      'tax_preference', 'non_gst', 'invoice_prefix', 'TOO-LONG-PREFIX'));
    raise exception 'FAIL 3b: invoice prefix too long';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 3 (UPI ID and invoice prefix checked)';
end $$;

-- A staff member joins the repair shop.
reset role;
select set_config('request.jwt.claims', '', true);
update public.profiles set role = 'staff',
  business_id = (select id from public.businesses where name = 'R1 Fix It')
  where id = 'abababab-0000-0000-0000-00000000000d';
set local role authenticated;

do $$
declare
  repair   constant uuid := 'abababab-0000-0000-0000-00000000000a';
  garment  constant uuid := 'abababab-0000-0000-0000-00000000000b';
  electric constant uuid := 'abababab-0000-0000-0000-00000000000c';
  staff    constant uuid := 'abababab-0000-0000-0000-00000000000d';
  gstin    constant text := '27AAPFU0939F1ZV';
  b uuid; v jsonb; n integer;
begin
  perform pg_temp.act(repair);
  b := public.current_business_id();

  -- 4. Staff can't run the owner's setup.
  perform pg_temp.act(staff);
  begin
    perform public.complete_onboarding(jsonb_build_object('business_type', 'mobile_repair',
      'tax_preference', 'non_gst'));
    raise exception 'FAIL 4: staff completed the owner''s setup';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 4 (owner only): %', sqlerrm;
  end;

  -- 5. Mobile repair shop: state from GSTIN, estimates on, starter services.
  perform pg_temp.act(repair);
  v := public.complete_onboarding(jsonb_build_object('business_type', 'mobile_repair',
    'tax_preference', 'gst', 'gst_number', lower(gstin), 'turnover_band', 'up_to_5cr',
    'upi_id', 'fixit@okaxis', 'invoice_prefix', 'fx'));
  if not (v ->> 'onboarding_done')::boolean or v ->> 'state_code' <> '27'
     or v ->> 'gst_number' <> gstin or v ->> 'invoice_prefix' <> 'FX'
     or v ->> 'upi_id' <> 'fixit@okaxis' or not (v ->> 'require_repair_estimate')::boolean then
    raise exception 'FAIL 5a: %', v;
  end if;
  select count(*) into n from public.services where business_id = b;
  if n <> 6 then raise exception 'FAIL 5b: % starter services', n; end if;
  raise notice 'PASS 5 (repair shop: state 27 from GSTIN, estimates on, 6 starter services)';

  -- 6. Running setup again doesn't duplicate anything.
  perform public.complete_onboarding(jsonb_build_object('business_type', 'mobile_repair'));
  select count(*) into n from public.services where business_id = b;
  if n <> 6 then raise exception 'FAIL 6: % services after a second run', n; end if;
  raise notice 'PASS 6 (setup can be re-run safely)';

  -- 7. Garment shop (non-GST): estimates off, no services, no GSTIN kept.
  perform pg_temp.act(garment);
  b := public.create_business(jsonb_build_object('name', 'R1 Threads'));
  v := public.complete_onboarding(jsonb_build_object('business_type', 'garment',
    'tax_preference', 'non_gst', 'gst_number', gstin));
  if (v ->> 'require_repair_estimate')::boolean or v ->> 'gst_number' <> ''
     or (select count(*) from public.services where business_id = b) <> 0 then
    raise exception 'FAIL 7: %', v;
  end if;
  raise notice 'PASS 7 (garment shop: estimates off, no services)';

  -- 8. Electrical shop: coil and feet units, installation services.
  perform pg_temp.act(electric);
  b := public.create_business(jsonb_build_object('name', 'R1 Sparks'));
  perform public.complete_onboarding(jsonb_build_object('business_type', 'electrical',
    'tax_preference', 'non_gst'));
  if (select count(*) from public.units where business_id = b and name in ('Coil', 'Feet')) <> 2
     or not exists (select 1 from public.services where business_id = b and name = 'Installation charge') then
    raise exception 'FAIL 8: electrical defaults missing';
  end if;
  raise notice 'PASS 8 (electrical: coil and feet units, installation services)';
end $$;

reset role;
do $$ begin raise notice 'ALL R1 SETUP CHECKS PASSED — rolling back test data'; end $$;
rollback;
