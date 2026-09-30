-- ============================================================
-- Admin Settings: checked, logged saves; the support number reaches the
-- app; shops never see the settings themselves (migration 0056).
--
-- HOW TO RUN — on a STAGING copy, after 0056:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; your real settings are untouched.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('e6e6e6e6-0000-0000-0000-0000000000ad', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'set-admin@test.invalid'),
  ('e6e6e6e6-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'set-owner@test.invalid');

insert into public.businesses (id, name, state_code, phone) values
  ('e6e6e6e6-1111-0000-0000-00000000000a', 'SET Shop', '27', '9000055555');
update public.profiles set role = 'admin' where id = 'e6e6e6e6-0000-0000-0000-0000000000ad';
update public.profiles set business_id = 'e6e6e6e6-1111-0000-0000-00000000000a', role = 'owner'
  where id = 'e6e6e6e6-0000-0000-0000-00000000000a';
insert into public.subscriptions (business_id, status, expiry_date) values
  ('e6e6e6e6-1111-0000-0000-00000000000a', 'active', current_date + 30);

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

do $$
declare
  admin constant uuid := 'e6e6e6e6-0000-0000-0000-0000000000ad';
  owner constant uuid := 'e6e6e6e6-0000-0000-0000-00000000000a';
  good  constant jsonb := jsonb_build_object(
    'payment_upi_id', 'settest@okaxis', 'payment_payee_name', 'Set Test',
    'support_whatsapp', '98765 43210', 'business_name', 'SOFTRAXA Test',
    'business_address', 'Pune', 'business_phone', '9876543210',
    'business_email', 'Help@Example.com', 'business_gstin', '27abcde1234f1z5',
    'receipt_footer', 'Thank you');
  v jsonb; s public.platform_settings;
begin
  -- 1. A shop can't read or change the settings.
  perform pg_temp.act(owner);
  if exists (select 1 from public.platform_settings) then
    raise exception 'FAIL 1a: a shop can read the settings';
  end if;
  begin
    perform public.admin_save_settings(good);
    raise exception 'FAIL 1b: a shop changed the settings';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 1 (settings are SOFTRAXA''s only)';

  -- 2. Wrong values are refused.
  perform pg_temp.act(admin);
  begin
    perform public.admin_save_settings(good || '{"payment_upi_id": "not a upi id"}');
    raise exception 'FAIL 2a: bad UPI ID accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    perform public.admin_save_settings(good || '{"support_whatsapp": "12345"}');
    raise exception 'FAIL 2b: short WhatsApp number accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    perform public.admin_save_settings(good || '{"business_gstin": "27ABC"}');
    raise exception 'FAIL 2c: bad GSTIN accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    perform public.admin_save_settings(good || '{"business_email": "nobody"}');
    raise exception 'FAIL 2d: bad email accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 2 (UPI ID, WhatsApp number, GSTIN and email are checked)';

  -- 3. A good save is tidied, stamped and logged.
  perform public.admin_save_settings(good);
  select * into s from public.platform_settings where id = 1;
  if s.payment_upi_id <> 'settest@okaxis' or s.support_whatsapp <> '919876543210'
     or s.business_gstin <> '27ABCDE1234F1Z5' or s.business_email <> 'help@example.com'
     or s.business_name <> 'SOFTRAXA Test' or s.updated_by is distinct from admin then
    raise exception 'FAIL 3a: saved %', to_jsonb(s) - 'confirmed_checks';
  end if;
  if not exists (select 1 from public.audit_logs
                 where action = 'settings.updated' and user_id = admin
                   and details -> 'after' ->> 'payment_upi_id' = 'settest@okaxis') then
    raise exception 'FAIL 3b: the change was not logged';
  end if;
  raise notice 'PASS 3 (saved, 10-digit number gets 91, logged with before and after)';

  -- 4. The app gets the support number everywhere, and the payment
  --    details on the renewal screen — but not SOFTRAXA's other details.
  perform pg_temp.act(owner);
  v := public.get_my_context();
  if v -> 'support' ->> 'whatsapp' is distinct from '919876543210'
     or v::text like '%settest@okaxis%' or v::text like '%27ABCDE1234F1Z5%' then
    raise exception 'FAIL 4a: context %', v -> 'support';
  end if;
  v := public.get_payment_info();
  if v ->> 'upi_id' <> 'settest@okaxis' or v ->> 'payee_name' <> 'Set Test'
     or v ->> 'support_whatsapp' <> '919876543210' then
    raise exception 'FAIL 4b: payment info %', v;
  end if;
  raise notice 'PASS 4 (app has the support number and the UPI details)';

  -- 5. System health knows 0056.
  perform pg_temp.act(admin);
  v := public.get_system_health();
  if not (v -> 'migrations' ->> '0056')::boolean or not (v ->> 'support_whatsapp_set')::boolean then
    raise exception 'FAIL 5: %', v;
  end if;
  raise notice 'PASS 5 (health: 0056 applied)';
end $$;

reset role;
do $$ begin raise notice 'ALL SETTINGS CHECKS PASSED — rolling back test data'; end $$;
rollback;
