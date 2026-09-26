-- ============================================================
-- 0045_cashbook.sql — release R1, batch 6
-- (LAUNCH_SPECIFICATION.md D34–D36, PD54–PD58)
--
-- One shared cash drawer per shop (D35 default). The day's cash is
-- derived from the records that already hold it — no double entry:
--   in : cash taken on bills (the cash part of split payments), customer
--        payments and advances, job-card advances, supplier refunds,
--        owner cash added, bank withdrawals
--   out: cash refunds (returns, advances), payment reversals, supplier
--        payments, cash expenses, owner withdrawals, bank deposits
-- Credit sales, advances used on bills and exchange credit are not cash.
-- UPI / card / other are shown separately and never touch the drawer.
--
-- Each movement counts on the day it was recorded (Indian time). Once a
-- day is closed, anything recorded later falls into the next open day,
-- so a closing never changes afterwards (PD57).
--
-- Closing (D34, D36, PD54–PD56): staff with the cash permission count the
-- drawer and submit; a difference needs a reason; the owner reviews. The
-- closing is locked; only the owner can reopen it (with a reason — the
-- old version is kept). Next day's opening = the counted cash (PD56).
--
-- Run AFTER 0044.
-- ============================================================

-- ============================================================
-- A. Permission
-- ============================================================
alter table public.staff_permissions add column if not exists can_manage_cash boolean not null default false;

create or replace function public.staff_permission_defaults()
returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'can_create_invoice', true,
    'can_edit_prices', false,
    'can_view_profit', false,
    'can_manage_products', true,
    'can_manage_stock', false,
    'can_manage_expenses', false,
    'can_manage_services', true,
    'can_view_reports', false,
    'can_manage_staff', false,
    'can_manage_purchases', false,
    'can_manage_returns', false,
    'can_edit_invoices', false,
    'can_record_payments', true,
    'can_manage_cash', false);
$$;

create or replace function public.permission_label(p_perm text)
returns text language sql immutable as $$
  select coalesce(jsonb_build_object(
    'can_create_invoice', 'create bills',
    'can_edit_prices', 'change prices or give discounts',
    'can_view_profit', 'view cost and profit',
    'can_manage_products', 'manage products',
    'can_manage_stock', 'adjust stock',
    'can_manage_expenses', 'manage expenses',
    'can_manage_services', 'manage services and job cards',
    'can_view_reports', 'view reports',
    'can_manage_purchases', 'manage purchases and suppliers',
    'can_manage_returns', 'process returns',
    'can_edit_invoices', 'edit or cancel bills',
    'can_record_payments', 'record payments',
    'can_manage_cash', 'manage the cash drawer and closing',
    'owner', 'do this (owner only)') ->> p_perm, p_perm);
$$;

-- Owner turns the cash permission on or off for a staff member.
create or replace function public.set_staff_cash_permission(p_profile uuid, p_value boolean)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
begin
  perform public.assert_can('owner');
  if not exists (select 1 from public.profiles
                 where id = p_profile and business_id = v_business and role::text <> 'owner') then
    raise exception 'Staff member not found';
  end if;
  perform public.write_staff_permissions(p_profile, v_business, '{}'::jsonb);
  update public.staff_permissions set can_manage_cash = coalesce(p_value, false), updated_at = now()
    where profile_id = p_profile;
end $$;

-- ============================================================
-- B. Tables
-- ============================================================
-- Cash moved by hand: owner adds/takes cash, bank deposits/withdrawals.
create table if not exists public.cash_entries (
  id          uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  kind        text not null check (kind in
                ('owner_in', 'owner_out', 'bank_deposit', 'bank_withdrawal', 'other_in', 'other_out')),
  amount      numeric(14,2) not null check (amount > 0),
  note        text not null default '',
  created_by  uuid references public.profiles(id),
  created_at  timestamptz not null default now()
);
create index if not exists idx_cash_entries_business on public.cash_entries (business_id, created_at);

