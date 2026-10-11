-- ============================================================
-- 0080_reverse_charge.sql — GST the shop pays itself (reverse charge)
-- ============================================================
-- Some expenses carry GST that the shop, not the supplier, must pay:
-- rent for a shop taken from an unregistered landlord (18%, from Oct
-- 2024) and road freight paid to a goods transport agency (GTA, 5%) are
-- the common ones. The shop pays that tax in cash with GSTR-3B (table
-- 3.1(d)) and, as a regular GST shop, claims it back as credit in the
-- same return (table 4(A)(3)). A composition shop pays it with CMP-08.
--
-- expenses.rcm_rate  0 = no reverse charge, else the GST rate (5 or 18).
-- expenses.rcm_inter the supplier is in another state (IGST, not CGST+SGST).
-- The expense amount is the value paid to the supplier; the tax is on top.
--
-- get_gstr3b and get_composition_return gain a "reverse_charge" key:
-- {taxable_value, igst_amount, cgst_amount, sgst_amount, count}.
-- ============================================================

alter table public.expenses
  add column if not exists rcm_rate numeric(5,2) not null default 0,
  add column if not exists rcm_inter boolean not null default false;

alter table public.expenses drop constraint if exists expenses_rcm_rate_check;
alter table public.expenses add constraint expenses_rcm_rate_check
  check (rcm_rate in (0, 5, 18));

-- Reverse-charge tax on the expenses of a period, per head. Tax is worked
-- out per expense and rounded to the paisa; within the state it splits
-- half CGST, half SGST.
create or replace function public.get_reverse_charge_impl(p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_result   jsonb;
begin
  with e as (
    select amount, rcm_inter, round(amount * rcm_rate / 100, 2) as tax
    from public.expenses
    where business_id = v_business and rcm_rate > 0
      and expense_date between p_from and p_to)
  select jsonb_build_object(
    'taxable_value', coalesce(sum(amount), 0),
    'igst_amount', coalesce(sum(tax) filter (where rcm_inter), 0),
    'cgst_amount', coalesce(sum(round(tax / 2, 2)) filter (where not rcm_inter), 0),
    'sgst_amount', coalesce(sum(tax - round(tax / 2, 2)) filter (where not rcm_inter), 0),
    'count', count(*))
  into v_result from e;
  return v_result;
end $$;

revoke execute on function public.get_reverse_charge_impl(date, date) from public, anon, authenticated;

create or replace function public.get_gstr3b(p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_reports();
  return public.get_gstr3b_impl(p_from, p_to)
    || jsonb_build_object('reverse_charge', public.get_reverse_charge_impl(p_from, p_to));
end $$;

create or replace function public.get_composition_return(p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_reports();
  return public.get_composition_return_impl(p_from, p_to)
    || jsonb_build_object('reverse_charge', public.get_reverse_charge_impl(p_from, p_to));
end $$;

revoke execute on function public.get_gstr3b(date, date) from public, anon;
revoke execute on function public.get_composition_return(date, date) from public, anon;
grant execute on function public.get_gstr3b(date, date) to authenticated;
grant execute on function public.get_composition_return(date, date) to authenticated;
