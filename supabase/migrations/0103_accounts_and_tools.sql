-- ============================================================
-- 0103 — Accounts, reports and team tools.
--
-- Accounts (payments area, 0098):
--   * GST tax invoices for Dukania's own sales: once Settings has a GSTIN,
--     every payment gets an invoice number per financial year
--     (DK/26-27/0001) and its GST split (CGST+SGST in the same state,
--     IGST otherwise; prices include GST). Older payments: on request;
--   * refunds, with a credit note when the payment had an invoice, and
--     optionally ending the plan;
--   * business expenses (with the GST paid on them) and monthly targets;
--   * admin_finance(): money in and out by month, MRR/ARR, targets;
--   * admin_accounts_export(): sales register, credit notes and expenses
--     for the CA.
-- Team tools (every team member):
--   * tasks, and a calendar of tasks, follow-ups and renewals;
--   * admin_search(): clients, leads, support requests and payments;
--   * admin_alerts(): what came in over the last 7 days, new since last look.
-- ============================================================

create or replace function pg_temp.team_table(p_table text, p_area text) returns void language plpgsql as $$
begin
  execute format('alter table public.%I enable row level security', p_table);
  execute format('drop policy if exists "admin all" on public.%I', p_table);
  execute format('create policy "admin all" on public.%I for all using (public.is_admin()) with check (public.is_admin())', p_table);
  execute format('drop policy if exists "team area" on public.%I', p_table);
  if p_area is not null then
    execute format('create policy "team area" on public.%I as restrictive for all '
                   'using (not public.is_admin() or public.admin_can(%L)) '
                   'with check (not public.is_admin() or public.admin_can(%L))', p_table, p_area, p_area);
  end if;
end $$;

-- ============================================================
-- A. GST settings and document numbers
-- ============================================================
alter table public.platform_settings
  add column if not exists gst_rate numeric(5,2) not null default 18 check (gst_rate between 0 and 28),
  add column if not exists sac_code text not null default '998314',
  add column if not exists invoice_prefix text not null default 'DK'
    check (invoice_prefix ~ '^[A-Z0-9-]{1,8}$');

create table if not exists public.doc_series (
  kind  text not null,
  fy    text not null,
  last  integer not null default 0,
  primary key (kind, fy)
);
alter table public.doc_series enable row level security;  -- functions only

-- "26-27" for a date in the financial year April 2026 – March 2027.
create or replace function public.fy_label(p date)
returns text language sql immutable as $$
  select to_char(case when extract(month from p) >= 4 then p else p - interval '1 year' end, 'YY')
         || '-' || to_char(case when extract(month from p) >= 4 then p + interval '1 year' else p end, 'YY')
$$;

-- DK/26-27/0001 (invoice) or DK-CN/26-27/0001 (credit note).
create or replace function public.next_doc_no(p_kind text, p_date date)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_fy text := public.fy_label(p_date);
  v_n integer;
  v_prefix text := (select invoice_prefix from public.platform_settings where id = 1);
begin
  insert into public.doc_series (kind, fy, last) values (p_kind, v_fy, 1)
  on conflict (kind, fy) do update set last = public.doc_series.last + 1
  returning last into v_n;
  return v_prefix || case when p_kind = 'credit_note' then '-CN' else '' end
         || '/' || v_fy || '/' || lpad(v_n::text, 4, '0');
end $$;
revoke execute on function public.next_doc_no(text, date) from public, anon, authenticated;

