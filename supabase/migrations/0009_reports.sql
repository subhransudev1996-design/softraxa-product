-- ============================================================
-- 0009_reports.sql — dashboard stats and report RPCs (PRD 7.3, 7.16)
-- ============================================================

-- ---------- Dashboard (PRD 7.3) ----------
create or replace function public.get_dashboard_stats()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_today_start timestamptz := date_trunc('day', now());
begin
  if v_business is null then raise exception 'No business for current user'; end if;
  return jsonb_build_object(
    'today_sales', coalesce((
      select sum(total) from public.invoices
      where business_id = v_business and not is_cancelled
        and invoice_type <> 'estimate' and invoice_date >= v_today_start), 0),
    'today_invoice_count', coalesce((
      select count(*) from public.invoices
      where business_id = v_business and not is_cancelled
        and invoice_type <> 'estimate' and invoice_date >= v_today_start), 0),
    'today_profit', coalesce((
      select sum((ii.quantity * ii.unit_price - ii.discount_amount)
                 - (ii.quantity * ii.cost_price))
      from public.invoice_items ii
      join public.invoices i on i.id = ii.invoice_id
      where i.business_id = v_business and not i.is_cancelled
        and i.invoice_type <> 'estimate' and i.invoice_date >= v_today_start), 0),
    'stock_value', coalesce((
      select sum(sub.value) from (
        select p.current_stock * p.purchase_price as value
          from public.products p
          where p.business_id = v_business and p.is_active and not p.has_variants
        union all
        select v.current_stock * coalesce(v.purchase_price, p.purchase_price)
          from public.product_variants v
          join public.products p on p.id = v.product_id
          where v.business_id = v_business and v.is_active
      ) sub), 0),
    'low_stock_count', coalesce((
      select count(*) from public.products
      where business_id = v_business and is_active and not has_variants
        and low_stock_qty > 0 and current_stock <= low_stock_qty and current_stock > 0), 0)
      + coalesce((
      select count(*) from public.product_variants v join public.products p on p.id = v.product_id
      where v.business_id = v_business and v.is_active
        and coalesce(v.low_stock_qty, p.low_stock_qty) > 0
        and v.current_stock <= coalesce(v.low_stock_qty, p.low_stock_qty)
        and v.current_stock > 0), 0),
    'out_of_stock_count', coalesce((
      select count(*) from public.products
      where business_id = v_business and is_active and not has_variants
        and current_stock <= 0), 0)
      + coalesce((
      select count(*) from public.product_variants
      where business_id = v_business and is_active and current_stock <= 0), 0),
    'customer_due_total', coalesce((
      select sum(due_amount) from public.customers
      where business_id = v_business and due_amount > 0), 0),
    'supplier_due_total', coalesce((
      select sum(due_amount) from public.suppliers
      where business_id = v_business and due_amount > 0), 0)
  );
end $$;

