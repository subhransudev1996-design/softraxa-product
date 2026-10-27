-- ============================================================
-- A longer note at the bottom of the bill (migration 0093).
--
-- HOW TO RUN — on a STAGING copy, after 0093:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the last line shows "bill_note tests passed".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('93939393-0000-0000-0000-00000000000f', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'note-owner@test.invalid');
insert into public.businesses (id, name, state_code) values
  ('93939393-1111-0000-0000-00000000000f', 'Note Test Shop', '21');
update public.profiles set business_id = '93939393-1111-0000-0000-00000000000f', role = 'owner'
  where id = '93939393-0000-0000-0000-00000000000f';

select set_config('request.jwt.claims',
  json_build_object('sub', '93939393-0000-0000-0000-00000000000f', 'role', 'authenticated')::text, true);
set local role authenticated;

do $$
declare
  v_note text := '*BUSINESS HOURS - 9.00 AM TO 10.00 PM (NO LUNCH BREAK)*' || chr(10) ||
    'LAST TUESDAY CLOSED' || chr(10) ||
    'Books once sold can not be returned back, unless any defects (Govt. published books are not included.)' || chr(10) ||
    '(Return of defective books is subject to producing the sale invoice / estimate slip within 7 days from the date of purchase)' || chr(10) ||
    '(No cash will be refunded against return of books)' || chr(10) ||
    '*Exchange time: 12 noon to 4:00 p.m. only.*';
  v_saved text;
begin
  -- The owner saves a several-line note longer than the old 200 limit.
  update public.businesses set bill_footer = v_note where id = '93939393-1111-0000-0000-00000000000f';
  select bill_footer into v_saved from public.businesses where id = '93939393-1111-0000-0000-00000000000f';
  if v_saved is distinct from v_note then raise exception 'note not saved'; end if;

  -- Still capped, at 1000 characters.
  begin
    update public.businesses set bill_footer = repeat('x', 1001) where id = '93939393-1111-0000-0000-00000000000f';
    raise exception 'a 1001-character note was accepted';
  exception when check_violation then null;
  end;
end $$;

reset role;
select 'bill_note tests passed' as result;
rollback;
