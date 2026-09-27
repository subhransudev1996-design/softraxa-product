-- ============================================================
-- R1 repair estimates and customer approval (migration 0046).
--
-- HOW TO RUN — on a STAGING copy, after 0046:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
--
-- Spec example (D37): the customer approves a screen (1,500) and fitting
-- (500) = 2,000. A newly found 500 repair needs approval of the revised
-- 2,500 before that work starts; a different added task with the same
-- total also needs approval (scope, not just amount).
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('99999999-0000-0000-0000-000000000009', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'r1-rep-owner@test.invalid'),
  ('99999999-0000-0000-0000-0000000000c9', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'r1-rep-tech@test.invalid'),
  ('99999999-0000-0000-0000-0000000000d9', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'r1-rep-cashier@test.invalid'),
  ('99999999-0000-0000-0000-0000000000e9', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'r1-rep-other@test.invalid');

insert into public.businesses (id, name, state_code) values
  ('99999999-1111-0000-0000-000000000009', 'R1 Repair Shop', '27'),
  ('99999999-1111-0000-0000-000000000019', 'R1 Other Shop', '27');

update public.profiles set business_id = '99999999-1111-0000-0000-000000000009', role = 'owner'
  where id = '99999999-0000-0000-0000-000000000009';
update public.profiles set business_id = '99999999-1111-0000-0000-000000000009', role = 'staff'
  where id in ('99999999-0000-0000-0000-0000000000c9', '99999999-0000-0000-0000-0000000000d9');
update public.profiles set business_id = '99999999-1111-0000-0000-000000000019', role = 'owner'
  where id = '99999999-0000-0000-0000-0000000000e9';
-- Technician: default staff rights (job cards allowed). Cashier: no job cards.
insert into public.staff_permissions (profile_id, business_id, can_manage_services)
  values ('99999999-0000-0000-0000-0000000000d9', '99999999-1111-0000-0000-000000000009', false);

insert into public.subscriptions (business_id, status, expiry_date) values
  ('99999999-1111-0000-0000-000000000009', 'active', current_date + 30),
  ('99999999-1111-0000-0000-000000000019', 'active', current_date + 30);

insert into public.products (id, business_id, name, selling_price, purchase_price, gst_rate) values
  ('99999999-2222-0000-0000-000000000009', '99999999-1111-0000-0000-000000000009',
   'R1 Screen', 1500, 900, 0);
insert into public.stock_movements (business_id, product_id, movement_type, quantity, note) values
  ('99999999-1111-0000-0000-000000000009', '99999999-2222-0000-0000-000000000009', 'opening', 10, 'r1 test');

-- Job 1 and an uploaded photo for it (a real upload goes through Storage;
-- here the object row stands in for it).
insert into public.job_cards (id, business_id, job_no, customer_name, item_name, issue_description) values
  ('99999999-5555-0000-0000-000000000001', '99999999-1111-0000-0000-000000000009', 'JOB-R1T1',
   'Ravi', 'Phone', 'Broken screen');
insert into storage.objects (bucket_id, name) values
  ('job-attachments',
   '99999999-1111-0000-0000-000000000009/99999999-5555-0000-0000-000000000001/approval.jpg');

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

create or replace function pg_temp.line(p_type text, p_name text, p_price numeric,
  p_from uuid default null, p_product uuid default null) returns jsonb language sql as $$
  select jsonb_strip_nulls(jsonb_build_object('item_type', p_type, 'name', p_name, 'quantity', 1,
    'unit_price', p_price, 'gst_rate', 0, 'from_line_id', p_from, 'product_id', p_product));
$$;

set local role authenticated;

do $$
declare
  owner    constant uuid := '99999999-0000-0000-0000-000000000009';
  tech     constant uuid := '99999999-0000-0000-0000-0000000000c9';
  cashier  constant uuid := '99999999-0000-0000-0000-0000000000d9';
  other    constant uuid := '99999999-0000-0000-0000-0000000000e9';
  biz      constant uuid := '99999999-1111-0000-0000-000000000009';
  screen   constant uuid := '99999999-2222-0000-0000-000000000009';
  job1     constant uuid := '99999999-5555-0000-0000-000000000001';
  photo    constant text := '99999999-1111-0000-0000-000000000009/99999999-5555-0000-0000-000000000001/approval.jpg';
  e1 uuid; e2 uuid; e3 uuid; a1 uuid; a3 uuid;
  l_screen uuid; l_fit uuid; l_extra uuid; l3_screen uuid; l3_fit uuid; l3_speaker uuid;
  job2 uuid; job3 uuid; v jsonb; n numeric; s text;
