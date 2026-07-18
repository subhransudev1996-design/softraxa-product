-- Product expiry tracking (for the notification bell's expired /
-- near-expiry alerts). One optional date per product — batch-level expiry
-- (different dates per purchase lot) is out of scope for V1; shops that
-- need it can model batches as variants.
alter table public.products add column expiry_date date;

comment on column public.products.expiry_date is
  'Optional expiry date; drives the expired/near-expiry alerts in the app''s notification bell.';

-- The alert query filters active products with a non-null expiry_date at or
-- below a cutoff — keep it cheap even for large catalogs.
create index idx_products_expiry on public.products(business_id, expiry_date)
  where expiry_date is not null;
