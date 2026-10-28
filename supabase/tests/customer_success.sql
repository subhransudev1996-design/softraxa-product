-- ============================================================
-- Customer success (0102): health score and its reasons, onboarding
-- steps, the call log and its follow-ups, "would you recommend".
--
-- HOW TO RUN — on a STAGING copy, after 0102:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the last line shows "customer_success tests passed".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('10210210-0000-0000-0000-0000000000ad', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'cs-owner@test.invalid'),
  ('10210210-0000-0000-0000-00000000005a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'cs-sales@test.invalid'),
  ('10210210-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'cs-shop-a@test.invalid'),
  ('10210210-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'cs-shop-b@test.invalid');
update public.profiles set role = 'admin'
  where id in ('10210210-0000-0000-0000-0000000000ad', '10210210-0000-0000-0000-00000000005a');
insert into public.admin_team (user_id, team_role, areas) values
  ('10210210-0000-0000-0000-0000000000ad', 'owner', '{}'),
  ('10210210-0000-0000-0000-00000000005a', 'custom', '{leads}');

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

do $$
declare
  owner constant uuid := '10210210-0000-0000-0000-0000000000ad';
  sales constant uuid := '10210210-0000-0000-0000-00000000005a';
  shop_a constant uuid := '10210210-0000-0000-0000-00000000000a';
  shop_b constant uuid := '10210210-0000-0000-0000-00000000000b';
  biz_a uuid; biz_b uuid; h jsonb; c1 uuid; v jsonb; n int;
begin
  perform pg_temp.act(shop_a);
  biz_a := public.create_business(jsonb_build_object('name', 'CS Shop A', 'phone', '9000102001'));
  perform pg_temp.act(shop_b);
  biz_b := public.create_business(jsonb_build_object('name', 'CS Shop B', 'phone', '9000102002'));
  perform pg_temp.act(owner);
  -- Shop A joined a month ago, finished setup and has never made a bill.
  update public.businesses set created_at = now() - interval '30 days', onboarding_done = true where id = biz_a;

  -- 1. Health: points off with the reasons; onboarding steps.
  select e into h from jsonb_array_elements(public.admin_shop_health()) e where (e ->> 'id')::uuid = biz_a;
  if h is null then raise exception 'FAIL 1a: shop missing'; end if;
  if (h ->> 'score')::int <> 50 or h ->> 'level' <> 'watch' then raise exception 'FAIL 1b: score %', h; end if;
  if not exists (select 1 from jsonb_array_elements_text(h -> 'reasons') r where r like 'No bill yet%') then
    raise exception 'FAIL 1c: reasons %', h -> 'reasons';
  end if;
  if jsonb_array_length(h -> 'steps') <> 9
     or (select count(*) from jsonb_array_elements(h -> 'steps') s where (s ->> 'done')::boolean) <> 1 then
    raise exception 'FAIL 1d: steps %', h -> 'steps';
  end if;
  raise notice 'PASS 1 (health)';

  -- 2. The call log: a new contact closes the older follow-up.
  c1 := public.admin_log_contact(biz_a, jsonb_build_object('kind', 'call', 'outcome', 'no_answer',
    'follow_up_date', to_char(current_date, 'YYYY-MM-DD')));
  perform public.admin_log_contact(biz_a, jsonb_build_object('kind', 'call', 'outcome', 'happy', 'note', 'Showed billing'));
  if not (select follow_up_done from public.client_contacts where id = c1) then
    raise exception 'FAIL 2a: old follow-up still open';
  end if;
  perform pg_temp.act(sales);
  begin
    perform public.admin_log_contact(biz_a, jsonb_build_object('kind', 'call'));
    raise exception 'FAIL 2b: leads-only member logged a contact';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform pg_temp.act(shop_a);
  select count(*) into n from public.client_contacts;
  if n <> 0 then raise exception 'FAIL 2c: a shop sees the call log'; end if;
  raise notice 'PASS 2 (call log)';

  -- 3. Would you recommend: asked once per round, after 14 days.
  if not public.nps_due() then raise exception 'FAIL 3a: not asked'; end if;
  perform public.submit_nps(3, 'Printing is slow');
  if public.nps_due() then raise exception 'FAIL 3b: asked again'; end if;
  perform pg_temp.act(shop_b);
  if public.nps_due() then raise exception 'FAIL 3c: a new shop was asked'; end if;
  perform pg_temp.act(owner);
  select e into h from jsonb_array_elements(public.admin_shop_health()) e where (e ->> 'id')::uuid = biz_a;
  if not exists (select 1 from jsonb_array_elements_text(h -> 'reasons') r where r like 'Would not recommend%') then
    raise exception 'FAIL 3d: low score not a reason';
  end if;
  v := public.admin_satisfaction();
  if (v ->> 'detractors')::int < 1 then raise exception 'FAIL 3e: satisfaction %', v; end if;
  raise notice 'PASS 3 (recommend)';
end $$;

reset role;
select 'customer_success tests passed' as result;
rollback;
