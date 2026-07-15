-- Secondary (bulk) unit for products — PRD Phase 3 "partial quantities".
-- Kirana buys sugar by the Bag (1 Bag = 50 kg) but sells by the kg; a rod
-- store buys full rods (1 Rod = 12 m) and sells cut lengths in metres.
--
-- Stock is ALWAYS tracked in the base unit (products.unit_id) so every
-- existing report, stock movement and RPC stays correct — the secondary
-- unit is a client-side entry/display convenience: the purchase form and
-- POS convert bulk-unit entries to base units before anything is saved.
--
-- Deliberately a plain text label (not a units FK): a second FK to units
-- would make every existing `units(...)` PostgREST embed on products
-- ambiguous and break the app's queries.
alter table public.products
  add column if not exists secondary_unit_name text,
  add column if not exists conversion_factor numeric(12,3)
    check (conversion_factor is null or conversion_factor > 0);

comment on column public.products.secondary_unit_name is
  'Optional bulk unit label, e.g. Bag / Box / Rod. Display + entry only; stock stays in the base unit.';
comment on column public.products.conversion_factor is
  '1 secondary unit = X base units (e.g. Bag of sugar: 50).';
