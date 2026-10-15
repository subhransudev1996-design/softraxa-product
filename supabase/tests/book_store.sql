-- ============================================================
-- Book store shop category (migration 0081).
--
-- HOW TO RUN — on a STAGING copy, AFTER 0081 has been run (the new
-- category only exists once that migration is committed):
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('81818181-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'book-store@test.invalid');

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

do $$
declare
  owner constant uuid := '81818181-0000-0000-0000-00000000000a';
  b uuid;
begin
  -- 1. A shop can finish setup as a book store.
  perform pg_temp.act(owner);
  b := public.create_business(jsonb_build_object('name', 'Test Book House', 'business_type', 'other'));
  perform public.complete_onboarding(jsonb_build_object('business_type', 'book_store',
    'tax_preference', 'non_gst'));
  if (select business_type::text from public.businesses where id = b) <> 'book_store' then
    raise exception 'FAIL 1: category not saved as book_store';
  end if;
  if not (select onboarding_done from public.businesses where id = b) then
    raise exception 'FAIL 1b: setup not finished';
  end if;
  raise notice 'PASS 1 (book store saved, setup finished)';

  -- 2. No repair estimates, no starter services for a book store.
  if (select require_repair_estimate from public.businesses where id = b) then
    raise exception 'FAIL 2a: book store requires repair estimates';
  end if;
  if exists (select 1 from public.services where business_id = b) then
    raise exception 'FAIL 2b: book store got starter services';
  end if;
  raise notice 'PASS 2 (no repair defaults)';
end $$;

reset role;
do $$ begin raise notice 'ALL BOOK STORE CHECKS PASSED — rolling back test data'; end $$;
rollback;
