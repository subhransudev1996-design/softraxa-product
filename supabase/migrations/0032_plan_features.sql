-- ============================================================
-- 0032_plan_features.sql — plans pick a software product, a subset of its
-- features, and a max-user (staff-login) limit.
--
-- Flow: a software product (software_products, 0031) defines its FULL feature
-- list in `features` jsonb. A plan belongs to one product (plans.software_id,
-- added in 0031) and ticks the subset of feature keys it includes, plus how
-- many staff logins it allows.
-- ============================================================

-- Feature keys included in this plan (subset of the product's feature list).
-- e.g. ["gst_billing","barcode_scanning","reports"]
alter table public.plans
  add column included_features jsonb not null default '[]'::jsonb;

-- Max staff logins this plan allows for a shop. null = unlimited.
alter table public.plans
  add column user_limit integer;

-- ---------- Seed Dukania's master feature list ----------
-- Mirrors the per-business feature_flags booleans (0001_core.sql) so plan
-- features map straight onto what the app already toggles.
update public.software_products
set features = '[
  { "key": "gst_billing",      "label": "GST billing" },
  { "key": "barcode_scanning", "label": "Barcode scanning" },
  { "key": "excel_import",     "label": "Excel import" },
  { "key": "reports",          "label": "Reports & analytics" },
  { "key": "pdf_invoice",      "label": "PDF invoices" },
  { "key": "thermal_print",    "label": "Thermal printing" },
  { "key": "a4_print",         "label": "A4 printing" },
  { "key": "offline_billing",  "label": "Offline billing" },
  { "key": "expense_module",   "label": "Expense tracking" }
]'::jsonb
where slug = 'dukania';
