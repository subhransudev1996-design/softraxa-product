-- ============================================================
-- Accounts and team tools (0103): GST invoices and credit notes,
-- refunds, expenses, finance by month, CA export, tasks, calendar,
-- search and alerts.
--
-- HOW TO RUN — on a STAGING copy, after 0103:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the last line shows "accounts_tools tests passed".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('10310310-0000-0000-0000-0000000000ad', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'acc-owner@test.invalid'),
  ('10310310-0000-0000-0000-00000000005a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'acc-sales@test.invalid'),
  ('10310310-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'acc-shop-a@test.invalid'),
  ('10310310-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'acc-shop-b@test.invalid');
update public.profiles set role = 'admin'
  where id in ('10310310-0000-0000-0000-0000000000ad', '10310310-0000-0000-0000-00000000005a');
insert into public.admin_team (user_id, team_role, areas) values
  ('10310310-0000-0000-0000-0000000000ad', 'owner', '{}'),
  ('10310310-0000-0000-0000-00000000005a', 'sales', '{clients,leads}');
-- Start with no GSTIN, so a payment is recorded without an invoice first.
update public.platform_settings set business_gstin = '', invoice_prefix = 'DK', gst_rate = 18 where id = 1;

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

do $$
declare
  owner constant uuid := '10310310-0000-0000-0000-0000000000ad';
  sales constant uuid := '10310310-0000-0000-0000-00000000005a';
  shop_a constant uuid := '10310310-0000-0000-0000-00000000000a';
  shop_b constant uuid := '10310310-0000-0000-0000-00000000000b';
  biz_a uuid; biz_b uuid; std uuid; p0 uuid; sale jsonb; pay uuid; inv text; v jsonb; r jsonb; n int;
begin
  perform pg_temp.act(shop_a);
  biz_a := public.create_business(jsonb_build_object('name', 'Acc Shop A', 'phone', '9000103001'));
  perform pg_temp.act(shop_b);
  biz_b := public.create_business(jsonb_build_object('name', 'Acc Shop B', 'phone', '9000103002'));
  perform pg_temp.act(owner);
  update public.businesses set state_code = '21' where id = biz_a;   -- same state as Dukania
  update public.businesses set state_code = '29' where id = biz_b;   -- another state
  select id into std from public.plans where name = 'Standard';

  -- 1. No GSTIN: no invoice. Then GSTIN set: an earlier payment gets one on request (CGST+SGST).
  insert into public.subscription_payments (business_id, amount, payment_mode, note, payment_date)
  values (biz_a, 1180, 'upi', 'test', current_date) returning id into p0;
  if (select invoice_no from public.subscription_payments where id = p0) is not null then
    raise exception 'FAIL 1a: invoice without a GSTIN';
  end if;
  update public.platform_settings set business_gstin = '21ABCDE1234F1Z5' where id = 1;
  inv := public.admin_issue_invoice(p0);
  if inv !~ '^DK/[0-9]{2}-[0-9]{2}/[0-9]{4}$' then raise exception 'FAIL 1b: invoice no %', inv; end if;
  v := (select tax from public.subscription_payments where id = p0);
  if (v ->> 'taxable')::numeric <> 1000 or (v ->> 'cgst')::numeric <> 90 or (v ->> 'sgst')::numeric <> 90
     or (v ->> 'igst')::numeric <> 0 then
    raise exception 'FAIL 1c: same-state split %', v;
  end if;
  raise notice 'PASS 1 (invoice on request)';

  -- 2. A sale now gets its invoice by itself; another state is IGST.
  sale := public.admin_record_sale(biz_b, jsonb_build_object('plan_id', std, 'amount', 2360, 'mode', 'upi', 'reference', 'UTR103'));
  pay := (sale ->> 'payment_id')::uuid;
  v := (select tax from public.subscription_payments where id = pay);
  if (select invoice_no from public.subscription_payments where id = pay) is null
     or (v ->> 'igst')::numeric <> 360 or (v ->> 'cgst')::numeric <> 0 then
    raise exception 'FAIL 2: automatic invoice %', v;
  end if;
  raise notice 'PASS 2 (automatic invoice)';

  -- 3. Refund with a credit note; ending the plan; not more than was paid.
  r := public.admin_record_refund(pay, jsonb_build_object('amount', 1180, 'reason', 'Changed mind', 'end_plan', true));
  if (r ->> 'credit_note_no') !~ '^DK-CN/' then raise exception 'FAIL 3a: credit note %', r; end if;
  if (select status::text from public.subscriptions where business_id = biz_b order by created_at desc limit 1) <> 'expired' then
    raise exception 'FAIL 3b: plan not ended';
  end if;
  begin
    perform public.admin_record_refund(pay, jsonb_build_object('amount', 2000, 'reason', 'x'));
    raise exception 'FAIL 3c: refunded more than paid';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 3 (refund)';

  -- 4. Expenses, target, the month's figures and the CA export.
  insert into public.business_expenses (category, amount, gst_paid, vendor) values ('software', 590, 90, 'Test host');
  perform public.admin_set_target(current_date, 50000, 10);
  v := public.admin_finance(3);
  v := v -> 'months' -> (jsonb_array_length(v -> 'months') - 1);
  if (v ->> 'money_in')::numeric < 3540 or (v ->> 'refunds')::numeric < 1180 or (v ->> 'money_out')::numeric < 590
     or (v ->> 'target_revenue')::numeric <> 50000 then
    raise exception 'FAIL 4a: this month %', v;
  end if;
  v := public.admin_accounts_export(current_date, current_date);
  if not exists (select 1 from jsonb_array_elements(v -> 'sales') s where s ->> 'invoice_no' = inv)
     or jsonb_array_length(v -> 'credit_notes') < 1
     or not exists (select 1 from jsonb_array_elements(v -> 'expenses') e where e ->> 'vendor' = 'Test host') then
    raise exception 'FAIL 4b: export';
  end if;
  raise notice 'PASS 4 (finance and export)';

  -- 5. A task for someone else: on the calendar and in their alerts.
  insert into public.admin_tasks (title, due_date, assigned_to) values ('Call Acc Shop A about GST', current_date, sales);
  v := public.admin_calendar(current_date, current_date);
  if not exists (select 1 from jsonb_array_elements(v) e where e ->> 'kind' = 'task' and e ->> 'title' like 'Call Acc Shop A%') then
    raise exception 'FAIL 5a: calendar %', v;
  end if;
  perform pg_temp.act(sales);
  v := public.admin_alerts();
  if not exists (select 1 from jsonb_array_elements(v -> 'items') e where e ->> 'kind' = 'task') then
    raise exception 'FAIL 5b: no alert for the task';
  end if;
  perform public.admin_mark_alerts_seen();
  raise notice 'PASS 5 (tasks, calendar, alerts)';

  -- 6. Search: Sales finds the client but not payments; can't refund.
  v := public.admin_search('Acc Shop');
  if jsonb_array_length(v -> 'clients') < 2 or jsonb_array_length(v -> 'payments') <> 0 then
    raise exception 'FAIL 6a: search %', v;
  end if;
  begin
    perform public.admin_record_refund(p0, jsonb_build_object('amount', 1, 'reason', 'x'));
    raise exception 'FAIL 6b: sales refunded';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  select count(*) into n from public.business_expenses;
  if n <> 0 then raise exception 'FAIL 6c: sales sees expenses'; end if;
  raise notice 'PASS 6 (search and areas)';
end $$;

reset role;
select 'accounts_tools tests passed' as result;
rollback;
