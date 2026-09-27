-- ============================================================
-- R1 leftovers: diagnostic fee, due dates, approval push, unit
-- snapshots (migration 0052).
--
-- HOW TO RUN — on a STAGING copy, after 0052:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('cdcdcdcd-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'r1-left-owner@test.invalid'),
  ('cdcdcdcd-0000-0000-0000-00000000000c', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'r1-left-staff@test.invalid'),
  ('cdcdcdcd-0000-0000-0000-0000000000e0', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'r1-left-other@test.invalid');

insert into public.businesses (id, name, state_code) values
  ('cdcdcdcd-1111-0000-0000-00000000000a', 'R1 Leftover Shop', '27'),
  ('cdcdcdcd-1111-0000-0000-0000000000e0', 'R1 Other Shop', '27');
update public.profiles set business_id = 'cdcdcdcd-1111-0000-0000-00000000000a', role = 'owner'
  where id = 'cdcdcdcd-0000-0000-0000-00000000000a';
update public.profiles set business_id = 'cdcdcdcd-1111-0000-0000-00000000000a', role = 'staff'
  where id = 'cdcdcdcd-0000-0000-0000-00000000000c';
update public.profiles set business_id = 'cdcdcdcd-1111-0000-0000-0000000000e0', role = 'owner'
  where id = 'cdcdcdcd-0000-0000-0000-0000000000e0';
insert into public.subscriptions (business_id, status, expiry_date) values
  ('cdcdcdcd-1111-0000-0000-00000000000a', 'active', current_date + 30),
  ('cdcdcdcd-1111-0000-0000-0000000000e0', 'active', current_date + 30);

-- Sugar: sold by the kg, bought by the 50 kg bag.
insert into public.products (id, business_id, name, selling_price, purchase_price,
  secondary_unit_name, conversion_factor) values
  ('cdcdcdcd-2222-0000-0000-00000000000a', 'cdcdcdcd-1111-0000-0000-00000000000a',
   'R1 Sugar', 45, 40, 'Bag', 50);
insert into public.stock_movements (business_id, product_id, movement_type, quantity, note) values
  ('cdcdcdcd-1111-0000-0000-00000000000a', 'cdcdcdcd-2222-0000-0000-00000000000a', 'opening', 500, 'r1 test');
insert into public.customers (id, business_id, name, credit_unlimited) values
  ('cdcdcdcd-3333-0000-0000-00000000000a', 'cdcdcdcd-1111-0000-0000-00000000000a', 'R1 Kiran', true);
-- No credit allowed: any credit sale to Tara needs the owner.
insert into public.customers (id, business_id, name, credit_unlimited, credit_limit) values
  ('cdcdcdcd-3333-0000-0000-00000000000b', 'cdcdcdcd-1111-0000-0000-00000000000a', 'R1 Tara', false, 0);
-- A repair service with a 200 diagnostic fee (18% GST).
insert into public.services (id, business_id, name, price, gst_rate, sac_code, diagnostic_fee) values
  ('cdcdcdcd-5555-0000-0000-00000000000a', 'cdcdcdcd-1111-0000-0000-00000000000a',
   'Phone repair', 0, 18, '998719', 200);

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

do $$
declare
  owner  constant uuid := 'cdcdcdcd-0000-0000-0000-00000000000a';
  staff  constant uuid := 'cdcdcdcd-0000-0000-0000-00000000000c';
  other  constant uuid := 'cdcdcdcd-0000-0000-0000-0000000000e0';
  sugar  constant uuid := 'cdcdcdcd-2222-0000-0000-00000000000a';
  kiran  constant uuid := 'cdcdcdcd-3333-0000-0000-00000000000a';
  svc    constant uuid := 'cdcdcdcd-5555-0000-0000-00000000000a';
  today  constant date := public.ist_date(now());
  v jsonb; inv uuid; job uuid; job2 uuid; appr uuid;
begin
  -- 1. Unit snapshot: 100 kg sold; the line keeps "1 Bag = 50 kg".
  perform pg_temp.act(staff);
  v := public.create_invoice(jsonb_build_object(
    'invoice_type', 'non_gst', 'customer_id', kiran, 'customer_name', 'R1 Kiran',
    'paid_amount', 0, 'payment_mode', 'credit', 'due_date', today + 7,
    'items', jsonb_build_array(jsonb_build_object(
      'product_id', sugar, 'product_name', 'R1 Sugar', 'quantity', 100, 'unit_price', 45,
      'gst_rate', 0, 'tax_amount', 0, 'line_total', 4500))));
  inv := (v ->> 'id')::uuid;
  if (select alt_unit_name from public.invoice_items where invoice_id = inv) <> 'Bag'
     or (select alt_factor from public.invoice_items where invoice_id = inv) <> 50 then
    raise exception 'FAIL 1: unit not kept on the line';
  end if;
  raise notice 'PASS 1 (bill line keeps 1 Bag = 50 kg)';

  -- 2. A new credit bill can carry its own due date.
  if (select due_date from public.invoices where id = inv) <> today + 7 then
    raise exception 'FAIL 2: due date %', (select due_date from public.invoices where id = inv);
  end if;
  raise notice 'PASS 2 (new bill due in 7 days as chosen)';

  -- 3. Changing an issued bill's due date: owner only, with a reason.
  begin
    perform public.change_invoice_due_date(inv, today + 30, 'asked for time');
    raise exception 'FAIL 3a: staff changed a due date';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform pg_temp.act(owner);
  begin
    perform public.change_invoice_due_date(inv, today + 30, '');
    raise exception 'FAIL 3b: changed without a reason';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    perform public.change_invoice_due_date(inv, today - 1, 'typo');
    raise exception 'FAIL 3c: due before the bill date';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform public.change_invoice_due_date(inv, today + 30, 'Kiran asked for a month');
  if (select due_date from public.invoices where id = inv) <> today + 30 then
    raise exception 'FAIL 3d: due date not changed';
  end if;
  raise notice 'PASS 3 (owner moved the due date with a reason; staff and bad dates refused)';

  -- 4. Diagnostic fee: agreed at intake, billable without an estimate.
  perform pg_temp.act(staff);
  job := (public.create_job_card(jsonb_build_object('customer_id', kiran, 'customer_name', 'R1 Kiran',
    'item_name', 'Phone', 'issue_description', 'Dead', 'diagnostic_service_id', svc,
    'diagnostic_consent', true)) ->> 'id')::uuid;
  if (select diagnostic_fee from public.job_cards where id = job) <> 200
     or (select diagnostic_consent_at from public.job_cards where id = job) is null then
    raise exception 'FAIL 4a: fee/consent not recorded';
  end if;
  perform public.add_job_card_item(jsonb_build_object('job_card_id', job, 'is_diagnostic', true));
  begin
    perform public.add_job_card_item(jsonb_build_object('job_card_id', job, 'is_diagnostic', true));
    raise exception 'FAIL 4b: diagnostic fee charged twice';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 4 (fee 200 agreed at intake, added once without an estimate)';

  -- 5. Customer rejects the repair: the fee is still billed (200 + 18%).
  perform public.update_job_status(job, 'returned_unrepaired', 'customer declined');
  v := public.close_job_card(job, jsonb_build_object('paid_amount', 236, 'payment_mode', 'cash',
    'invoice_type', 'gst'));
  if (v ->> 'total')::numeric <> 236 then raise exception 'FAIL 5: bill %', v; end if;
  raise notice 'PASS 5 (returned unrepaired; diagnostic fee billed 236)';

  -- 6. No consent, no fee.
  job2 := (public.create_job_card(jsonb_build_object('customer_name', 'Walk-in',
    'item_name', 'Phone', 'diagnostic_service_id', svc, 'diagnostic_consent', false)) ->> 'id')::uuid;
  begin
    perform public.add_job_card_item(jsonb_build_object('job_card_id', job2, 'is_diagnostic', true));
    raise exception 'FAIL 6: fee charged without consent';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 6 (no consent → no diagnostic fee)';

  -- 7. Approval push: announced once, only for the requester's own shop.
  --    (A credit sale to Tara, who has no credit limit, needs the owner.)
  v := public.request_sale_approval(jsonb_build_object(
    'invoice_type', 'non_gst', 'customer_id', 'cdcdcdcd-3333-0000-0000-00000000000b',
    'customer_name', 'R1 Tara', 'paid_amount', 0, 'payment_mode', 'credit',
    'items', jsonb_build_array(jsonb_build_object(
      'product_id', sugar, 'product_name', 'R1 Sugar', 'quantity', 1, 'unit_price', 45,
      'gst_rate', 0, 'tax_amount', 0, 'line_total', 45))), 'regular customer');
  appr := (v ->> 'id')::uuid;
  perform pg_temp.act(other);
  if public.claim_approval_notification(appr) is not null then
    raise exception 'FAIL 7a: another shop claimed the notification';
  end if;
  perform pg_temp.act(staff);
  v := public.claim_approval_notification(appr);
  if v is null or (v ->> 'total')::numeric <> 45 or v ->> 'customer' <> 'R1 Tara'
     or public.claim_approval_notification(appr) is not null then
    raise exception 'FAIL 7b: %', v;
  end if;
  raise notice 'PASS 7 (approval announced once, own shop only)';
end $$;

reset role;
do $$ begin raise notice 'ALL R1 LEFTOVER CHECKS PASSED — rolling back test data'; end $$;
rollback;