-- GST inside an amount that includes it, for a client in [p_state].
create or replace function public.gst_split(p_total numeric, p_state text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  s public.platform_settings := (select x from public.platform_settings x where id = 1);
  v_our text := left(s.business_gstin, 2);
  v_place text := coalesce(nullif(p_state, ''), v_our);
  v_taxable numeric := round(p_total / (1 + s.gst_rate / 100), 2);
  v_tax numeric := p_total - v_taxable;
  v_cgst numeric := case when v_place = v_our then round(v_tax / 2, 2) else 0 end;
begin
  return jsonb_build_object(
    'rate', s.gst_rate, 'sac', s.sac_code, 'place_of_supply', v_place, 'seller_state', v_our,
    'taxable', v_taxable,
    'cgst', v_cgst,
    'sgst', case when v_place = v_our then v_tax - v_cgst else 0 end,
    'igst', case when v_place = v_our then 0 else v_tax end,
    'total', p_total);
end $$;

-- ============================================================
-- B. Tax invoices on payments
-- ============================================================
alter table public.subscription_payments
  add column if not exists invoice_no text,
  add column if not exists invoice_date date,
  add column if not exists tax jsonb not null default '{}'::jsonb;
create unique index if not exists idx_subscription_payments_invoice on public.subscription_payments(invoice_no);

-- Fill in the invoice on a payment row (no GSTIN in Settings = none).
create or replace function public.fill_invoice(p public.subscription_payments)
returns public.subscription_payments language plpgsql security definer set search_path = public as $$
declare v_b public.businesses;
begin
  if p.invoice_no is not null or p.amount <= 0
     or coalesce((select business_gstin from public.platform_settings where id = 1), '') = '' then
    return p;
  end if;
  select * into v_b from public.businesses where id = p.business_id;
  p.invoice_no := public.next_doc_no('invoice', p.payment_date);
  p.invoice_date := p.payment_date;
  p.tax := public.gst_split(p.amount, coalesce(nullif(v_b.state_code, ''), left(v_b.gst_number, 2)))
           || jsonb_build_object('client_gstin', v_b.gst_number, 'client_name', v_b.name);
  return p;
end $$;
revoke execute on function public.fill_invoice(public.subscription_payments) from public, anon, authenticated;

create or replace function public.payment_invoice()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new := public.fill_invoice(new);
  return new;
end $$;
drop trigger if exists trg_payment_invoice on public.subscription_payments;
create trigger trg_payment_invoice before insert on public.subscription_payments
  for each row execute function public.payment_invoice();

-- An invoice for a payment from before (or recorded before the GSTIN was set).
create or replace function public.admin_issue_invoice(p_payment uuid)
returns text language plpgsql security definer set search_path = public as $$
declare v public.subscription_payments;
begin
  perform public.assert_admin_area('payments');
  if coalesce((select business_gstin from public.platform_settings where id = 1), '') = '' then
    raise exception 'Add Dukania''s GSTIN in Settings first';
  end if;
  select * into v from public.subscription_payments where id = p_payment for update;
  if v.id is null then raise exception 'Payment not found'; end if;
  if v.invoice_no is not null then return v.invoice_no; end if;
  v := public.fill_invoice(v);
  update public.subscription_payments set invoice_no = v.invoice_no, invoice_date = v.invoice_date, tax = v.tax
   where id = p_payment;
  perform public.admin_log(v.business_id, 'invoice.issued', 'subscription_payment', p_payment::text,
    jsonb_build_object('invoice_no', v.invoice_no));
  return v.invoice_no;
end $$;

create or replace function public.admin_save_gst_settings(p jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_admin_area('settings');
  update public.platform_settings
     set gst_rate = coalesce((p ->> 'gst_rate')::numeric, gst_rate),
         sac_code = coalesce(nullif(btrim(p ->> 'sac_code'), ''), sac_code),
         invoice_prefix = coalesce(nullif(upper(btrim(p ->> 'invoice_prefix')), ''), invoice_prefix)
   where id = 1;
  perform public.admin_log(null, 'settings.gst', 'platform_settings', '1', p);
end $$;

-- ============================================================
-- C. Refunds (credit notes)
-- ============================================================
create table if not exists public.subscription_refunds (
  id              uuid primary key default gen_random_uuid(),
  payment_id      uuid not null references public.subscription_payments(id) on delete cascade,
  business_id     uuid not null references public.businesses(id) on delete cascade,
  amount          numeric(12,2) not null check (amount > 0),
  refund_date     date not null,
  mode            public.payment_mode not null default 'upi',
  reference       text not null default '',
  reason          text not null default '',
  credit_note_no  text unique,
  tax             jsonb not null default '{}'::jsonb,
  ended_plan      boolean not null default false,
  created_by      uuid references public.profiles(id) on delete set null,
  created_at      timestamptz not null default now()
);
select pg_temp.team_table('subscription_refunds', 'payments');

create or replace function public.admin_record_refund(p_payment uuid, p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_pay public.subscription_payments;
  v_amount numeric := (p ->> 'amount')::numeric;
  v_date date := coalesce(nullif(p ->> 'refund_date', '')::date, public.ist_date(now()));
  v_left numeric;
  v_cn text;
  v_tax jsonb := '{}'::jsonb;
  v_id uuid;
begin
  perform public.assert_admin_area('payments');
  select * into v_pay from public.subscription_payments where id = p_payment for update;
  if v_pay.id is null then raise exception 'Payment not found'; end if;
  v_left := v_pay.amount - coalesce((select sum(amount) from public.subscription_refunds where payment_id = p_payment), 0);
  if v_amount is null or v_amount <= 0 then raise exception 'Enter the amount refunded'; end if;
  if v_amount > v_left then raise exception 'Only % of this payment is left to refund', v_left; end if;
  if btrim(coalesce(p ->> 'reason', '')) = '' then raise exception 'Say why it was refunded'; end if;
  if v_pay.invoice_no is not null then
    v_cn := public.next_doc_no('credit_note', v_date);
    v_tax := public.gst_split(v_amount, v_pay.tax ->> 'place_of_supply')
             || jsonb_build_object('invoice_no', v_pay.invoice_no, 'client_gstin', v_pay.tax ->> 'client_gstin',
                                   'client_name', v_pay.tax ->> 'client_name');
  end if;
  insert into public.subscription_refunds (payment_id, business_id, amount, refund_date, mode, reference, reason,
                                           credit_note_no, tax, ended_plan, created_by)
  values (p_payment, v_pay.business_id, v_amount, v_date,
          coalesce(nullif(p ->> 'mode', ''), 'upi')::public.payment_mode, btrim(coalesce(p ->> 'reference', '')),
          btrim(p ->> 'reason'), v_cn, v_tax, coalesce((p ->> 'end_plan')::boolean, false), auth.uid())
  returning id into v_id;
  if coalesce((p ->> 'end_plan')::boolean, false) then
    update public.subscriptions set expiry_date = v_date, status = 'expired'
     where id = (select id from public.subscriptions where business_id = v_pay.business_id order by created_at desc limit 1);
  end if;
  perform public.admin_log(v_pay.business_id, 'payment.refunded', 'subscription_payment', p_payment::text,
    jsonb_build_object('amount', v_amount, 'credit_note', v_cn, 'end_plan', p ->> 'end_plan'));
  return jsonb_build_object('id', v_id, 'credit_note_no', v_cn);
end $$;

-- ============================================================
-- D. Expenses and targets
-- ============================================================
create table if not exists public.business_expenses (
  id          uuid primary key default gen_random_uuid(),
  spent_on    date not null default current_date,
  category    text not null check (category in ('ads', 'salaries', 'software', 'office', 'travel', 'commission', 'taxes', 'other')),
  amount      numeric(12,2) not null check (amount > 0),
  gst_paid    numeric(12,2) not null default 0 check (gst_paid >= 0),
  vendor      text not null default '',
  note        text not null default '',
  created_by  uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now()
);
create index if not exists idx_business_expenses_date on public.business_expenses(spent_on);
select pg_temp.team_table('business_expenses', 'payments');

create table if not exists public.monthly_targets (
  month      date primary key check (extract(day from month) = 1),
  revenue    numeric(12,2) not null default 0 check (revenue >= 0),
  new_shops  integer not null default 0 check (new_shops >= 0),
  note       text not null default ''
);
select pg_temp.team_table('monthly_targets', 'payments');

-- ============================================================
-- E. Money by month, MRR and ARR
-- ============================================================

-- Recurring income on a day: each paid period running that day (not
-- lifetime), less refunds, spread over its months.
create or replace function public.mrr_on(p_day date)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(round(sum(
           (sp.amount - coalesce((select sum(r.amount) from public.subscription_refunds r where r.payment_id = sp.id), 0))
           / greatest(1, round((sp.period_end - sp.period_start) / 30.4375))), 0), 0)
  from public.subscription_payments sp
  where sp.amount > 0 and sp.period_start <= p_day and sp.period_end >= p_day and sp.period_end < date '2090-01-01'
$$;
revoke execute on function public.mrr_on(date) from public, anon, authenticated;

create or replace function public.admin_finance(p_months integer default 12)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_today date := public.ist_date(now());
  v_first date := (date_trunc('month', v_today) - make_interval(months => greatest(1, least(p_months, 36)) - 1))::date;
begin
  perform public.assert_admin_area('payments');
  return jsonb_build_object(
    'mrr', public.mrr_on(v_today),
    'paying_shops', (select count(distinct business_id) from public.subscription_payments
                     where amount > 0 and period_start <= v_today and period_end >= v_today and period_end < date '2090-01-01'),
    'lifetime_shops', (select count(distinct business_id) from public.subscription_payments where period_end >= date '2090-01-01'),
    'months', (select jsonb_agg(m order by m.month) from (
      select to_char(g.month, 'YYYY-MM-DD') as month,
        coalesce((select sum(amount) from public.subscription_payments
                  where payment_date >= g.month and payment_date < g.month + interval '1 month'), 0) as money_in,
        coalesce((select sum(amount) from public.subscription_refunds
                  where refund_date >= g.month and refund_date < g.month + interval '1 month'), 0) as refunds,
        coalesce((select sum(amount) from public.business_expenses
                  where spent_on >= g.month and spent_on < g.month + interval '1 month'), 0)
        + coalesce((select sum(amount) from public.campaign_costs
                    where spent_on >= g.month and spent_on < g.month + interval '1 month'), 0) as money_out,
        (select count(*) from (select business_id, min(payment_date) first_paid from public.subscription_payments
                               where amount > 0 group by business_id) f
          where f.first_paid >= g.month and f.first_paid < g.month + interval '1 month') as new_shops,
        public.mrr_on(least((g.month + interval '1 month' - interval '1 day')::date, v_today)) as mrr,
        t.revenue as target_revenue, t.new_shops as target_new_shops
      from generate_series(v_first, date_trunc('month', v_today)::date, interval '1 month') as g(month)
      left join public.monthly_targets t on t.month = g.month::date) m),
    'expense_categories', coalesce((select jsonb_object_agg(category, total) from (
        select category, sum(amount) total from public.business_expenses
        where spent_on >= v_first group by category) x), '{}'::jsonb));
end $$;

create or replace function public.admin_set_target(p_month date, p_revenue numeric, p_new_shops integer, p_note text default '')
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_admin_area('payments');
  insert into public.monthly_targets (month, revenue, new_shops, note)
  values (date_trunc('month', p_month)::date, coalesce(p_revenue, 0), coalesce(p_new_shops, 0), coalesce(p_note, ''))
  on conflict (month) do update set revenue = excluded.revenue, new_shops = excluded.new_shops, note = excluded.note;
end $$;

-- ============================================================
-- F. For the CA: sales register, credit notes, expenses
-- ============================================================
create or replace function public.admin_accounts_export(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.assert_admin_area('payments');
  return jsonb_build_object(
    'sales', coalesce((select jsonb_agg(x order by x.date, x.receipt_no) from (
      select sp.payment_date as date, sp.invoice_no, sp.receipt_no, b.name as client, b.gst_number as client_gstin,
             coalesce(sp.tax ->> 'place_of_supply', b.state_code) as place_of_supply,
             (sp.tax ->> 'taxable')::numeric as taxable, (sp.tax ->> 'cgst')::numeric as cgst,
             (sp.tax ->> 'sgst')::numeric as sgst, (sp.tax ->> 'igst')::numeric as igst,
             sp.amount as total, sp.payment_mode::text as mode, sp.reference, p.name as plan
      from public.subscription_payments sp
      join public.businesses b on b.id = sp.business_id
      left join public.plans p on p.id = sp.plan_id
      where sp.amount > 0 and sp.payment_date between p_from and p_to) x), '[]'::jsonb),
    'credit_notes', coalesce((select jsonb_agg(x order by x.date) from (
      select r.refund_date as date, r.credit_note_no, r.tax ->> 'invoice_no' as invoice_no, b.name as client,
             b.gst_number as client_gstin, (r.tax ->> 'taxable')::numeric as taxable,
             (r.tax ->> 'cgst')::numeric as cgst, (r.tax ->> 'sgst')::numeric as sgst,
             (r.tax ->> 'igst')::numeric as igst, r.amount as total, r.mode::text as mode, r.reference, r.reason
      from public.subscription_refunds r join public.businesses b on b.id = r.business_id
      where r.refund_date between p_from and p_to) x), '[]'::jsonb),
    'expenses', coalesce((select jsonb_agg(x order by x.date) from (
      select e.spent_on as date, e.category, e.vendor, e.amount, e.gst_paid, e.note
      from public.business_expenses e where e.spent_on between p_from and p_to
      union all
      select c.spent_on, 'ads', c.channel || ' — ' || c.campaign, c.amount, 0, c.note
      from public.campaign_costs c where c.spent_on between p_from and p_to) x), '[]'::jsonb));
end $$;

-- ============================================================
-- G. Tasks and the calendar
-- ============================================================
create table if not exists public.admin_tasks (
  id           uuid primary key default gen_random_uuid(),
  title        text not null check (btrim(title) <> ''),
  notes        text not null default '',
  due_date     date,
  assigned_to  uuid references public.profiles(id) on delete set null,
  business_id  uuid references public.businesses(id) on delete cascade,
  lead_id      uuid references public.leads(id) on delete cascade,
  done         boolean not null default false,
  done_at      timestamptz,
  created_by   uuid references public.profiles(id) on delete set null,
  created_at   timestamptz not null default now()
);
create index if not exists idx_admin_tasks_open on public.admin_tasks(due_date) where not done;
select pg_temp.team_table('admin_tasks', null);

create or replace function public.admin_tasks_defaults()
returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    new.created_by := coalesce(new.created_by, auth.uid());
    new.assigned_to := coalesce(new.assigned_to, auth.uid());
  end if;
  new.done_at := case when new.done then coalesce(new.done_at, now()) end;
  return new;
end $$;
drop trigger if exists trg_admin_tasks_defaults on public.admin_tasks;
create trigger trg_admin_tasks_defaults before insert or update on public.admin_tasks
  for each row execute function public.admin_tasks_defaults();

-- What falls on each day: tasks, lead and client follow-ups, renewals.
create or replace function public.admin_calendar(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admin only' using errcode = '42501'; end if;
  if p_to - p_from > 62 then raise exception 'Up to two months at a time'; end if;
  return coalesce((select jsonb_agg(e order by e.date, e.kind) from (
    select t.due_date as date, 'task' as kind, t.title, '/tasks' as href, t.done, t.assigned_to as who
      from public.admin_tasks t where t.due_date between p_from and p_to
    union all
    select l.follow_up_date, 'lead', 'Follow up: ' || l.shop_name, '/leads/' || l.id, false, l.assigned_to
      from public.leads l
      where public.admin_can('leads') and l.follow_up_date between p_from and p_to
        and l.status in ('new', 'contacted', 'demo', 'trial', 'negotiation')
    union all
    select c.follow_up_date, 'call', 'Call: ' || b.name, '/clients/' || b.id, c.follow_up_done, c.created_by
      from public.client_contacts c join public.businesses b on b.id = c.business_id
      where c.follow_up_date between p_from and p_to
    union all
    select ls.expiry_date, 'renewal', case when ls.status = 'trial' then 'Trial ends: ' else 'Renewal: ' end || b.name,
           '/clients/' || b.id, false, null::uuid
      from public.latest_subscriptions ls join public.businesses b on b.id = ls.business_id
      where b.is_active and ls.status in ('active', 'trial') and ls.expiry_date between p_from and p_to
  ) e), '[]'::jsonb);
end $$;

-- ============================================================
-- H. Search everywhere
-- ============================================================
create or replace function public.admin_search(p_q text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_q text := btrim(coalesce(p_q, ''));
  v_like text := '%' || replace(replace(btrim(coalesce(p_q, '')), '%', ''), '_', '') || '%';
  v_key text := public.phone_key(p_q);
begin
  if not public.is_admin() then raise exception 'Admin only' using errcode = '42501'; end if;
  if char_length(v_q) < 2 then return '{}'::jsonb; end if;
  return jsonb_build_object(
    'clients', coalesce((select jsonb_agg(x) from (
        select b.id, b.name, b.owner_name, b.phone from public.businesses b
        where b.name ilike v_like or b.owner_name ilike v_like or b.email ilike v_like or b.gst_number ilike v_like
           or b.referral_code ilike v_like or (length(v_key) >= 6 and public.phone_key(b.phone) like '%' || v_key || '%')
        order by b.name limit 8) x), '[]'::jsonb),
    'leads', case when public.admin_can('leads') then coalesce((select jsonb_agg(x) from (
        select l.id, l.shop_name, l.contact_name, l.status from public.leads l
        where l.shop_name ilike v_like or l.contact_name ilike v_like or l.city ilike v_like
           or (length(v_key) >= 6 and l.phone_key like '%' || v_key || '%')
        order by l.created_at desc limit 8) x), '[]'::jsonb) else '[]'::jsonb end,
    'tickets', case when public.admin_can('support') then coalesce((select jsonb_agg(x) from (
        select t.id, t.subject, b.name, t.status from public.support_tickets t join public.businesses b on b.id = t.business_id
        where t.subject ilike v_like or t.message ilike v_like
        order by t.created_at desc limit 8) x), '[]'::jsonb) else '[]'::jsonb end,
    'payments', case when public.admin_can('payments') then coalesce((select jsonb_agg(x) from (
        select sp.id, sp.receipt_no, sp.invoice_no, sp.amount, sp.payment_date, b.name
        from public.subscription_payments sp join public.businesses b on b.id = sp.business_id
        where sp.receipt_no ilike v_like or sp.invoice_no ilike v_like or sp.reference ilike v_like
        order by sp.payment_date desc limit 8) x), '[]'::jsonb) else '[]'::jsonb end);
end $$;

-- ============================================================
-- I. Alerts: the last 7 days, and what's new since the person last looked
-- ============================================================
alter table public.admin_team add column if not exists alerts_seen_at timestamptz;

create or replace function public.admin_alerts()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_seen timestamptz := coalesce((select alerts_seen_at from public.admin_team where user_id = auth.uid()), now() - interval '1 day');
  v_since timestamptz := now() - interval '7 days';
begin
  if not public.is_admin() then raise exception 'Admin only' using errcode = '42501'; end if;
  return jsonb_build_object('seen_at', v_seen, 'items', coalesce((select jsonb_agg(a order by a.at desc) from (
    select b.created_at as at, 'signup' as kind, 'New shop: ' || b.name as title, '/clients/' || b.id as href
      from public.businesses b where b.created_at > v_since
    union all
    select l.created_at, 'lead', 'New lead: ' || l.shop_name || ' (' || l.source || ')', '/leads/' || l.id
      from public.leads l where public.admin_can('leads') and l.created_at > v_since and l.source <> 'app_signup'
    union all
    select coalesce(t.last_shop_message_at, t.created_at),
           case when t.kind = 'complaint' then 'complaint' else 'ticket' end,
           case when t.kind = 'complaint' then 'Complaint: ' else 'Support: ' end || b.name || ' — ' || t.subject, '/support'
      from public.support_tickets t join public.businesses b on b.id = t.business_id
      where public.admin_can('support') and public.ticket_needs_reply(t)
        and coalesce(t.last_shop_message_at, t.created_at) > v_since
    union all
    select c.created_at, 'payment', 'Payment to verify: ' || b.name || ' ₹' || c.amount, '/'
      from public.renewal_claims c join public.businesses b on b.id = c.business_id
      where public.admin_can('payments') and c.status = 'pending' and c.created_at > v_since
    union all
    select r.created_at, 'unhappy', 'Would not recommend (' || r.score || '/10): ' || b.name, '/success'
      from public.nps_responses r join public.businesses b on b.id = r.business_id
      where r.score <= 6 and r.created_at > v_since
    union all
    select t.created_at, 'task', 'Task for you: ' || t.title, '/tasks'
      from public.admin_tasks t
      where t.assigned_to = auth.uid() and t.created_by is distinct from auth.uid() and not t.done and t.created_at > v_since
  ) a), '[]'::jsonb));
end $$;

create or replace function public.admin_mark_alerts_seen()
returns void language sql security definer set search_path = public as $$
  update public.admin_team set alerts_seen_at = now() where user_id = auth.uid() and public.is_admin();
$$;

-- ============================================================
-- Grants
-- ============================================================
revoke execute on function public.gst_split(numeric, text) from public, anon;
revoke execute on function public.admin_issue_invoice(uuid) from public, anon;
revoke execute on function public.admin_save_gst_settings(jsonb) from public, anon;
revoke execute on function public.admin_record_refund(uuid, jsonb) from public, anon;
revoke execute on function public.admin_finance(integer) from public, anon;
revoke execute on function public.admin_set_target(date, numeric, integer, text) from public, anon;
revoke execute on function public.admin_accounts_export(date, date) from public, anon;
revoke execute on function public.admin_calendar(date, date) from public, anon;
revoke execute on function public.admin_search(text) from public, anon;
revoke execute on function public.admin_alerts() from public, anon;
revoke execute on function public.admin_mark_alerts_seen() from public, anon;
grant execute on function public.gst_split(numeric, text) to authenticated;
grant execute on function public.admin_issue_invoice(uuid) to authenticated;
grant execute on function public.admin_save_gst_settings(jsonb) to authenticated;
grant execute on function public.admin_record_refund(uuid, jsonb) to authenticated;
grant execute on function public.admin_finance(integer) to authenticated;
grant execute on function public.admin_set_target(date, numeric, integer, text) to authenticated;
grant execute on function public.admin_accounts_export(date, date) to authenticated;
grant execute on function public.admin_calendar(date, date) to authenticated;
grant execute on function public.admin_search(text) to authenticated;
grant execute on function public.admin_alerts() to authenticated;
grant execute on function public.admin_mark_alerts_seen() to authenticated;