-- Day closings. A reopened closing stays as history (status 'reopened').
create table if not exists public.cash_closings (
  id              uuid primary key default gen_random_uuid(),
  business_id     uuid not null references public.businesses(id) on delete cascade,
  business_date   date not null,
  version         integer not null default 1,
  opening_cash    numeric(14,2) not null,
  cash_in         numeric(14,2) not null,
  cash_out        numeric(14,2) not null,
  expected_cash   numeric(14,2) not null,
  counted_cash    numeric(14,2) not null,
  variance        numeric(14,2) not null,
  reason          text not null default '',
  denominations   jsonb,
  snapshot        jsonb not null,
  status          text not null default 'submitted' check (status in ('submitted', 'reviewed', 'reopened')),
  submitted_by    uuid references public.profiles(id),
  submitted_at    timestamptz not null default now(),
  reviewed_by     uuid references public.profiles(id),
  reviewed_at     timestamptz,
  review_note     text not null default '',
  reopened_by     uuid references public.profiles(id),
  reopened_at     timestamptz,
  reopen_reason   text not null default ''
);
create unique index if not exists uq_cash_closings_active
  on public.cash_closings (business_id, business_date) where status <> 'reopened';
create index if not exists idx_cash_closings_business on public.cash_closings (business_id, business_date desc);

