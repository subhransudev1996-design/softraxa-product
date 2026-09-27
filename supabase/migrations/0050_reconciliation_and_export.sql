-- ============================================================
-- 0050_reconciliation_and_export.sql — release R1, batch 11
-- (LAUNCH_SPECIFICATION.md "Ledger integrity", "Exports", pilot exit
-- criteria)
--
-- 1. Nightly reconciliation. run_reconciliation() recomputes stored
--    totals from their ledgers for every active shop and records each
--    mismatch for SOFTRAXA (admin panel → Reconciliation):
--      stock_product   products.current_stock  = sum of its stock movements
--      stock_variant   variant current_stock   = sum of its stock movements
--      customer_due    customers.due_amount    = dues of its open bills
--      customer_advance customers.advance_amount = its advance ledger
--      supplier_due    suppliers.due_amount    = dues of its purchases
--      pieces_exceed   available cut pieces can't add up to more than stock
--      invoice_amounts no bill with paid < 0, or paid + credit > total
--    Only exact rules are checked, so every issue is a real mismatch.
--    SOFTRAXA can mark an issue "explained" with a note; later runs carry
--    the note while the same difference remains. Scheduled with pg_cron
--    at 02:00 India time when pg_cron is enabled (see end of file).
-- 2. Data export. export_business_data() returns all of a shop's
--    records for the owner — also when the subscription has expired or
--    the account is suspended (their data stays theirs). The app writes
--    it as an Excel workbook, one sheet per table.
--
-- Run AFTER 0049.
-- ============================================================

-- ============================================================
-- A. Runs and issues (SOFTRAXA only)
-- ============================================================
create table if not exists public.reconciliation_runs (
  id           uuid primary key default gen_random_uuid(),
  started_at   timestamptz not null default now(),
  finished_at  timestamptz,
  businesses   integer not null default 0,
  issues       integer not null default 0,
  unexplained  integer not null default 0
);

create table if not exists public.reconciliation_issues (
  id             uuid primary key default gen_random_uuid(),
  run_id         uuid not null references public.reconciliation_runs(id) on delete cascade,
  business_id    uuid not null references public.businesses(id) on delete cascade,
  check_name     text not null,
  entity_id      uuid,
  entity_label   text not null default '',
  expected       numeric(16,3),
  actual         numeric(16,3),
  detail         text not null default '',
  explained_note text not null default '',
  explained_by   uuid references public.profiles(id),
  created_at     timestamptz not null default now()
);
create index if not exists idx_recon_issues_run on public.reconciliation_issues(run_id, business_id);
create index if not exists idx_recon_issues_key
  on public.reconciliation_issues(business_id, check_name, entity_id, created_at desc);

alter table public.reconciliation_runs enable row level security;
alter table public.reconciliation_issues enable row level security;
drop policy if exists "admin read" on public.reconciliation_runs;
create policy "admin read" on public.reconciliation_runs for select using (public.is_admin());
drop policy if exists "admin read" on public.reconciliation_issues;
create policy "admin read" on public.reconciliation_issues for select using (public.is_admin());

-- ============================================================
-- B. The checks
-- ============================================================
-- Mismatches of one shop, as rows (check, entity, label, expected, actual, detail).
create or replace function public.reconcile_business(p_business uuid)
returns table (check_name text, entity_id uuid, entity_label text,
               expected numeric, actual numeric, detail text)
