-- ============================================================
-- Dukania AI assistant: who may use it, and product search (migration 0086).
--
-- HOW TO RUN — on a STAGING copy, after 0086:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
--
-- Shop A (owner + staff S) on a plan with "all features" (empty list),
-- then on a plan that ticks ai_assistant. Shop B has a product A must
-- never see.
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('86868686-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'ai-owner@test.invalid'),
  ('86868686-0000-0000-0000-0000000000a5', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'ai-staff@test.invalid'),
  ('86868686-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'ai-other@test.invalid');

insert into public.businesses (id, name, state_code, business_type) values
  ('86868686-1111-0000-0000-00000000000a', 'AI Test Kirana', '21', 'grocery'),
  ('86868686-1111-0000-0000-00000000000b', 'AI Other Shop', '21', 'grocery');
update public.profiles set business_id = '86868686-1111-0000-0000-00000000000a', role = 'owner'
  where id = '86868686-0000-0000-0000-00000000000a';
update public.profiles set business_id = '86868686-1111-0000-0000-00000000000a', role = 'staff'
  where id = '86868686-0000-0000-0000-0000000000a5';
update public.profiles set business_id = '86868686-1111-0000-0000-00000000000b', role = 'owner'
  where id = '86868686-0000-0000-0000-00000000000b';

insert into public.plans (id, name, software_id, user_limit, included_features)
select '86868686-9999-0000-0000-000000000001', 'AI Test All', id, 3, '[]'
from public.software_products where slug = 'dukania';
insert into public.plans (id, name, software_id, user_limit, included_features)
select '86868686-9999-0000-0000-000000000002', 'AI Test With AI', id, 3,
       '["gst_billing", "reports", "ai_assistant"]'
from public.software_products where slug = 'dukania';
insert into public.subscriptions (business_id, plan_id, status, expiry_date) values
  ('86868686-1111-0000-0000-00000000000a', '86868686-9999-0000-0000-000000000001',
   'active', current_date + 30),
  ('86868686-1111-0000-0000-00000000000b', '86868686-9999-0000-0000-000000000002',
   'active', current_date + 30);

insert into public.products (id, business_id, name, barcode, selling_price, purchase_price,
                             gst_rate, low_stock_qty) values
  ('86868686-2222-0000-0000-000000000001', '86868686-1111-0000-0000-00000000000a',
   'AI Test Sugar 1kg', '8901000000011', 48, 42, 5, 10),
  ('86868686-2222-0000-0000-000000000002', '86868686-1111-0000-0000-00000000000a',
   'AI Test Salt 1kg', '8901000000028', 28, 22, 0, 5),
  ('86868686-2222-0000-0000-000000000003', '86868686-1111-0000-0000-00000000000a',
   'AI Test Tea 250g', '', 140, 120, 5, 0),
  ('86868686-2222-0000-0000-0000000000b1', '86868686-1111-0000-0000-00000000000b',
   'AI Test Sugar Other Shop', '', 50, 40, 5, 0);
insert into public.stock_movements (business_id, product_id, movement_type, quantity, note) values
  ('86868686-1111-0000-0000-00000000000a', '86868686-2222-0000-0000-000000000001', 'opening', 3, 'ai test'),
  ('86868686-1111-0000-0000-00000000000a', '86868686-2222-0000-0000-000000000002', 'opening', 50, 'ai test'),
  ('86868686-1111-0000-0000-00000000000b', '86868686-2222-0000-0000-0000000000b1', 'opening', 9, 'ai test');

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

-- 1. Shop B's plan ticks ai_assistant; shop A's "all features" plan does not.
do $$
begin
  if not coalesce((select ai_assistant from public.feature_flags
                   where business_id = '86868686-1111-0000-0000-00000000000b'), false) then
    raise exception 'FAIL 1a: a plan that ticks ai_assistant must switch it on';
  end if;
  if coalesce((select ai_assistant from public.feature_flags
               where business_id = '86868686-1111-0000-0000-00000000000a'), false) then
    raise exception 'FAIL 1b: an "all features" plan must not switch the AI assistant on';
  end if;
  if not coalesce((select reports from public.feature_flags
                   where business_id = '86868686-1111-0000-0000-00000000000a'), false) then
    raise exception 'FAIL 1c: an "all features" plan still switches the other features on';
  end if;
end $$;

set local role authenticated;

-- 2. Not signed in / no AI in the plan.
do $$
declare v jsonb;
begin
  v := public.ai_context();
  if (v ->> 'allowed')::boolean or v ->> 'reason' not like 'Sign in%' then
    raise exception 'FAIL 2a: no login must be refused, got %', v;
  end if;
  perform pg_temp.act('86868686-0000-0000-0000-00000000000a');
  v := public.ai_context();
  if (v ->> 'allowed')::boolean or v ->> 'reason' not like '%isn''t included in your shop''s plan%' then
    raise exception 'FAIL 2b: shop without the AI feature must be refused, got %', v;
  end if;
end $$;

-- Shop A moves to the plan with AI.
reset role;
update public.subscriptions set plan_id = '86868686-9999-0000-0000-000000000002'
  where business_id = '86868686-1111-0000-0000-00000000000a';
select public.set_plan_features('86868686-1111-0000-0000-00000000000a',
                                '86868686-9999-0000-0000-000000000002');
set local role authenticated;

-- 3. Owner may; staff only once the owner allows it.
do $$
declare v jsonb;
begin
  perform pg_temp.act('86868686-0000-0000-0000-00000000000a');
  v := public.ai_context();
  if not (v ->> 'allowed')::boolean then raise exception 'FAIL 3a: owner refused: %', v; end if;
  if v #>> '{shop,name}' <> 'AI Test Kirana' or not (v #>> '{permissions,owner}')::boolean
     or not (v #>> '{subscription,can_make_changes}')::boolean then
    raise exception 'FAIL 3b: owner context wrong: %', v;
  end if;

  perform pg_temp.act('86868686-0000-0000-0000-0000000000a5');
  v := public.ai_context();
  if (v ->> 'allowed')::boolean or v ->> 'reason' not like '%hasn''t allowed you%' then
    raise exception 'FAIL 3c: staff must be refused until allowed, got %', v;
  end if;
  begin
    perform public.set_staff_ai_permission('86868686-0000-0000-0000-0000000000a5', true);
    raise exception 'FAIL 3d: staff allowed themselves';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;

  perform pg_temp.act('86868686-0000-0000-0000-00000000000b');
  begin
    perform public.set_staff_ai_permission('86868686-0000-0000-0000-0000000000a5', true);
    raise exception 'FAIL 3e: another shop''s owner allowed our staff';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;

  perform pg_temp.act('86868686-0000-0000-0000-00000000000a');
  perform public.set_staff_ai_permission('86868686-0000-0000-0000-0000000000a5', true);
  perform pg_temp.act('86868686-0000-0000-0000-0000000000a5');
  v := public.ai_context();
  if not (v ->> 'allowed')::boolean then raise exception 'FAIL 3f: allowed staff refused: %', v; end if;
  if (v #>> '{permissions,owner}')::boolean or (v #>> '{permissions,can_view_profit}')::boolean then
    raise exception 'FAIL 3g: staff permissions wrong: %', v -> 'permissions';
  end if;
end $$;

-- 4. Product search: own shop only, filters, cost only for those who may see it.
do $$
declare v jsonb;
begin
  perform pg_temp.act('86868686-0000-0000-0000-00000000000a');
  v := public.ai_find_products('ai test', 'all', 50);
  if (v ->> 'total')::int <> 3 then raise exception 'FAIL 4a: expected 3 own products, got %', v; end if;
  if v::text like '%Other Shop%' then raise exception 'FAIL 4b: another shop''s product shown'; end if;
  if v #>> '{products,0,purchase_price}' is null then raise exception 'FAIL 4c: owner must see cost'; end if;

  v := public.ai_find_products('8901000000028', 'all', 50);
  if (v ->> 'total')::int <> 1 or v #>> '{products,0,name}' <> 'AI Test Salt 1kg' then
    raise exception 'FAIL 4d: barcode search, got %', v;
  end if;

  v := public.ai_find_products('', 'low', 50);
  if (v ->> 'total')::int <> 1 or v #>> '{products,0,name}' <> 'AI Test Sugar 1kg' then
    raise exception 'FAIL 4e: low stock should be only sugar (3 of 10), got %', v;
  end if;

  v := public.ai_find_products('', 'out', 50);
  if (v ->> 'total')::int <> 1 or v #>> '{products,0,name}' <> 'AI Test Tea 250g' then
    raise exception 'FAIL 4f: out of stock should be only tea, got %', v;
  end if;

  v := public.ai_find_products('ai test', 'all', 2);
  if (v ->> 'total')::int <> 3 or (v ->> 'shown')::int <> 2 then
    raise exception 'FAIL 4g: limit, got total % shown %', v ->> 'total', v ->> 'shown';
  end if;

  perform pg_temp.act('86868686-0000-0000-0000-0000000000a5');
  v := public.ai_find_products('ai test', 'all', 50);
  if v::text like '%purchase_price%' then raise exception 'FAIL 4h: staff must not see cost'; end if;

  begin
    perform public.ai_find_products('', 'cheap', 50);
    raise exception 'FAIL 4i: unknown filter accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
end $$;

-- 5. A suspended shop can't use it.
reset role;
update public.businesses set is_active = false where id = '86868686-1111-0000-0000-00000000000a';
set local role authenticated;
do $$
declare v jsonb;
begin
  perform pg_temp.act('86868686-0000-0000-0000-00000000000a');
  v := public.ai_context();
  if (v ->> 'allowed')::boolean or v ->> 'reason' not like '%suspended%' then
    raise exception 'FAIL 5: suspended shop must be refused, got %', v;
  end if;
end $$;

select 'ai_assistant tests passed' as result;

rollback;
