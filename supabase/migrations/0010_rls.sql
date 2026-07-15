-- ============================================================
-- 0010_rls.sql — row level security for every table
-- Tenant isolation: rows visible only to the owning business.
-- Main admin (profiles.role = 'admin') has full access.
-- ============================================================

-- ---------- profiles ----------
alter table public.profiles enable row level security;
create policy "own profile read" on public.profiles for select
  using (id = auth.uid() or public.is_admin());
create policy "own profile update" on public.profiles for update
  using (id = auth.uid() or public.is_admin());
create policy "admin manage profiles" on public.profiles for all
  using (public.is_admin()) with check (public.is_admin());

-- ---------- businesses ----------
alter table public.businesses enable row level security;
create policy "own business read" on public.businesses for select
  using (id = public.current_business_id() or public.is_admin());
create policy "own business update" on public.businesses for update
  using (id = public.current_business_id() or public.is_admin());
create policy "admin manage businesses" on public.businesses for all
  using (public.is_admin()) with check (public.is_admin());
-- inserts happen only via create_business() (security definer) or admin

-- ---------- feature_flags ----------
alter table public.feature_flags enable row level security;
create policy "own flags read" on public.feature_flags for select
  using (business_id = public.current_business_id() or public.is_admin());
create policy "admin manage flags" on public.feature_flags for all
  using (public.is_admin()) with check (public.is_admin());

-- ---------- doc_counters (only touched inside security-definer functions) ----------
alter table public.doc_counters enable row level security;
create policy "admin counters" on public.doc_counters for all
  using (public.is_admin()) with check (public.is_admin());

-- ---------- plans (readable by all logged-in users, managed by admin) ----------
alter table public.plans enable row level security;
create policy "plans read" on public.plans for select using (auth.uid() is not null);
create policy "admin manage plans" on public.plans for all
  using (public.is_admin()) with check (public.is_admin());

-- ---------- subscriptions / subscription_payments ----------
alter table public.subscriptions enable row level security;
create policy "own subscription read" on public.subscriptions for select
  using (business_id = public.current_business_id() or public.is_admin());
create policy "admin manage subscriptions" on public.subscriptions for all
  using (public.is_admin()) with check (public.is_admin());

alter table public.subscription_payments enable row level security;
create policy "own sub payments read" on public.subscription_payments for select
  using (business_id = public.current_business_id() or public.is_admin());
create policy "admin manage sub payments" on public.subscription_payments for all
  using (public.is_admin()) with check (public.is_admin());

-- ---------- support tickets: client creates + reads own, admin manages ----------
alter table public.support_tickets enable row level security;
create policy "own tickets read" on public.support_tickets for select
  using (business_id = public.current_business_id() or public.is_admin());
create policy "own tickets insert" on public.support_tickets for insert
  with check (business_id = public.current_business_id());
create policy "admin manage tickets" on public.support_tickets for all
  using (public.is_admin()) with check (public.is_admin());

-- ---------- audit logs: written via log_audit(), admin reads all ----------
alter table public.audit_logs enable row level security;
create policy "own audit read" on public.audit_logs for select
  using (business_id = public.current_business_id() or public.is_admin());

-- ---------- Tenant data tables: same pattern for all ----------
-- (select/insert/update/delete restricted to own business; admin full access)
do $$
declare
  t text;
begin
  foreach t in array array[
    'categories', 'brands', 'units', 'products', 'product_variants', 'product_serials',
    'customers', 'customer_payments', 'suppliers', 'supplier_payments',
    'invoices', 'invoice_items', 'invoice_payments',
    'sale_returns', 'sale_return_items',
    'purchases', 'purchase_items', 'purchase_returns', 'purchase_return_items',
    'stock_movements', 'expense_categories', 'expenses'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format(
      'create policy "tenant all" on public.%I for all
         using (business_id = public.current_business_id() or public.is_admin())
         with check (business_id = public.current_business_id() or public.is_admin())', t);
  end loop;
end $$;