language sql stable security definer set search_path = public as $$
  -- Stock: product total and each variant against the stock ledger.
  select 'stock_product', p.id, p.name, coalesce(m.qty, 0), p.current_stock, ''
  from public.products p
  left join (select product_id, sum(quantity) as qty from public.stock_movements
             where business_id = p_business group by product_id) m on m.product_id = p.id
  where p.business_id = p_business and abs(p.current_stock - coalesce(m.qty, 0)) > 0.0005
  union all
  select 'stock_variant', v.id, p.name || ' (' || v.name || ')', coalesce(m.qty, 0), v.current_stock, ''
  from public.product_variants v
  join public.products p on p.id = v.product_id
  left join (select variant_id, sum(quantity) as qty from public.stock_movements
             where business_id = p_business and variant_id is not null group by variant_id) m
    on m.variant_id = v.id
  where v.business_id = p_business and abs(v.current_stock - coalesce(m.qty, 0)) > 0.0005
  union all
  -- Customer due: the unpaid part of its bills (not cancelled, not estimates).
  select 'customer_due', c.id, c.name, coalesce(i.due, 0), c.due_amount, ''
  from public.customers c
  left join (select customer_id, sum(due_amount) as due from public.invoices
             where business_id = p_business and not is_cancelled and invoice_type <> 'estimate'
             group by customer_id) i on i.customer_id = c.id
  where c.business_id = p_business and abs(c.due_amount - coalesce(i.due, 0)) > 0.005
  union all
  -- Customer advance: its advance ledger.
  select 'customer_advance', c.id, c.name, coalesce(a.amt, 0), c.advance_amount, ''
  from public.customers c
  left join (select customer_id, sum(amount) as amt from public.customer_advance_entries
             where business_id = p_business group by customer_id) a on a.customer_id = c.id
  where c.business_id = p_business and abs(c.advance_amount - coalesce(a.amt, 0)) > 0.005
  union all
  -- Supplier due: the unpaid part of its purchases.
  select 'supplier_due', s.id, s.name, coalesce(pu.due, 0), s.due_amount, ''
  from public.suppliers s
  left join (select supplier_id, sum(due_amount) as due from public.purchases
             where business_id = p_business group by supplier_id) pu on pu.supplier_id = s.id
  where s.business_id = p_business and abs(s.due_amount - coalesce(pu.due, 0)) > 0.005
  union all
  -- Cut pieces: what's recorded as available can't exceed the stock.
  select 'pieces_exceed', p.id, p.name, p.current_stock, pc.len,
         'Available pieces add up to more than the stock'
  from public.products p
  join (select product_id, sum(length) as len from public.stock_pieces
        where business_id = p_business and status = 'available' group by product_id) pc
    on pc.product_id = p.id
  where p.business_id = p_business and p.track_pieces and pc.len > p.current_stock + 0.0005
  union all
  -- Bills: paid can't be negative; paid + credit can't exceed the total.
  select 'invoice_amounts', i.id, i.invoice_no, i.total, i.paid_amount + i.credit_amount,
         format('paid %s, credit %s, total %s', i.paid_amount, i.credit_amount, i.total)
  from public.invoices i
  where i.business_id = p_business and not i.is_cancelled
    and (i.paid_amount < -0.005 or i.paid_amount + i.credit_amount > i.total + 0.005)
$$;

