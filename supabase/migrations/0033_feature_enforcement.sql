-- ============================================================
-- 0033_feature_enforcement.sql — make plan features actually control the app.
--
-- The app enforces features via the per-business `feature_flags` booleans
-- (featureOn(key) => (features[key] as bool?) ?? true — so a flag must be set
-- to FALSE to hide a feature). This migration:
--   1. Reseeds Dukania's feature list to EXACTLY the keys the app enforces.
--   2. apply_plan_features(business, plan): writes a plan's included_features
--      into that shop's feature_flags (ticked=true, everything else=false).
--   3. resync_plan_features(plan): re-applies a plan to every shop on it,
--      so editing a plan's features updates existing clients.
--
-- IMPORTANT: the feature list is fixed BY THE APP. Admin never invents
-- features — a flag can only hide a feature the Flutter app already gates.
-- These 9 keys are every `featureOn(...)` the app actually checks (verified
-- 2026-07-19). `barcode_scanning` is intentionally excluded: the app has the
-- flag column but no code gates it, so toggling it would do nothing.
-- ============================================================

-- The canonical, app-enforced feature list. Keep in sync with feature_flags
-- columns that have a matching featureOn(...) call in the Flutter app.
create or replace function public.app_feature_keys()
returns text[] language sql immutable as $$
  select array[
    'gst_billing', 'reports', 'pdf_invoice', 'a4_print', 'thermal_print',
    'offline_billing', 'expense_module', 'excel_import', 'service_module'
  ]
$$;

-- 1. Reseed Dukania's feature list (label + key) to the enforced set.
update public.software_products
set features = '[
  { "key": "gst_billing",     "label": "GST billing" },
  { "key": "reports",         "label": "Reports & analytics" },
  { "key": "pdf_invoice",     "label": "PDF invoices" },
  { "key": "a4_print",        "label": "A4 printing" },
  { "key": "thermal_print",   "label": "Thermal printing" },
  { "key": "offline_billing", "label": "Offline billing" },
  { "key": "expense_module",  "label": "Expense tracking" },
  { "key": "excel_import",    "label": "Excel import" },
  { "key": "service_module",  "label": "Services & job cards" }
]'::jsonb
where slug = 'dukania';

-- 2. Apply a plan's included_features to one shop's feature_flags.
--    Any enforced key NOT in the plan is written false (so the app hides it).
--    If plan is null / has no feature list, everything is left ON (default).
create or replace function public.apply_plan_features(p_business uuid, p_plan uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_included text[];
  v_key text;
  v_on boolean;
begin
  -- ensure a flags row exists
  insert into public.feature_flags (business_id) values (p_business)
    on conflict (business_id) do nothing;

  if p_plan is null then
    return;  -- no plan → leave defaults (all on)
  end if;

  select coalesce(array(select jsonb_array_elements_text(included_features)), '{}')
    into v_included
    from public.plans where id = p_plan;

  -- If the plan defines no features at all, treat as "all on" (don't lock a
  -- shop out just because an admin hasn't ticked anything yet).
  if array_length(v_included, 1) is null then
    return;
  end if;

  foreach v_key in array public.app_feature_keys() loop
    v_on := v_key = any(v_included);
    execute format(
      'update public.feature_flags set %I = $1, updated_at = now() where business_id = $2',
      v_key
    ) using v_on, p_business;
  end loop;
end $$;

-- 3. Re-apply a plan to every shop currently subscribed to it.
create or replace function public.resync_plan_features(p_plan uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  r record;
begin
  for r in
    select distinct business_id from public.subscriptions where plan_id = p_plan
  loop
    perform public.apply_plan_features(r.business_id, p_plan);
  end loop;
end $$;

-- Admins call these via RPC; grant execute to authenticated (guarded by
-- being called only from the admin panel, which itself is admin-gated).
grant execute on function public.apply_plan_features(uuid, uuid) to authenticated;
grant execute on function public.resync_plan_features(uuid) to authenticated;