begin
  perform pg_temp.act(owner);

  -- 1. No work before an approved estimate.
  begin
    perform public.update_job_status(job1, 'in_progress');
    raise exception 'FAIL 1: work started without an approved estimate';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 1 (work waits for approval): %', sqlerrm;
  end;

  -- 2. No part/labour outside an estimate.
  begin
    perform public.add_job_card_item(jsonb_build_object('job_card_id', job1,
      'item_type', 'labor', 'name', 'Cleaning', 'unit_price', 100));
    raise exception 'FAIL 2: added unapproved work';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 2 (no free-form work): %', sqlerrm;
  end;

  -- 3. Version 1: screen 1,500 + fitting 500 = 2,000.
  v := public.create_job_estimate(job1, jsonb_build_array(
    pg_temp.line('part', 'R1 Screen', 1500, null, screen),
    pg_temp.line('labor', 'Fitting', 500)));
  e1 := (v ->> 'id')::uuid;
  if (v ->> 'total')::numeric <> 2000 or (v ->> 'version')::int <> 1
     or (select status from public.job_cards where id = job1) <> 'waiting_approval' then
    raise exception 'FAIL 3: % / %', v, (select status from public.job_cards where id = job1);
  end if;
  select id into l_screen from public.job_estimate_lines where estimate_id = e1 and item_type = 'part';
  select id into l_fit from public.job_estimate_lines where estimate_id = e1 and item_type = 'labor';
  raise notice 'PASS 3 (estimate v1 = 2,000; job waiting for approval)';

  -- 4. An answer needs a name and a real time.
  begin
    perform public.record_estimate_decision(e1, 'approved', '  ', 'in_person');
    raise exception 'FAIL 4a: approval without a name';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    perform public.record_estimate_decision(e1, 'approved', 'Ravi', 'phone', null, now() + interval '1 day');
    raise exception 'FAIL 4b: approval dated in the future';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 4 (name and a real time needed)';

  -- 5. Staff without job-card rights can't record it.
  perform pg_temp.act(cashier);
  begin
    perform public.record_estimate_decision(e1, 'approved', 'Ravi', 'in_person');
    raise exception 'FAIL 5: cashier recorded an approval';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 5 (permission needed): %', sqlerrm;
  end;

  -- 6. Technician records the approval (staff-recorded); work starts.
  perform pg_temp.act(tech);
  v := public.record_estimate_decision(e1, 'approved', 'Ravi', 'in_person', null, null, 'at the counter');
  a1 := (v ->> 'id')::uuid;
  if v ->> 'decision' <> 'approved' or (v ->> 'approved_total')::numeric <> 2000
     or (select status from public.job_cards where id = job1) <> 'in_progress'
     or (select verification from public.job_estimate_approvals where id = a1) <> 'staff_recorded' then
    raise exception 'FAIL 6: %', v;
  end if;
  raise notice 'PASS 6 (approved 2,000, staff-recorded; job in progress)';

  -- 7. Use the screen: stock goes down once; a second screen isn't approved.
  perform public.add_job_card_item(jsonb_build_object('job_card_id', job1,
    'estimate_line_id', l_screen, 'quantity', 1));
  select sum(quantity) into n from public.stock_movements where product_id = screen;
  if n <> 9 then raise exception 'FAIL 7a: stock %', n; end if;
  begin
    perform public.add_job_card_item(jsonb_build_object('job_card_id', job1,
      'estimate_line_id', l_screen, 'quantity', 1));
    raise exception 'FAIL 7b: used more than approved';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 7 (screen used, stock 10 → 9; no second screen)';

  -- 8. A different price than approved is refused, even written directly.
  begin
    insert into public.job_card_items (business_id, job_card_id, item_type, name, quantity,
      unit_price, line_total, estimate_line_id)
    values (biz, job1, 'labor', 'Fitting', 1, 800, 800, l_fit);
    raise exception 'FAIL 8: billed fitting at 800 instead of 500';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 8 (approved price enforced): %', sqlerrm;
  end;

  -- 9. Version 2 adds a 500 repair (2,500). Until approved, the extra
  --    work can't be done; version 1 stays the approved one.
  v := public.create_job_estimate(job1, jsonb_build_array(
    pg_temp.line('part', 'R1 Screen', 1500, l_screen, screen),
    pg_temp.line('labor', 'Fitting', 500, l_fit),
    pg_temp.line('labor', 'Water damage cleaning', 500)));
  e2 := (v ->> 'id')::uuid;
  select id into l_extra from public.job_estimate_lines where estimate_id = e2 and name = 'Water damage cleaning';
  if (v ->> 'total')::numeric <> 2500 or public.current_job_estimate(job1) <> e1
     or (select status from public.job_cards where id = job1) <> 'in_progress' then
    raise exception 'FAIL 9a: %', v;
  end if;
  begin
    perform public.add_job_card_item(jsonb_build_object('job_card_id', job1,
      'estimate_line_id', l_extra, 'quantity', 1));
    raise exception 'FAIL 9b: extra work done before approval';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 9 (v2 = 2,500 awaiting; v1 approval doesn''t cover it)';

  -- 10. Version 3: same 2,500 total but a different added task. v2 is
  --     replaced; an answer to v2 is refused.
  v := public.create_job_estimate(job1, jsonb_build_array(
    pg_temp.line('part', 'R1 Screen', 1500, l_screen, screen),
    pg_temp.line('labor', 'Fitting', 500, l_fit),
    pg_temp.line('labor', 'Speaker replacement', 500)));
  e3 := (v ->> 'id')::uuid;
  if (select status from public.job_estimates where id = e2) <> 'superseded' then
    raise exception 'FAIL 10a: v2 not superseded';
  end if;
  begin
    perform public.record_estimate_decision(e2, 'approved', 'Ravi', 'phone');
    raise exception 'FAIL 10b: approved a replaced version';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 10 (same total, new scope = new version; stale answer refused): %', sqlerrm;
  end;
  select id into l3_screen from public.job_estimate_lines where estimate_id = e3 and item_type = 'part';
  select id into l3_fit from public.job_estimate_lines where estimate_id = e3 and name = 'Fitting';
  select id into l3_speaker from public.job_estimate_lines where estimate_id = e3 and name = 'Speaker replacement';

  -- 11. A version that drops the screen already fitted is refused.
  begin
    perform public.create_job_estimate(job1, jsonb_build_array(
      pg_temp.line('labor', 'Fitting', 500, l_fit)));
    raise exception 'FAIL 11: estimate dropped work already done';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 11 (done work stays in scope): %', sqlerrm;
  end;

  -- 12. Partial approval can't leave out work already done.
  begin
    perform public.record_estimate_decision(e3, 'approved', 'Ravi', 'phone', array[l3_fit]);
    raise exception 'FAIL 12: partial approval left out the fitted screen';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 12 (done work stays approved): %', sqlerrm;
  end;

  -- 13. Customer approves v3 except the speaker (PD61).
  v := public.record_estimate_decision(e3, 'approved', 'Ravi', 'whatsapp',
    array[l3_screen, l3_fit], null, 'no speaker for now');
  a3 := (v ->> 'id')::uuid;
  if v ->> 'decision' <> 'partially_approved' or (v ->> 'approved_total')::numeric <> 2000
     or public.current_job_estimate(job1) <> e3
     or (select estimate_line_id from public.job_card_items where job_card_id = job1) <> l3_screen
     or (select decision from public.job_estimate_approvals where id = a1) <> 'approved' then
    raise exception 'FAIL 13a: %', v;
  end if;
  begin
    perform public.add_job_card_item(jsonb_build_object('job_card_id', job1,
      'estimate_line_id', l3_speaker, 'quantity', 1));
    raise exception 'FAIL 13b: worked on a line the customer didn''t approve';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 13 (partial approval 2,000; fitted screen moved to v3; v1 answer kept)';

  -- 14. Evidence photo: must be uploaded, and under this shop and job.
  begin
    perform public.add_job_attachment(job1, biz::text || '/' || job1::text || '/missing.jpg',
      'approval_evidence', 'missing.jpg', 'image/jpeg', 100, a3);
    raise exception 'FAIL 14a: attached a file that was never uploaded';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    perform public.add_job_attachment(job1, 'someone-else/' || job1::text || '/approval.jpg',
      'approval_evidence', 'approval.jpg', 'image/jpeg', 100, a3);
    raise exception 'FAIL 14b: attached a file from outside this shop';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform public.add_job_attachment(job1, photo, 'approval_evidence', 'approval.jpg',
    'image/jpeg', 100, a3);
  if (select count(*) from public.job_attachments where job_card_id = job1 and approval_id = a3) <> 1
     or (select count(*) from storage.objects where name = photo) <> 1 then
    raise exception 'FAIL 14c: evidence not recorded or not readable by the shop';
  end if;
  raise notice 'PASS 14 (WhatsApp screenshot attached to the v3 answer)';

  -- 15. Another shop sees none of it.
  perform pg_temp.act(other);
  if (select count(*) from public.job_estimates where job_card_id = job1) <> 0
     or (select count(*) from public.job_estimate_approvals where job_card_id = job1) <> 0
     or (select count(*) from public.job_attachments where job_card_id = job1) <> 0
     or (select count(*) from storage.objects where name = photo) <> 0 then
    raise exception 'FAIL 15a: another shop can see the estimate or photo';
  end if;
  begin
    perform public.add_job_attachment(job1, photo, 'other');
    raise exception 'FAIL 15b: another shop attached to this job';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 15 (estimates and photos stay inside the shop)';

  -- 16. Bill = approved work actually done: screen 1,500 + fitting 500.
  perform pg_temp.act(owner);
  perform public.add_job_card_item(jsonb_build_object('job_card_id', job1,
    'estimate_line_id', l3_fit, 'quantity', 1));
  v := public.close_job_card(job1, jsonb_build_object('paid_amount', 2000,
    'payment_mode', 'cash', 'invoice_type', 'non_gst'));
  if (v ->> 'total')::numeric <> 2000 then raise exception 'FAIL 16: bill %', v; end if;
  select sum(quantity) into n from public.stock_movements where product_id = screen;
  if n <> 9 then raise exception 'FAIL 16b: stock % (part deducted twice?)', n; end if;
  raise notice 'PASS 16 (bill 2,000 — no speaker, screen deducted once)';

  -- 17. Rejection: nothing can start; the answer is on record.
  perform pg_temp.act(tech);
  job2 := (public.create_job_card(jsonb_build_object('customer_name', 'Meena',
    'item_name', 'Phone', 'issue_description', 'Not charging')) ->> 'id')::uuid;
  v := public.create_job_estimate(job2, jsonb_build_array(pg_temp.line('labor', 'Charging port', 800)));
  perform public.record_estimate_decision((v ->> 'id')::uuid, 'rejected', 'Meena', 'phone');
  begin
    perform public.update_job_status(job2, 'in_progress');
    raise exception 'FAIL 17: work started after rejection';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform public.update_job_status(job2, 'returned_unrepaired', 'customer declined');
  if (select decision from public.job_estimate_approvals where job_card_id = job2) <> 'rejected' then
    raise exception 'FAIL 17b: rejection not recorded';
  end if;
  raise notice 'PASS 17 (rejected: returned unrepaired, answer kept)';

  -- 18. Vehicle job needs a registration number (PD64).
  begin
    perform public.create_job_card(jsonb_build_object('job_type', 'vehicle',
      'customer_name', 'Arjun', 'item_name', 'Bike'));
    raise exception 'FAIL 18a: vehicle job without registration';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  job3 := (public.create_job_card(jsonb_build_object('job_type', 'vehicle', 'customer_name', 'Arjun',
    'item_name', 'Bike', 'registration_no', 'mh 12 ab 1234', 'odometer_km', 15230,
    'fuel_level', 'half')) ->> 'id')::uuid;
  select registration_no into s from public.job_cards where id = job3;
  if s <> 'MH12AB1234' then raise exception 'FAIL 18b: registration %', s; end if;
  raise notice 'PASS 18 (vehicle registration required, stored as MH12AB1234)';

  -- 19. A shop that turns estimates off works as before.
  perform pg_temp.act(owner);
  update public.businesses set require_repair_estimate = false where id = biz;
  job3 := (public.create_job_card(jsonb_build_object('customer_name', 'Walk-in',
    'item_name', 'Fan')) ->> 'id')::uuid;
  perform public.add_job_card_item(jsonb_build_object('job_card_id', job3,
    'item_type', 'labor', 'name', 'Service', 'unit_price', 200));
  perform public.update_job_status(job3, 'in_progress');
  raise notice 'PASS 19 (estimates off: free-form work as before)';
end $$;

reset role;
do $$ begin raise notice 'ALL R1 REPAIR ESTIMATE CHECKS PASSED — rolling back test data'; end $$;
rollback;
