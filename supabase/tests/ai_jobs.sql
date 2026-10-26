-- ============================================================
-- Dukania AI: services and job cards (migration 0091).
--
-- HOW TO RUN — on a STAGING copy, after 0087–0091:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes with "ai_jobs tests passed". The first
-- failed check stops the run with "FAIL …".
--
-- A mobile repair shop: part "Screen" sells at ₹1,180 incl. 18% GST
-- (₹1,000 before GST), service "Screen fitting" ₹300 + 18%.
-- Ramesh's phone: estimate, approval, work, ready, billed and delivered.
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);
select set_config('request.headers', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('91919191-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'ai-job-owner@test.invalid');
insert into public.businesses (id, name, state_code, business_type, tax_preference) values
  ('91919191-1111-0000-0000-00000000000a', 'AI Mobile Repairs', '21', 'mobile_repair', 'gst');
update public.profiles set business_id = '91919191-1111-0000-0000-00000000000a', role = 'owner'
  where id = '91919191-0000-0000-0000-00000000000a';
insert into public.plans (id, name, software_id, user_limit, included_features)
select '91919191-9999-0000-0000-000000000001', 'AI Job Plan', id, 3, '[]'
from public.software_products where slug = 'dukania';
insert into public.subscriptions (business_id, plan_id, status, expiry_date) values
  ('91919191-1111-0000-0000-00000000000a', '91919191-9999-0000-0000-000000000001',
   'active', current_date + 30);
insert into public.products (id, business_id, name, selling_price, purchase_price, gst_rate, hsn_code) values
  ('91919191-2222-0000-0000-000000000001', '91919191-1111-0000-0000-00000000000a',
   'AI Test Screen', 1180, 700, 18, '8517');
insert into public.stock_movements (business_id, product_id, movement_type, quantity, note) values
  ('91919191-1111-0000-0000-00000000000a', '91919191-2222-0000-0000-000000000001', 'opening', 5, 'ai test');
insert into public.services (id, business_id, name, price, gst_rate, sac_code) values
  ('91919191-3333-0000-0000-000000000001', '91919191-1111-0000-0000-00000000000a',
   'AI Screen fitting', 300, 18, '998719');
insert into public.customers (id, business_id, name, phone, credit_unlimited) values
  ('91919191-4444-0000-0000-000000000001', '91919191-1111-0000-0000-00000000000a', 'AI Ramesh', '9000000091', true);

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
create or replace function pg_temp.job() returns public.job_cards language sql as $$
  select * from public.job_cards where business_id = '91919191-1111-0000-0000-00000000000a' limit 1;
$$;
create or replace function pg_temp.stock() returns numeric language sql as $$
  select current_stock from public.products where id = '91919191-2222-0000-0000-000000000001';
$$;
create or replace function pg_temp.work() returns jsonb language sql as $$
  select jsonb_build_array(
    jsonb_build_object('product_id', '91919191-2222-0000-0000-000000000001'),
    jsonb_build_object('service_id', '91919191-3333-0000-0000-000000000001'));
$$;

set local role authenticated;
select set_config('request.headers', '{"x-dukania-source": "ai"}', true);

do $$
declare v jsonb; j public.job_cards; inv record;
begin
  perform pg_temp.act('91919191-0000-0000-0000-00000000000a');

  -- 1. Open the job card; the same ref again doesn't open a second one.
  v := public.ai_job_action(jsonb_build_object('kind', 'create_job', 'ref', '91919191-5555-0000-0000-000000000001',
         'job', jsonb_build_object('customer_id', '91919191-4444-0000-0000-000000000001',
                                   'customer_name', 'AI Ramesh', 'customer_phone', '9000000091',
                                   'item_name', 'Phone', 'brand', 'Redmi', 'model', 'Note 12',
                                   'issue_description', 'Screen broken', 'advance_amount', 200)));
  j := pg_temp.job();
  if j.id is null or j.status <> 'received' or j.created_via <> 'ai' then raise exception 'FAIL 1a: job not opened: %', v; end if;
  v := public.ai_job_action(jsonb_build_object('kind', 'create_job', 'ref', '91919191-5555-0000-0000-000000000001',
         'job', jsonb_build_object('item_name', 'Phone')));
  if not coalesce((v ->> 'already_saved')::boolean, false)
     or (select count(*) from public.job_cards where business_id = '91919191-1111-0000-0000-00000000000a') <> 1 then
    raise exception 'FAIL 1b: second confirm opened another job';
  end if;

  -- 2. Estimate: screen ₹1,000 + fitting ₹300, both + 18% = ₹1,534.
  v := public.ai_job_action(jsonb_build_object('kind', 'estimate', 'ref', '91919191-5555-0000-0000-000000000002',
         'job_id', j.id, 'lines', pg_temp.work()));
  if (select total from public.job_estimates where job_card_id = j.id) <> 1534 then
    raise exception 'FAIL 2: estimate should be 1534: %', v;
  end if;

  -- 3. Ramesh approves on the phone: the job is in progress.
  v := public.ai_job_action(jsonb_build_object('kind', 'decision', 'ref', '91919191-5555-0000-0000-000000000003',
         'job_id', j.id, 'decision', 'approved', 'channel', 'phone'));
  if (pg_temp.job()).status <> 'in_progress' then raise exception 'FAIL 3: approved job should be in progress'; end if;

  -- 4. The work done: the part comes out of stock, once.
  v := public.ai_job_action(jsonb_build_object('kind', 'add_items', 'ref', '91919191-5555-0000-0000-000000000004',
         'job_id', j.id, 'lines', pg_temp.work()));
  if pg_temp.stock() <> 4 or (v ->> 'job_total')::numeric <> 1534 then
    raise exception 'FAIL 4a: stock 4 and job total 1534 expected, got % / %', pg_temp.stock(), v ->> 'job_total';
  end if;
  v := public.ai_job_action(jsonb_build_object('kind', 'add_items', 'ref', '91919191-5555-0000-0000-000000000004',
         'job_id', j.id, 'lines', pg_temp.work()));
  if pg_temp.stock() <> 4 then raise exception 'FAIL 4b: repeated confirm took the part twice'; end if;

  -- 5. Ready; "delivered" only comes with the bill.
  v := public.ai_job_action(jsonb_build_object('kind', 'status', 'ref', '91919191-5555-0000-0000-000000000005',
         'job_id', j.id, 'status', 'ready'));
  if (pg_temp.job()).status <> 'ready' then raise exception 'FAIL 5a: job should be ready'; end if;
  begin
    perform public.ai_job_action(jsonb_build_object('kind', 'status', 'ref', '91919191-5555-0000-0000-0000000000f5',
      'job_id', j.id, 'status', 'delivered'));
    raise exception 'FAIL 5b: delivered without a bill';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;

  -- 6. Bill it: ₹200 advance + ₹1,334 UPI; delivered; made by the AI.
  v := public.ai_job_action(jsonb_build_object('kind', 'close', 'ref', '91919191-5555-0000-0000-000000000006',
         'job_id', j.id, 'paid', 1334, 'payment_mode', 'upi'));
  select * into inv from public.invoices where id = (v ->> 'invoice_id')::uuid;
  if inv.total <> 1534 or inv.paid_amount <> 1534 or inv.created_via <> 'ai' then
    raise exception 'FAIL 6a: bill wrong: %', to_jsonb(inv);
  end if;
  if (pg_temp.job()).status <> 'delivered' then raise exception 'FAIL 6b: billed job should be delivered'; end if;
  v := public.ai_job_action(jsonb_build_object('kind', 'close', 'ref', '91919191-5555-0000-0000-000000000006',
         'job_id', j.id, 'paid', 1334, 'payment_mode', 'upi'));
  if not coalesce((v ->> 'already_saved')::boolean, false) then raise exception 'FAIL 6c: second confirm not recognised'; end if;
end $$;

-- 7. A plan without services & job cards can't use them.
reset role;
update public.feature_flags set service_module = false where business_id = '91919191-1111-0000-0000-00000000000a';
set local role authenticated;
do $$
begin
  perform pg_temp.act('91919191-0000-0000-0000-00000000000a');
  begin
    perform public.ai_job_action(jsonb_build_object('kind', 'create_job', 'ref', '91919191-5555-0000-0000-000000000007',
      'job', jsonb_build_object('item_name', 'Phone')));
    raise exception 'FAIL 7: job card made without the services feature';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
end $$;

select 'ai_jobs tests passed' as result;

rollback;
