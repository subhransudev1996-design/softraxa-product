-- Fix get_sales_report's `by_mode` breakdown for split-payment bills.
--
-- Previously it grouped invoices.total by invoices.payment_mode — but a
-- split bill (e.g. ₹500 cash + ₹500 upi) stores a single collapsed
-- payment_mode of 'other' with the *entire* total, so a split bill's whole
-- amount was misattributed to 'other' instead of being divided across the
-- modes actually used. invoice_payments (one row per amount+mode actually
-- collected, written by create_invoice — see 0015_split_payments.sql) is
-- the correct source: sum actual collected amounts per real payment_mode.
--
-- Dormant fix: report_detail_screen.dart doesn't render `by_mode` today,
-- so this was latent/unused, not yet user-visible — fixed now so it's
-- correct before anything renders it.

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
      select ip.payment_mode,
             sum(ip.amount) as sales,
             count(distinct ip.invoice_id) as invoices
      from public.invoice_payments ip
      join public.invoices i on i.id = ip.invoice_id
      where i.business_id = v_business and not i.is_cancelled and i.invoice_type <> 'estimate'
        and i.invoice_date::date between p_from and p_to
      group by 1 order by 2 desc) m), '[]'::jsonb)
  );
end $$;