do $$
declare t text;
begin
  foreach t in array array['cash_entries', 'cash_closings'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "cash read" on public.%I', t);
    execute format('drop policy if exists "admin all" on public.%I', t);
    execute format('create policy "cash read" on public.%I for select
      using (business_id = (select public.current_business_id())
             and (select public.has_permission(''can_manage_cash'')))', t);
    execute format('create policy "admin all" on public.%I for all
      using (public.is_admin()) with check (public.is_admin())', t);
  end loop;
end $$;

-- ============================================================
-- C. Cash movements, derived from their source records
-- ============================================================
create or replace function public.cash_movements(p_business uuid, p_from date, p_to date)
returns table (ts timestamptz, source text, ref_id uuid, label text, mode text,
               direction integer, amount numeric)
language sql stable security definer set search_path = public as $$
  select * from (
    -- money taken on bills (split payments: each mode separately)
    select ip.created_at, 'bill_payment', ip.invoice_id, 'Bill ' || i.invoice_no,
           ip.payment_mode::text, 1, ip.amount
    from public.invoice_payments ip join public.invoices i on i.id = ip.invoice_id
    where ip.business_id = p_business and not ip.is_advance and not ip.reversed
      and ip.customer_payment_id is null and ip.sale_return_id is null
    union all
    -- customer payments and advances received
    select cp.created_at, 'customer_payment', cp.id, 'Payment — ' || c.name,
           cp.payment_mode::text, 1, cp.amount
    from public.customer_payments cp join public.customers c on c.id = cp.customer_id
    where cp.business_id = p_business
    union all
    -- a reversed payment leaves on the day it was reversed
    select cp.reversed_at, 'payment_reversal', cp.id, 'Payment reversed — ' || c.name,
           cp.payment_mode::text, -1, cp.amount
    from public.customer_payments cp join public.customers c on c.id = cp.customer_id
    where cp.business_id = p_business and cp.reversed_at is not null
    union all
    select jc.created_at, 'job_advance', jc.id, 'Advance — job ' || jc.job_no,
           jc.advance_mode::text, 1, jc.advance_amount
    from public.job_cards jc
    where jc.business_id = p_business and jc.advance_amount > 0
    union all
    select sr.created_at, 'return_refund', sr.id, 'Refund — return ' || sr.return_no,
           sr.refund_mode::text, -1, sr.refund_amount
    from public.sale_returns sr
    where sr.business_id = p_business and sr.refund_amount > 0 and sr.refund_mode <> 'credit'
    union all
    select e.created_at, 'advance_refund', e.id, 'Advance refunded — ' || c.name,
           coalesce(e.payment_mode::text, 'cash'), -1, -e.amount
    from public.customer_advance_entries e join public.customers c on c.id = e.customer_id
    where e.business_id = p_business and e.kind = 'refund'
    union all
    select sp.created_at, 'supplier_payment', sp.id, 'Paid — ' || s.name,
           sp.payment_mode::text, -1, sp.amount
    from public.supplier_payments sp join public.suppliers s on s.id = sp.supplier_id
    where sp.business_id = p_business
    union all
    select pr.created_at, 'supplier_refund', pr.id, 'Refund from supplier — ' || pr.return_no,
           'cash', 1, pr.received_amount
    from public.purchase_returns pr
    where pr.business_id = p_business and pr.received_amount > 0
    union all
    select x.created_at, 'expense', x.id,
           'Expense — ' || coalesce(ec.name, 'other') || case when x.note <> '' then ' (' || x.note || ')' else '' end,
           x.payment_mode::text, -1, x.amount
    from public.expenses x left join public.expense_categories ec on ec.id = x.category_id
    where x.business_id = p_business
    union all
    select ce.created_at, 'manual', ce.id,
           case ce.kind when 'owner_in' then 'Cash added by owner'
                        when 'owner_out' then 'Cash taken by owner'
                        when 'bank_deposit' then 'Deposited in bank'
                        when 'bank_withdrawal' then 'Withdrawn from bank'
                        when 'other_in' then 'Other cash in'
                        else 'Other cash out' end
             || case when ce.note <> '' then ' — ' || ce.note else '' end,
           'cash', case when ce.kind in ('owner_in', 'bank_withdrawal', 'other_in') then 1 else -1 end,
           ce.amount
    from public.cash_entries ce
    where ce.business_id = p_business
  ) m (ts, source, ref_id, label, mode, direction, amount)
  where public.ist_date(m.ts) between p_from and p_to;
$$;

-- The shop day a movement belongs to: its Indian date, or the next open
-- day if that day was already closed before it was recorded (PD57).
create or replace function public.cash_day(p_business uuid, p_ts timestamptz)
returns date language plpgsql stable security definer set search_path = public as $$
declare
  d date := public.ist_date(p_ts);
begin
  while exists (select 1 from public.cash_closings
                where business_id = p_business and business_date = d
                  and status <> 'reopened' and submitted_at < p_ts) loop
    d := d + 1;
  end loop;
  return d;
end $$;

-- The cashbook for one day (internal: no permission check).
create or replace function public.cashbook_data(p_business uuid, p_date date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_opening numeric := 0;
  v_result  jsonb;
begin
  -- PD56: opening = counted cash of the last closed day before this one.
  select counted_cash into v_opening from public.cash_closings
    where business_id = p_business and business_date < p_date and status <> 'reopened'
    order by business_date desc limit 1;
  v_opening := coalesce(v_opening, 0);

  with m as (
    select * from public.cash_movements(p_business, p_date - 7, p_date) x
    where public.cash_day(p_business, x.ts) = p_date)
  select jsonb_build_object(
    'date', p_date,
    'opening', v_opening,
    'lines', coalesce((select jsonb_agg(jsonb_build_object(
                'ts', ts, 'source', source, 'ref_id', ref_id, 'label', label,
                'direction', direction, 'amount', amount) order by ts)
              from m where mode = 'cash'), '[]'::jsonb),
    'cash_in', coalesce((select sum(amount) from m where mode = 'cash' and direction = 1), 0),
    'cash_out', coalesce((select sum(amount) from m where mode = 'cash' and direction = -1), 0),
    'non_cash', coalesce((select jsonb_agg(jsonb_build_object('mode', mode, 'in', i, 'out', o) order by mode)
              from (select mode,
                           coalesce(sum(amount) filter (where direction = 1), 0) as i,
                           coalesce(sum(amount) filter (where direction = -1), 0) as o
                    from m where mode <> 'cash' group by mode) t), '[]'::jsonb)
  ) into v_result;

  return v_result || jsonb_build_object(
    'expected', (v_result ->> 'opening')::numeric + (v_result ->> 'cash_in')::numeric
                - (v_result ->> 'cash_out')::numeric);
end $$;

revoke execute on function public.cash_movements(uuid, date, date) from public, anon, authenticated;
revoke execute on function public.cash_day(uuid, timestamptz) from public, anon, authenticated;
revoke execute on function public.cashbook_data(uuid, date) from public, anon, authenticated;

-- ============================================================
-- D. App-facing functions
-- ============================================================

-- One day's cashbook with its closing (and earlier versions).
create or replace function public.get_cashbook(p_date date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
begin
  perform public.assert_can('can_manage_cash', false);
  return public.cashbook_data(v_business, p_date) || jsonb_build_object(
    'closing', (select to_jsonb(c) - 'snapshot' from public.cash_closings c
                where c.business_id = v_business and c.business_date = p_date and c.status <> 'reopened'),
    'history', coalesce((select jsonb_agg(to_jsonb(c) - 'snapshot' order by c.version)
                from public.cash_closings c
                where c.business_id = v_business and c.business_date = p_date and c.status = 'reopened'),
               '[]'::jsonb),
    'last_closed', (select max(business_date) from public.cash_closings
                    where business_id = v_business and status <> 'reopened'));
end $$;

-- Record cash moved by hand (owner cash, bank transfers, other).
create or replace function public.add_cash_entry(p_kind text, p_amount numeric, p_note text default '')
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
begin
  perform public.assert_can('can_manage_cash');
  if p_amount is null or p_amount <= 0 then raise exception 'Amount must be positive'; end if;
  if p_kind in ('other_in', 'other_out') and length(trim(coalesce(p_note, ''))) < 3 then
    raise exception 'Say what this cash is for';
  end if;
  insert into public.cash_entries (business_id, kind, amount, note, created_by)
  values (public.current_business_id(), p_kind, round(p_amount, 2), coalesce(trim(p_note), ''), auth.uid())
  returning id into v_id;
  perform public.log_audit('cash.entry', 'cash_entry', v_id::text,
    jsonb_build_object('kind', p_kind, 'amount', p_amount));
  return v_id;
end $$;

-- Count the drawer and close the day (PD54). A difference needs a reason.
create or replace function public.submit_cash_closing(
  p_date date, p_counted numeric, p_reason text default '', p_denominations jsonb default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_book     jsonb;
  v_expected numeric;
  v_variance numeric;
  v_version  integer;
  v_row      public.cash_closings;
begin
  perform public.assert_can('can_manage_cash');
  if p_date > public.ist_date(now()) then raise exception 'A future day can''t be closed'; end if;
  if p_counted is null or p_counted < 0 then raise exception 'Enter the cash you counted'; end if;
  perform pg_advisory_xact_lock(hashtext(v_business::text || p_date::text));

  if exists (select 1 from public.cash_closings
             where business_id = v_business and business_date = p_date and status <> 'reopened') then
    raise exception 'This day is already closed';
  end if;

  v_book := public.cashbook_data(v_business, p_date);
  v_expected := (v_book ->> 'expected')::numeric;
  v_variance := round(p_counted - v_expected, 2);
  if abs(v_variance) > 0.005 and length(trim(coalesce(p_reason, ''))) < 3 then
    raise exception 'The count is % from expected — give a reason', v_variance;
  end if;

  select coalesce(max(version), 0) + 1 into v_version from public.cash_closings
    where business_id = v_business and business_date = p_date;

  insert into public.cash_closings
    (business_id, business_date, version, opening_cash, cash_in, cash_out, expected_cash,
     counted_cash, variance, reason, denominations, snapshot, submitted_by)
  values
    (v_business, p_date, v_version, (v_book ->> 'opening')::numeric, (v_book ->> 'cash_in')::numeric,
     (v_book ->> 'cash_out')::numeric, v_expected, round(p_counted, 2), v_variance,
     coalesce(trim(p_reason), ''), p_denominations, v_book, auth.uid())
  returning * into v_row;

  perform public.log_audit('cash.closed', 'cash_closing', v_row.id::text,
    jsonb_build_object('date', p_date, 'expected', v_expected, 'counted', p_counted, 'variance', v_variance));
  return to_jsonb(v_row) - 'snapshot';
end $$;

-- Owner reviews a submitted closing.
create or replace function public.review_cash_closing(p_id uuid, p_note text default '')
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_can('owner', false);
  update public.cash_closings
     set status = 'reviewed', reviewed_by = auth.uid(), reviewed_at = now(),
         review_note = coalesce(trim(p_note), '')
   where id = p_id and business_id = public.current_business_id() and status = 'submitted';
  if not found then raise exception 'Nothing to review'; end if;
end $$;

-- Owner reopens a closed day (D36). The old version stays as history;
-- the day can then be closed again.
create or replace function public.reopen_cash_closing(p_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_can('owner', false);
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'Give a reason for reopening'; end if;
  update public.cash_closings
     set status = 'reopened', reopened_by = auth.uid(), reopened_at = now(),
         reopen_reason = trim(p_reason)
   where id = p_id and business_id = public.current_business_id() and status <> 'reopened';
  if not found then raise exception 'Closing not found'; end if;
  perform public.log_audit('cash.reopened', 'cash_closing', p_id::text,
    jsonb_build_object('reason', trim(p_reason)));
end $$;

-- ============================================================
-- E. Locks on source records (D36): a cash expense in a closed day can't
-- be changed or removed except by the owner. (Other sources can't be
-- edited once recorded; reversals and refunds are new movements.)
-- ============================================================
create or replace function public.guard_closed_cash_expense()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.payment_mode = 'cash' and auth.uid() is not null and not public.has_permission('owner')
     and exists (select 1 from public.cash_closings c
                 where c.business_id = old.business_id and c.status <> 'reopened'
                   and c.business_date = public.cash_day(old.business_id, old.created_at)) then
    raise exception 'That day''s cash is closed — ask the owner to change this expense'
      using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;

drop trigger if exists trg_expenses_cash_lock on public.expenses;
create trigger trg_expenses_cash_lock before update or delete on public.expenses
  for each row execute function public.guard_closed_cash_expense();

-- ============================================================
-- F. Job cards: the advance is cash when booked, not again when the bill
-- is made (replaces 0017's close_job_card; only the advance row changed).
-- ============================================================
create or replace function public.close_job_card(p_job_id uuid, payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business      uuid := public.current_business_id();
  v_job           record;
  v_item          record;
  v_subtotal      numeric(14,2) := 0;
  v_tax           numeric(14,2) := 0;
  v_total         numeric(14,2);
  v_paid_now      numeric(14,2) := coalesce((payload ->> 'paid_amount')::numeric, 0);
  v_paid_raw      numeric(14,2);
  v_paid          numeric(14,2);
  v_scale         numeric;
  v_mode          public.payment_mode := coalesce((payload ->> 'payment_mode')::public.payment_mode, 'cash');
  v_invoice_id    uuid;
  v_invoice_no    text;
  v_prefix        text;
  v_status        public.payment_status;
  v_warranty_days integer := (payload ->> 'warranty_days')::integer;
  v_item_count    integer;
begin
  select * into v_job from public.job_cards
    where id = p_job_id and business_id = v_business for update;
  if v_job is null then raise exception 'Job card not found'; end if;
  if v_job.invoice_id is not null then raise exception 'Job card already closed'; end if;

  select count(*) into v_item_count from public.job_card_items where job_card_id = p_job_id;
  if v_item_count = 0 then
    raise exception 'Add at least one part or labor line before closing';
  end if;

  for v_item in select * from public.job_card_items where job_card_id = p_job_id loop
    v_subtotal := v_subtotal + (v_item.quantity * v_item.unit_price);
    v_tax := v_tax + (v_item.line_total - v_item.quantity * v_item.unit_price);
  end loop;
  v_total := v_subtotal + v_tax;
  v_paid_raw := v_job.advance_amount + v_paid_now;
  v_paid := least(v_paid_raw, v_total);
  v_scale := case when v_paid_raw > 0 then v_paid / v_paid_raw else 1 end;

  v_status := case when v_paid >= v_total then 'paid' when v_paid > 0 then 'partial' else 'unpaid' end;
  select invoice_prefix into v_prefix from public.businesses where id = v_business;
  v_invoice_no := public.next_doc_no(v_business, 'invoice', v_prefix);

  insert into public.invoices
    (business_id, invoice_no, invoice_type, invoice_date, customer_id, customer_name,
     customer_phone, subtotal, discount_amount, tax_amount, round_off, total,
     paid_amount, payment_status, payment_mode, notes, created_by)
  values
    (v_business, v_invoice_no, coalesce((payload ->> 'invoice_type')::public.invoice_type, 'gst'),
     now(), v_job.customer_id, v_job.customer_name, v_job.customer_phone,
     v_subtotal, 0, v_tax, 0, v_total, v_paid, v_status, v_mode,
     'Job card ' || v_job.job_no, auth.uid())
  returning id into v_invoice_id;

  for v_item in select * from public.job_card_items where job_card_id = p_job_id loop
    insert into public.invoice_items
      (business_id, invoice_id, product_id, variant_id, product_name, variant_name,
       hsn_code, serial_no, quantity, unit_name, unit_price, mrp, cost_price,
       discount_amount, gst_rate, tax_amount, line_total)
    values
      (v_business, v_invoice_id, v_item.product_id, v_item.variant_id, v_item.name, '',
       v_item.hsn_code, case when v_item.item_type = 'part' then v_job.serial_no else '' end,
       v_item.quantity, '', v_item.unit_price, 0, v_item.cost_price, 0, v_item.gst_rate,
       v_item.line_total - v_item.quantity * v_item.unit_price, v_item.line_total);
  end loop;

  if v_job.advance_amount > 0 then
    -- 0045: the advance was cash-in when the job card was booked; on the
    -- bill it is an advance being used, not new money.
    insert into public.invoice_payments (business_id, invoice_id, amount, payment_mode, is_advance, note)
    values (v_business, v_invoice_id, round(v_job.advance_amount * v_scale, 2), v_job.advance_mode,
            true, 'Job card advance');
  end if;
  if v_paid_now > 0 then
    insert into public.invoice_payments (business_id, invoice_id, amount, payment_mode)
    values (v_business, v_invoice_id, round(v_paid_now * v_scale, 2), v_mode);
  end if;
  if v_job.customer_id is not null and (v_total - v_paid) > 0 then
    update public.customers set due_amount = due_amount + (v_total - v_paid)
      where id = v_job.customer_id and business_id = v_business;
  end if;

  update public.job_cards set
    invoice_id = v_invoice_id,
    warranty_days = coalesce(v_warranty_days, warranty_days),
    warranty_start = case when coalesce(v_warranty_days, warranty_days) is not null
                       then current_date else warranty_start end,
    warranty_end = case when coalesce(v_warranty_days, warranty_days) is not null
                     then current_date + coalesce(v_warranty_days, warranty_days)
                     else warranty_end end
  where id = p_job_id;

  perform public.log_audit('job_card.closed', 'job_card', p_job_id::text,
    jsonb_build_object('invoice_id', v_invoice_id, 'invoice_no', v_invoice_no, 'total', v_total));

  return jsonb_build_object('invoice_id', v_invoice_id, 'invoice_no', v_invoice_no, 'total', v_total);
end $$;

-- Earlier job-card bills: mark their advance rows the same way.
alter table public.invoice_payments disable trigger user;
update public.invoice_payments ip set is_advance = true, note = 'Job card advance'
  from public.job_cards jc
  where jc.invoice_id = ip.invoice_id and jc.advance_amount > 0 and not ip.is_advance
    and ip.id = (select ip2.id from public.invoice_payments ip2
                 where ip2.invoice_id = jc.invoice_id and ip2.payment_mode = jc.advance_mode
                 order by ip2.created_at, ip2.id limit 1);
alter table public.invoice_payments enable trigger user;

-- ============================================================
-- Grants
-- ============================================================
revoke execute on function public.set_staff_cash_permission(uuid, boolean) from public, anon;
revoke execute on function public.get_cashbook(date) from public, anon;
revoke execute on function public.add_cash_entry(text, numeric, text) from public, anon;
revoke execute on function public.submit_cash_closing(date, numeric, text, jsonb) from public, anon;
revoke execute on function public.review_cash_closing(uuid, text) from public, anon;
revoke execute on function public.reopen_cash_closing(uuid, text) from public, anon;
grant execute on function public.set_staff_cash_permission(uuid, boolean) to authenticated;
grant execute on function public.get_cashbook(date) to authenticated;
grant execute on function public.add_cash_entry(text, numeric, text) to authenticated;
grant execute on function public.submit_cash_closing(date, numeric, text, jsonb) to authenticated;
grant execute on function public.review_cash_closing(uuid, text) to authenticated;
grant execute on function public.reopen_cash_closing(uuid, text) to authenticated;
