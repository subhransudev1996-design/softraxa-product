-- ============================================================
-- Reverse charge on expenses (migration 0080).
--
-- HOW TO RUN — on a STAGING copy, after 0079 and 0080:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
--
-- Shop: Maharashtra (27). Expenses today:
--   Rent ₹10,000, reverse charge 18%, landlord in the state
--   Freight ₹2,000, reverse charge 5%, transporter in another state
--   Tea ₹500, no reverse charge
-- and rent ₹10,000 at 18% forty days ago (outside the period).
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('80808080-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'rc-owner@test.invalid');
insert into public.businesses (id, name, state_code, gst_number) values
  ('80808080-1111-0000-0000-00000000000a', 'RC Shop', '27', '27AAPFU0939F1ZV');
update public.profiles set business_id = '80808080-1111-0000-0000-00000000000a', role = 'owner'
  where id = '80808080-0000-0000-0000-00000000000a';
insert into public.plans (id, name, software_id, user_limit, included_features)
select '80808080-9999-0000-0000-00000000000a', 'RC Plan', id, 2, '[]'
from public.software_products where slug = 'dukania';
insert into public.subscriptions (business_id, plan_id, status, expiry_date) values
  ('80808080-1111-0000-0000-00000000000a', '80808080-9999-0000-0000-00000000000a',
   'active', current_date + 30);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"80808080-0000-0000-0000-00000000000a","role":"authenticated"}', true);

insert into public.expenses (business_id, amount, expense_date, note, rcm_rate, rcm_inter) values
  ('80808080-1111-0000-0000-00000000000a', 10000, current_date, 'rent', 18, false),
  ('80808080-1111-0000-0000-00000000000a', 2000, current_date, 'freight', 5, true),
  ('80808080-1111-0000-0000-00000000000a', 500, current_date, 'tea', 0, false),
  ('80808080-1111-0000-0000-00000000000a', 10000, current_date - 40, 'old rent', 18, false);

do $$
declare
  v_g3 jsonb;
  v_rc jsonb;
  v_c  jsonb;
begin
  -- 1. GSTR-3B: 3.1(d) value 12,000; IGST 100; CGST 900; SGST 900; 2 expenses.
  v_g3 := public.get_gstr3b(current_date, current_date);
  v_rc := v_g3 -> 'reverse_charge';
  if (v_rc ->> 'taxable_value')::numeric <> 12000
     or (v_rc ->> 'igst_amount')::numeric <> 100
     or (v_rc ->> 'cgst_amount')::numeric <> 900
     or (v_rc ->> 'sgst_amount')::numeric <> 900
     or (v_rc ->> 'count')::int <> 2 then
    raise exception 'FAIL 1: reverse charge %', v_rc;
  end if;

  -- 2. The rest of GSTR-3B is still there.
  if not (v_g3 ? 'outward_taxable' and v_g3 ? 'itc_available') then
    raise exception 'FAIL 2: GSTR-3B lost its other figures %', v_g3;
  end if;

  -- 3. Composition return carries the same reverse charge.
  v_c := public.get_composition_return(current_date, current_date);
  if (v_c -> 'reverse_charge' ->> 'taxable_value')::numeric <> 12000
     or not (v_c ? 'turnover') then
    raise exception 'FAIL 3: composition %', v_c;
  end if;

  -- 4. A period with only the old rent.
  v_rc := public.get_gstr3b(current_date - 45, current_date - 35) -> 'reverse_charge';
  if (v_rc ->> 'cgst_amount')::numeric <> 900 or (v_rc ->> 'count')::int <> 1 then
    raise exception 'FAIL 4: older period %', v_rc;
  end if;

  -- 5. Only 0, 5 and 18 are accepted.
  begin
    insert into public.expenses (business_id, amount, rcm_rate)
      values ('80808080-1111-0000-0000-00000000000a', 100, 12);
    raise exception 'FAIL 5: a 12%% reverse charge was accepted';
  exception when check_violation then null;
  end;

  -- 6. The inner function can't be called directly.
  begin
    perform public.get_reverse_charge_impl(current_date, current_date);
    raise exception 'FAIL 6: get_reverse_charge_impl is callable';
  exception when insufficient_privilege then null;
  end;
end $$;

rollback;
