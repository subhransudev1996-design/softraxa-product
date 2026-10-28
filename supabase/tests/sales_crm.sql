-- ============================================================
-- Sales CRM (0100): stages and their log, app signups as leads,
-- won on payment, duplicates by phone, import.
--
-- HOW TO RUN — on a STAGING copy, after 0100:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the last line shows "sales_crm tests passed".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('10010010-0000-0000-0000-0000000000ad', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'crm-owner@test.invalid'),
  ('10010010-0000-0000-0000-00000000005c', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'crm-support@test.invalid'),
  ('10010010-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'crm-shop-a@test.invalid'),
  ('10010010-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'crm-shop-b@test.invalid');
update public.profiles set role = 'admin'
  where id in ('10010010-0000-0000-0000-0000000000ad', '10010010-0000-0000-0000-00000000005c');
insert into public.admin_team (user_id, team_role, areas) values
  ('10010010-0000-0000-0000-0000000000ad', 'owner', '{}'),
  ('10010010-0000-0000-0000-00000000005c', 'support', '{support}');

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

do $$
declare
  owner constant uuid := '10010010-0000-0000-0000-0000000000ad';
  support constant uuid := '10010010-0000-0000-0000-00000000005c';
  shop_a constant uuid := '10010010-0000-0000-0000-00000000000a';
  shop_b constant uuid := '10010010-0000-0000-0000-00000000000b';
  lead uuid; lead_b uuid; biz_a uuid; biz_b uuid; v jsonb; n int;
begin
  -- 1. A stage change is logged by the database, with who.
  perform pg_temp.act(owner);
  insert into public.leads (shop_name, phone) values ('CRM Test Shop', '9000100001') returning id into lead;
  update public.leads set status = 'contacted' where id = lead;
  if not exists (select 1 from public.lead_activities where lead_id = lead and activity_type = 'status_change'
                 and note = 'new → contacted' and created_by = owner) then
    raise exception 'FAIL 1a: stage change not logged';
  end if;
  update public.leads set status = 'negotiation', temperature = 'hot' where id = lead;
  if (select status::text from public.leads where id = lead) <> 'negotiation' then
    raise exception 'FAIL 1b: negotiation stage';
  end if;
  raise notice 'PASS 1 (stages)';

  -- 2. A shop signing up in the app: the open lead with its phone moves to Trial;
  --    a phone nobody knows becomes a new hot lead.
  perform pg_temp.act(shop_a);
  biz_a := public.create_business(jsonb_build_object('name', 'CRM Shop A', 'phone', '+91 90001 00001', 'owner_name', 'Asha'));
  perform pg_temp.act(shop_b);
  biz_b := public.create_business(jsonb_build_object('name', 'CRM Shop B', 'phone', '9000100002', 'owner_name', 'Bala'));
  perform pg_temp.act(owner);
  if (select status::text from public.leads where id = lead) <> 'trial'
     or (select converted_business_id from public.leads where id = lead) is distinct from biz_a then
    raise exception 'FAIL 2a: the existing lead did not move to Trial';
  end if;
  select id into lead_b from public.leads where converted_business_id = biz_b;
  if lead_b is null or (select source from public.leads where id = lead_b) <> 'app_signup'
     or (select temperature from public.leads where id = lead_b) <> 'hot' then
    raise exception 'FAIL 2b: no lead for the new signup';
  end if;
  raise notice 'PASS 2 (signups)';

  -- 3. The first payment wins the lead.
  insert into public.subscription_payments (business_id, amount, payment_mode, note)
  values (biz_b, 2799, 'upi', 'test');
  if (select status::text from public.leads where id = lead_b) <> 'converted'
     or (select converted_at from public.leads where id = lead_b) is null then
    raise exception 'FAIL 3: lead not won on payment';
  end if;
  raise notice 'PASS 3 (won on payment)';

  -- 4. Duplicates by phone across leads and clients.
  v := public.admin_find_duplicates('09000100001');
  if jsonb_array_length(v -> 'leads') < 1 or jsonb_array_length(v -> 'clients') < 1 then
    raise exception 'FAIL 4: duplicates %', v;
  end if;
  raise notice 'PASS 4 (duplicates)';

  -- 5. Import skips duplicates and rows without a shop name.
  v := public.admin_import_leads(jsonb_build_array(
    jsonb_build_object('shop_name', 'Imp A', 'phone', '9000100009'),
    jsonb_build_object('shop_name', 'Imp B', 'phone', '+91 9000100009'),
    jsonb_build_object('shop_name', '', 'phone', '9000100008'),
    jsonb_build_object('shop_name', 'Imp C', 'phone', '9000100001'),
    jsonb_build_object('shop_name', 'Imp D', 'business_type', 'GROCERY', 'temperature', 'Hot', 'source', 'Facebook')));
  if (v ->> 'added')::int <> 2 or jsonb_array_length(v -> 'skipped') <> 3 then
    raise exception 'FAIL 5a: import %', v;
  end if;
  if not exists (select 1 from public.leads where shop_name = 'Imp D' and business_type::text = 'grocery'
                 and temperature = 'hot' and source = 'facebook' and assigned_to = owner) then
    raise exception 'FAIL 5b: imported row not as given';
  end if;
  raise notice 'PASS 5 (import)';

  -- 6. Support (no leads area) can't import or check duplicates.
  perform pg_temp.act(support);
  begin
    perform public.admin_import_leads('[]'::jsonb);
    raise exception 'FAIL 6: support imported leads';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  select count(*) into n from public.leads;
  if n <> 0 then raise exception 'FAIL 6b: support sees leads'; end if;
  raise notice 'PASS 6 (leads area only)';
end $$;

reset role;
select 'sales_crm tests passed' as result;
rollback;