-- ---------- Sales report (today / monthly / custom range) ----------
create or replace function public.get_sales_report(p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
begin
  return jsonb_build_object(
    'total_sales', coalesce((select sum(total) from public.invoices
      where business_id = v_business and not is_cancelled and invoice_type <> 'estimate'
        and invoice_date::date between p_from and p_to), 0),
    'invoice_count', coalesce((select count(*) from public.invoices
      where business_id = v_business and not is_cancelled and invoice_type <> 'estimate'
        and invoice_date::date between p_from and p_to), 0),
    'total_paid', coalesce((select sum(paid_amount) from public.invoices
      where business_id = v_business and not is_cancelled and invoice_type <> 'estimate'
        and invoice_date::date between p_from and p_to), 0),
    'total_due', coalesce((select sum(due_amount) from public.invoices
      where business_id = v_business and not is_cancelled and invoice_type <> 'estimate'
        and invoice_date::date between p_from and p_to), 0),
    'total_tax', coalesce((select sum(tax_amount) from public.invoices
      where business_id = v_business and not is_cancelled and invoice_type <> 'estimate'
        and invoice_date::date between p_from and p_to), 0),
    'by_day', coalesce((select jsonb_agg(row_to_json(d)) from (
      select invoice_date::date as day, sum(total) as sales, count(*) as invoices
      from public.invoices
      where business_id = v_business and not is_cancelled and invoice_type <> 'estimate'
        and invoice_date::date between p_from and p_to
      group by 1 order by 1) d), '[]'::jsonb),
    'by_mode', coalesce((select jsonb_agg(row_to_json(m)) from (
      select payment_mode, sum(total) as sales, count(*) as invoices
      from public.invoices
      where business_id = v_business and not is_cancelled and invoice_type <> 'estimate'
        and invoice_date::date between p_from and p_to
      group by 1 order by 2 desc) m), '[]'::jsonb)
  );
end $$;

-- ---------- Product-wise sales report ----------
create or replace function public.get_product_sales_report(p_from date, p_to date)
returns table (
  product_id uuid, product_name text, variant_name text,
  qty_sold numeric, revenue numeric, profit numeric
) language sql security definer set search_path = public as $$
  select ii.product_id, ii.product_name, ii.variant_name,
         sum(ii.quantity) as qty_sold,
         sum(ii.line_total) as revenue,
         sum((ii.quantity * ii.unit_price - ii.discount_amount) - ii.quantity * ii.cost_price) as profit
  from public.invoice_items ii
  join public.invoices i on i.id = ii.invoice_id
  where i.business_id = public.current_business_id()
    and not i.is_cancelled and i.invoice_type <> 'estimate'
    and i.invoice_date::date between p_from and p_to
  group by ii.product_id, ii.product_name, ii.variant_name
  order by revenue desc
$$;

-- ---------- Profit report ----------
create or replace function public.get_profit_report(p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_sales numeric; v_cogs numeric; v_expenses numeric; v_returns numeric;
begin
  select coalesce(sum(ii.quantity * ii.unit_price - ii.discount_amount), 0),
         coalesce(sum(ii.quantity * ii.cost_price), 0)
    into v_sales, v_cogs
    from public.invoice_items ii join public.invoices i on i.id = ii.invoice_id
    where i.business_id = v_business and not i.is_cancelled
      and i.invoice_type <> 'estimate' and i.invoice_date::date between p_from and p_to;
  select coalesce(sum(amount), 0) into v_expenses from public.expenses
    where business_id = v_business and expense_date between p_from and p_to;
  select coalesce(sum(total), 0) into v_returns from public.sale_returns
    where business_id = v_business and return_date::date between p_from and p_to;
  return jsonb_build_object(
    'sales', v_sales, 'cogs', v_cogs, 'sale_returns', v_returns,
    'gross_profit', v_sales - v_returns - v_cogs,
    'expenses', v_expenses,
    'net_profit', v_sales - v_returns - v_cogs - v_expenses);
end $$;

-- ---------- GST report (tax collected by rate, PRD 7.16) ----------
create or replace function public.get_gst_report(p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
begin
  return jsonb_build_object(
    'output_tax', coalesce((select jsonb_agg(row_to_json(t)) from (
      select ii.gst_rate,
             sum(ii.quantity * ii.unit_price - ii.discount_amount) as taxable_value,
             sum(ii.tax_amount) as tax_amount
      from public.invoice_items ii join public.invoices i on i.id = ii.invoice_id
      where i.business_id = v_business and not i.is_cancelled and i.invoice_type = 'gst'
        and i.invoice_date::date between p_from and p_to
      group by ii.gst_rate order by ii.gst_rate) t), '[]'::jsonb),
    'input_tax', coalesce((select jsonb_agg(row_to_json(t)) from (
      select pi.gst_rate,
             sum(pi.quantity * pi.unit_price - pi.discount_amount) as taxable_value,
             sum(pi.tax_amount) as tax_amount
      from public.purchase_items pi join public.purchases p on p.id = pi.purchase_id
      where p.business_id = v_business
        and p.purchase_date between p_from and p_to
      group by pi.gst_rate order by pi.gst_rate) t), '[]'::jsonb)
  );
end $$;

-- ---------- Expense report ----------
create or replace function public.get_expense_report(p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
begin
  return jsonb_build_object(
    'total', coalesce((select sum(amount) from public.expenses
      where business_id = v_business and expense_date between p_from and p_to), 0),
    'by_category', coalesce((select jsonb_agg(row_to_json(c)) from (
      select coalesce(ec.name, 'Uncategorised') as category, sum(e.amount) as amount, count(*) as entries
      from public.expenses e left join public.expense_categories ec on ec.id = e.category_id
      where e.business_id = v_business and e.expense_date between p_from and p_to
      group by 1 order by 2 desc) c), '[]'::jsonb)
  );
end $$;

-- ---------- Admin dashboard (PRD 8.1) ----------
create or replace function public.get_admin_dashboard()
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admin only'; end if;
  return jsonb_build_object(
    'total_clients',   (select count(*) from public.businesses),
    'active_clients',  (select count(*) from public.subscriptions where status = 'active'),
    'trial_clients',   (select count(*) from public.subscriptions where status = 'trial'),
    'expired_clients', (select count(*) from public.subscriptions
                        where status = 'expired'
                           or (status in ('trial','active') and expiry_date + grace_days < current_date)),
    'suspended_clients', (select count(*) from public.subscriptions where status = 'suspended'),
    'monthly_revenue', coalesce((select sum(amount) from public.subscription_payments
                        where payment_date >= date_trunc('month', current_date)), 0),
    'new_clients_this_month', (select count(*) from public.businesses
                        where created_at >= date_trunc('month', now())),
    'plan_wise', coalesce((select jsonb_agg(row_to_json(p)) from (
        select coalesce(pl.name, 'No plan') as plan, count(*) as clients
        from public.subscriptions s left join public.plans pl on pl.id = s.plan_id
        group by 1 order by 2 desc) p), '[]'::jsonb),
    'open_tickets', (select count(*) from public.support_tickets where status <> 'resolved')
  );
end $$;
