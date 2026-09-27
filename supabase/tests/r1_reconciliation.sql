-- ============================================================
-- R1 nightly reconciliation and data export (migration 0050).
--
-- HOW TO RUN — on a STAGING copy, after 0050:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('abcdabcd-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'r1-recon-clean@test.invalid'),
  ('abcdabcd-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'r1-recon-broken@test.invalid'),
  ('abcdabcd-0000-0000-0000-0000000000c0', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'r1-recon-staff@test.invalid'),
  ('abcdabcd-0000-0000-0000-0000000000ad', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'r1-recon-admin@test.invalid');

insert into public.businesses (id, name, state_code) values
  ('abcdabcd-1111-0000-0000-00000000000a', 'R1 Clean Shop', '27'),
  ('abcdabcd-1111-0000-0000-00000000000b', 'R1 Broken Shop', '27');
update public.profiles set business_id = 'abcdabcd-1111-0000-0000-00000000000a', role = 'owner'
  where id = 'abcdabcd-0000-0000-0000-00000000000a';
update public.profiles set business_id = 'abcdabcd-1111-0000-0000-00000000000b', role = 'owner'
  where id = 'abcdabcd-0000-0000-0000-00000000000b';
update public.profiles set business_id = 'abcdabcd-1111-0000-0000-00000000000a', role = 'staff'
  where id = 'abcdabcd-0000-0000-0000-0000000000c0';
update public.profiles set role = 'admin' where id = 'abcdabcd-0000-0000-0000-0000000000ad';
-- The clean shop's subscription has expired (export must still work).
insert into public.subscriptions (business_id, status, expiry_date, grace_days) values
  ('abcdabcd-1111-0000-0000-00000000000a', 'expired', current_date - 10, 0),
  ('abcdabcd-1111-0000-0000-00000000000b', 'active', current_date + 30, 0);

insert into public.products (id, business_id, name, selling_price, purchase_price) values
  ('abcdabcd-2222-0000-0000-00000000000a', 'abcdabcd-1111-0000-0000-00000000000a', 'R1 Bulb', 50, 30),
  ('abcdabcd-2222-0000-0000-00000000000b', 'abcdabcd-1111-0000-0000-00000000000b', 'R1 Bulb', 50, 30);
insert into public.stock_movements (business_id, product_id, movement_type, quantity, note) values
  ('abcdabcd-1111-0000-0000-00000000000a', 'abcdabcd-2222-0000-0000-00000000000a', 'opening', 10, 'r1 test'),
  ('abcdabcd-1111-0000-0000-00000000000b', 'abcdabcd-2222-0000-0000-00000000000b', 'opening', 10, 'r1 test');
insert into public.customers (id, business_id, name) values
  ('abcdabcd-3333-0000-0000-00000000000a', 'abcdabcd-1111-0000-0000-00000000000a', 'R1 Ravi'),
  ('abcdabcd-3333-0000-0000-00000000000b', 'abcdabcd-1111-0000-0000-00000000000b', 'R1 Ravi');

-- Break the second shop the way a bug would: stock and a due changed
-- without their ledgers (only possible as the database owner).
update public.products set current_stock = 9 where id = 'abcdabcd-2222-0000-0000-00000000000b';
update public.customers set due_amount = 50 where id = 'abcdabcd-3333-0000-0000-00000000000b';

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

do $$
declare
  clean    constant uuid := 'abcdabcd-1111-0000-0000-00000000000a';
  broken   constant uuid := 'abcdabcd-1111-0000-0000-00000000000b';
  owner_a  constant uuid := 'abcdabcd-0000-0000-0000-00000000000a';
  staff    constant uuid := 'abcdabcd-0000-0000-0000-0000000000c0';
  admin    constant uuid := 'abcdabcd-0000-0000-0000-0000000000ad';
  v jsonb; iss uuid;
begin
  -- 1. A shop owner can't run it or see the results.
  perform pg_temp.act(owner_a);
  begin
    perform public.run_reconciliation(clean);
    raise exception 'FAIL 1: shop owner ran the reconciliation';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 1 (SOFTRAXA only)';

  -- 2. A consistent shop has no issues.
  perform pg_temp.act(admin);
  v := public.run_reconciliation(clean);
  if (v ->> 'issues')::int <> 0 then raise exception 'FAIL 2: clean shop has issues: %', v; end if;
  raise notice 'PASS 2 (consistent shop: 0 issues)';

  -- 3. The broken shop: stock 9 vs ledger 10, due 50 vs bills 0.
  v := public.run_reconciliation(broken);
  if (v ->> 'issues')::int <> 2 or (v ->> 'unexplained')::int <> 2
     or not exists (select 1 from public.reconciliation_issues
                    where run_id = (v ->> 'run_id')::uuid and check_name = 'stock_product'
                      and expected = 10 and actual = 9)
     or not exists (select 1 from public.reconciliation_issues
                    where run_id = (v ->> 'run_id')::uuid and check_name = 'customer_due'
                      and expected = 0 and actual = 50) then
    raise exception 'FAIL 3: %', v;
  end if;
  raise notice 'PASS 3 (found stock 9 vs 10 and due 50 vs 0)';

  -- 4. An explanation carries into the next run while the difference stays.
  select id into iss from public.reconciliation_issues
    where run_id = (v ->> 'run_id')::uuid and check_name = 'customer_due';
  perform public.explain_reconciliation_issue(iss, 'Opening due typed in before 0038');
  v := public.run_reconciliation(broken);
  if (v ->> 'issues')::int <> 2 or (v ->> 'unexplained')::int <> 1 then
    raise exception 'FAIL 4: %', v;
  end if;
  raise notice 'PASS 4 (explained issue stays explained; 1 unexplained left)';

  -- 5. Shops never see SOFTRAXA's reconciliation records.
  perform pg_temp.act(owner_a);
  if exists (select 1 from public.reconciliation_issues)
     or exists (select 1 from public.reconciliation_runs) then
    raise exception 'FAIL 5: shop can read reconciliation records';
  end if;
  raise notice 'PASS 5 (records visible to SOFTRAXA only)';

  -- 6. Owner export works even with an expired subscription.
  v := public.export_business_data();
  if v -> 'business' ->> 'id' <> clean::text
     or jsonb_array_length(v -> 'products') <> 1
     or jsonb_array_length(v -> 'customers') <> 1
     or jsonb_array_length(v -> 'staff') <> 2
     or v ? 'device_tokens' or v ? 'audit_logs' then
    raise exception 'FAIL 6: %', left(v::text, 400);
  end if;
  raise notice 'PASS 6 (owner export after expiry: business, staff, products, customers…)';

  -- 7. Staff can't export.
  perform pg_temp.act(staff);
  begin
    perform public.export_business_data();
    raise exception 'FAIL 7: staff exported the shop''s data';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 7 (owner only): %', sqlerrm;
  end;
end $$;

reset role;
do $$ begin raise notice 'ALL R1 RECONCILIATION CHECKS PASSED — rolling back test data'; end $$;
rollback;
