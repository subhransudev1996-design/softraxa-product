-- ============================================================
-- R1 owner approvals (migration 0044): below cost, credit limit,
-- overdue, discount limit; request → decide → complete; owner
-- acknowledgement; offline flagging; expiry.
--
-- HOW TO RUN — on a STAGING copy, after 0044:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
--
-- Shop G: item cost 300, price 500 (non-GST). Owner; staff S with price
-- permission (limit 100%) but no cost/profit permission. Customers: Ravi
-- (limit 1,000, one overdue bill of 500) and Mala (limit 1,000).
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('99999999-0000-0000-0000-000000000009', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'r1-appr-owner@test.invalid'),
  ('99999999-0000-0000-0000-000000000059', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'r1-appr-staff@test.invalid');

insert into public.businesses (id, name, state_code) values
  ('99999999-1111-0000-0000-000000000009', 'R1 Approvals Shop', '27');

update public.profiles set business_id = '99999999-1111-0000-0000-000000000009', role = 'owner'
  where id = '99999999-0000-0000-0000-000000000009';
update public.profiles set business_id = '99999999-1111-0000-0000-000000000009', role = 'staff'
  where id = '99999999-0000-0000-0000-000000000059';
insert into public.staff_permissions (profile_id, business_id, can_edit_prices, discount_limit_pct, can_view_profit)
  values ('99999999-0000-0000-0000-000000000059', '99999999-1111-0000-0000-000000000009', true, 100, false);

insert into public.subscriptions (business_id, status, expiry_date) values
  ('99999999-1111-0000-0000-000000000009', 'active', current_date + 30);

insert into public.products (id, business_id, name, selling_price, purchase_price, gst_rate) values
  ('99999999-2222-0000-0000-000000000009', '99999999-1111-0000-0000-000000000009', 'R1 Mixer', 500, 300, 0);
insert into public.stock_movements (business_id, product_id, movement_type, quantity, note) values
  ('99999999-1111-0000-0000-000000000009', '99999999-2222-0000-0000-000000000009', 'opening', 100, 'r1 test');

insert into public.customers (id, business_id, name, credit_limit, credit_unlimited) values
  ('99999999-3333-0000-0000-0000000000a1', '99999999-1111-0000-0000-000000000009', 'R1 Ravi', 1000, false),
  ('99999999-3333-0000-0000-0000000000b1', '99999999-1111-0000-0000-000000000009', 'R1 Mala', 1000, false);

-- Sale payload: qty × price for a customer (null = walk-in), money
-- collected now, extra keys merged in.
create or replace function pg_temp.sale(p_customer uuid, p_qty numeric, p_price numeric,
                                        p_paid numeric, p_extra jsonb default '{}')
returns jsonb language sql as $$
  select jsonb_build_object(
    'invoice_type', 'non_gst', 'customer_id', p_customer, 'customer_name', 'x',
    'paid_amount', p_paid, 'payment_mode', case when p_paid > 0 then 'cash' else 'credit' end,
    'items', jsonb_build_array(jsonb_build_object(
      'product_id', '99999999-2222-0000-0000-000000000009', 'product_name', 'R1 Mixer',
      'quantity', p_qty, 'unit_price', p_price, 'gst_rate', 0, 'tax_amount', 0,
      'line_total', p_qty * p_price))) || p_extra;
$$;

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

create or replace function pg_temp.stock() returns numeric language sql as $$
  select current_stock from public.products where id = '99999999-2222-0000-0000-000000000009';
$$;

set local role authenticated;

-- Ravi's overdue bill: 500 on credit, billed 40 days ago (due after 30).
select pg_temp.act('99999999-0000-0000-0000-000000000009');
select public.create_invoice(pg_temp.sale('99999999-3333-0000-0000-0000000000a1', 1, 500, 0,
  jsonb_build_object('invoice_date', now() - interval '40 days')));

do $$
declare
  owner constant uuid := '99999999-0000-0000-0000-000000000009';
  staff constant uuid := '99999999-0000-0000-0000-000000000059';
  ravi  constant uuid := '99999999-3333-0000-0000-0000000000a1';
  mala  constant uuid := '99999999-3333-0000-0000-0000000000b1';
  r jsonb; v jsonb; v2 jsonb;
  s0 numeric;