-- Runs every active shop (or one) and records the mismatches.
create or replace function public.run_reconciliation(p_business uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_run   uuid;
  v_b     record;
  v_count integer := 0;
  v_total integer;
  v_open  integer;
begin
  -- Nightly job (no user) or a SOFTRAXA admin from the panel.
  if auth.uid() is not null and not public.is_admin() then
    raise exception 'Only SOFTRAXA can run the reconciliation' using errcode = '42501';
  end if;

  insert into public.reconciliation_runs default values returning id into v_run;
  for v_b in select id from public.businesses
             where is_active and (p_business is null or id = p_business) loop
    v_count := v_count + 1;
    insert into public.reconciliation_issues
      (run_id, business_id, check_name, entity_id, entity_label, expected, actual, detail,
       explained_note, explained_by)
    select v_run, v_b.id, r.check_name, r.entity_id, r.entity_label, r.expected, r.actual, r.detail,
           coalesce(prev.explained_note, ''), prev.explained_by
    from public.reconcile_business(v_b.id) r
    -- Keep an earlier explanation while the difference is unchanged.
    left join lateral (
      select x.explained_note, x.explained_by from public.reconciliation_issues x
      where x.business_id = v_b.id and x.check_name = r.check_name
        and x.entity_id is not distinct from r.entity_id and x.explained_note <> ''
        and x.expected = round(r.expected, 3) and x.actual = round(r.actual, 3)
      order by x.created_at desc limit 1) prev on true;
  end loop;

  select count(*), count(*) filter (where explained_note = '')
    into v_total, v_open from public.reconciliation_issues where run_id = v_run;
  update public.reconciliation_runs
     set finished_at = now(), businesses = v_count, issues = v_total, unexplained = v_open
   where id = v_run;
  return jsonb_build_object('run_id', v_run, 'businesses', v_count, 'issues', v_total,
                            'unexplained', v_open);
end $$;

-- SOFTRAXA explains an issue (e.g. data from before a fix).
create or replace function public.explain_reconciliation_issue(p_issue uuid, p_note text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_run uuid;
begin
  if not public.is_admin() then
    raise exception 'Only SOFTRAXA can explain reconciliation issues' using errcode = '42501';
  end if;
  if btrim(coalesce(p_note, '')) = '' then raise exception 'Write what explains it'; end if;
  update public.reconciliation_issues set explained_note = btrim(p_note), explained_by = auth.uid()
    where id = p_issue returning run_id into v_run;
  if v_run is null then raise exception 'Issue not found'; end if;
  update public.reconciliation_runs
     set unexplained = (select count(*) from public.reconciliation_issues
                        where run_id = v_run and explained_note = '')
   where id = v_run;
end $$;

-- ============================================================
-- C. Owner's data export
-- ============================================================
-- Every table with a business_id, except device tokens, internal
-- counters, the audit trail and SOFTRAXA's reconciliation records. Staff
-- are listed by name and role only.
create or replace function public.export_business_data()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_out      jsonb;
  v_table    text;
  v_rows     jsonb;
begin
  if v_business is null then raise exception 'No shop selected'; end if;
  -- Owner only; allowed after expiry or suspension (no write check).
  if not public.has_permission('owner') then
    raise exception 'Only the owner can export the shop''s data' using errcode = '42501';
  end if;

  v_out := jsonb_build_object(
    'exported_at', now(),
    'business', (select to_jsonb(b) from public.businesses b where b.id = v_business),
    'staff', (select coalesce(jsonb_agg(jsonb_build_object(
                'id', p.id, 'name', p.full_name, 'role', p.role) order by p.full_name), '[]')
              from public.profiles p where p.business_id = v_business));

  for v_table in
    select c.table_name
    from information_schema.columns c
    join information_schema.tables t
      on t.table_schema = c.table_schema and t.table_name = c.table_name
    where c.table_schema = 'public' and c.column_name = 'business_id'
      and t.table_type = 'BASE TABLE'
      and c.table_name not in ('profiles', 'device_tokens', 'doc_counters', 'audit_logs',
                               'reconciliation_issues', 'businesses')
    order by c.table_name
  loop
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]''::jsonb) from public.%I x
                    where x.business_id = $1', v_table)
      into v_rows using v_business;
    if jsonb_array_length(v_rows) > 0 then
      v_out := v_out || jsonb_build_object(v_table, v_rows);
    end if;
  end loop;

  perform public.log_audit('business.exported', 'business', v_business::text, '{}'::jsonb);
  return v_out;
end $$;

-- ============================================================
-- Grants
-- ============================================================
revoke execute on function public.reconcile_business(uuid) from public, anon, authenticated;
revoke execute on function public.run_reconciliation(uuid) from public, anon;
revoke execute on function public.explain_reconciliation_issue(uuid, text) from public, anon;
revoke execute on function public.export_business_data() from public, anon;
grant execute on function public.run_reconciliation(uuid) to authenticated;
grant execute on function public.explain_reconciliation_issue(uuid, text) to authenticated;
grant execute on function public.export_business_data() to authenticated;

-- ============================================================
-- D. Nightly schedule (02:00 India time = 20:30 UTC)
-- ============================================================
-- Needs the pg_cron extension (Dashboard → Integrations → Cron). If it
-- isn't enabled this step is skipped; enable it and re-run this block.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('dukania-nightly-reconciliation', '30 20 * * *',
                          'select public.run_reconciliation()');
    raise notice 'Nightly reconciliation scheduled at 02:00 IST';
  else
    raise notice 'pg_cron is not enabled — enable it, then re-run this block to schedule the nightly reconciliation';
  end if;
end $$;
