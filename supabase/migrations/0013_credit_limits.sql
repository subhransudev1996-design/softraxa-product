-- Optional credit limit for customers (udhar/due cap) and suppliers.
-- Null = no limit. Purely additive; existing rows are unaffected.

alter table public.customers add column if not exists credit_limit numeric(14,2);
alter table public.suppliers add column if not exists credit_limit numeric(14,2);