begin
  -- 1. Overdue customer: more credit needs approval (D25).
  perform pg_temp.act(staff);
  begin
    perform public.create_invoice(pg_temp.sale(ravi, 1, 500, 0));
    raise exception 'FAIL 1: credit sale to an overdue customer went through';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    if sqlerrm not like 'APPROVAL_REQUIRED%overdue%' then raise exception 'FAIL 1: %', sqlerrm; end if;
    raise notice 'PASS 1 (overdue customer: credit needs approval)';
  end;

  -- 2. …but a fully paid sale to him is fine.
  perform public.create_invoice(pg_temp.sale(ravi, 1, 500, 500));
  raise notice 'PASS 2 (fully paid sale needs no approval)';

  -- 3. Below cost (D17): refused, and staff don't see the cost.
  begin
    perform public.create_invoice(pg_temp.sale(null, 1, 250, 250));
    raise exception 'FAIL 3: below-cost sale went through';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    if sqlerrm not like 'APPROVAL_REQUIRED%below_cost%' or sqlerrm like '%"cost"%' then
      raise exception 'FAIL 3: %', sqlerrm;
    end if;
    raise notice 'PASS 3 (below cost needs approval; cost hidden from staff)';
  end;

  -- 4. Staff ask; the sale waits server-side.
  s0 := pg_temp.stock();
  r := public.request_sale_approval(pg_temp.sale(null, 1, 250, 250), 'clearance');
  if r ->> 'status' <> 'pending' or pg_temp.stock() <> s0
     or (public.my_sale_approvals() -> 0 -> 'exceptions')::text like '%"cost"%' then
    raise exception 'FAIL 4: %', r;
  end if;
  raise notice 'PASS 4 (request pending; nothing sold yet)';

  -- 5. Staff can't approve.
  begin
    perform public.decide_sale_approval((r ->> 'id')::uuid, true, 'ok', array['below_cost']);
    raise exception 'FAIL 5: staff approved a sale';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 5 (only the owner decides): %', sqlerrm;
  end;

  -- 6. Owner must tick every exception (PD15).
  perform pg_temp.act(owner);
  begin
    perform public.decide_sale_approval((r ->> 'id')::uuid, true, 'ok', '{}');
    raise exception 'FAIL 6: approved without ticking the exceptions';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform public.decide_sale_approval((r ->> 'id')::uuid, true, 'clearance ok', array['below_cost']);
  raise notice 'PASS 6 (owner approved with every exception ticked)';

  -- 7. Staff complete exactly that sale, once.
  perform pg_temp.act(staff);
  v := public.complete_approved_sale((r ->> 'id')::uuid);
  if pg_temp.stock() <> s0 - 1
     or (select exception_status from public.invoices where id = (v ->> 'id')::uuid) <> 'approved' then
    raise exception 'FAIL 7a: %', v;
  end if;
  v2 := public.complete_approved_sale((r ->> 'id')::uuid);
  if not coalesce((v2 ->> 'already_done')::boolean, false) or v2 ->> 'id' <> v ->> 'id'
     or pg_temp.stock() <> s0 - 1 then
    raise exception 'FAIL 7b: retry made another sale';
  end if;
  raise notice 'PASS 7 (approved sale completed once)';

  -- 8. The approval can't be reused for a different (cheaper) sale.
  begin
    perform public.create_invoice(pg_temp.sale(null, 1, 200, 200,
      jsonb_build_object('approval_id', r ->> 'id')));
    raise exception 'FAIL 8: approval reused';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 8 (approval bound to the sale, used once): %', sqlerrm;
  end;

  -- 9. The owner's own below-cost sale needs an explicit acknowledgement.
  perform pg_temp.act(owner);
  begin
    perform public.create_invoice(pg_temp.sale(null, 1, 250, 250));
    raise exception 'FAIL 9a: owner sold below cost without acknowledging';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  v := public.create_invoice(pg_temp.sale(null, 1, 250, 250, jsonb_build_object('owner_ack', true)));
  if (select exception_status from public.invoices where id = (v ->> 'id')::uuid) <> 'acknowledged' then
    raise exception 'FAIL 9b: acknowledgement not recorded';
  end if;
  raise notice 'PASS 9 (owner acknowledges their own exception)';

  -- 10. Over the credit limit (D24): 1,500 on credit against 1,000; rejected.
  perform pg_temp.act(staff);
  r := public.request_sale_approval(pg_temp.sale(mala, 3, 500, 0), 'regular customer');
  if (r -> 'exceptions')::text not like '%credit_limit%' then raise exception 'FAIL 10a: %', r; end if;
  perform pg_temp.act(owner);
  perform public.decide_sale_approval((r ->> 'id')::uuid, false, 'pay the old bill first');
  perform pg_temp.act(staff);
  begin
    perform public.complete_approved_sale((r ->> 'id')::uuid);
    raise exception 'FAIL 10b: rejected sale completed';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 10 (credit limit exception; rejected sale can''t complete)';
  end;

  -- 11. Beyond the staff discount limit (PD10): approval, not a hard stop.
  perform pg_temp.act(owner);
  perform public.set_staff_discount_limit(staff, 5);
  perform pg_temp.act(staff);
  begin
    perform public.create_invoice(pg_temp.sale(null, 2, 450, 900));     -- 10% below 1,000
    raise exception 'FAIL 11: 10%% discount with a 5%% limit went through';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    if sqlerrm not like 'APPROVAL_REQUIRED%discount%' then raise exception 'FAIL 11: %', sqlerrm; end if;
    raise notice 'PASS 11 (over-limit discount goes to the owner)';
  end;

  -- 12. An offline bill that syncs with an exception is kept and flagged (PD24).
  v := public.create_invoice(pg_temp.sale(null, 1, 250, 250, jsonb_build_object('offline_created', true)));
  -- Requests are only readable by the owner (staff use my_sale_approvals).
  perform pg_temp.act(owner);
  if (select exception_status from public.invoices where id = (v ->> 'id')::uuid) <> 'flagged'
     or not exists (select 1 from public.sale_approvals
                    where consumed_invoice_id = (v ->> 'id')::uuid and status = 'flagged') then
    raise exception 'FAIL 12: offline exception not flagged';
  end if;
  raise notice 'PASS 12 (offline bill kept and flagged for review)';

  perform pg_temp.act(staff);

  perform set_config('r1.req', (public.request_sale_approval(
    pg_temp.sale(mala, 3, 500, 0), 'expiry test') ->> 'id'), true);
end $$;

-- 13. Expiry (PD11): a request past its expiry can't be approved.
reset role;
update public.sale_approvals set expires_at = now() - interval '1 minute'
  where id = current_setting('r1.req')::uuid;
set local role authenticated;
select pg_temp.act('99999999-0000-0000-0000-000000000009');

do $$ begin
  begin
    perform public.decide_sale_approval(current_setting('r1.req')::uuid, true, 'late', array['credit_limit']);
    raise exception 'FAIL 13: expired request approved';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'PASS 13 (expired request can''t be approved): %', sqlerrm;
  end;
end $$;

reset role;
do $$ begin raise notice 'ALL R1 APPROVAL CHECKS PASSED — rolling back test data'; end $$;
rollback;
