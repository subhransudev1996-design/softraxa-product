-- ============================================================
-- 0041_customer_advances.sql — release R1, batch 2
-- (LAUNCH_SPECIFICATION.md D26, PD21–PD23, PD28)
--
--   A. Customer advance balance with its own ledger. Money a customer has
--      paid beyond their bills is an advance, never a negative due.
--   B. Receipts and allocations: a payment is split across bills (oldest
--      first, or bills the shop picks); the rest becomes an advance.
--      A preview shows the split before saving.
--   C. Using an advance on a bill (never automatic, PD22), refunding an
--      advance, and reversing a receipt (owner only, with a reason, PD23)
--   D. Every path that used to push a due below zero now feeds the
--      advance: returns (D27), cancelling a paid bill, editing a bill
--      below what was paid
--   E. Backfill: existing negative dues and overpaid bills become advances
--
-- Run AFTER 0040.
-- ============================================================

-- ============================================================
-- A. Advance balance and ledger
-- ============================================================
alter table public.customers add column if not exists advance_amount numeric(14,2) not null default 0;

create table if not exists public.customer_advance_entries (
  id             uuid primary key default gen_random_uuid(),
  business_id    uuid not null references public.businesses(id) on delete cascade,
  customer_id    uuid not null references public.customers(id) on delete cascade,
  amount         numeric(14,2) not null check (amount <> 0),  -- + adds to the advance, − uses it
  kind           text not null check (kind in (
                   'opening', 'payment_excess', 'return_credit', 'cancelled_bill',
                   'overpaid_bill', 'applied', 'refund', 'reversal')),
  payment_mode   public.payment_mode,                          -- refunds: how the money went out
  payment_id     uuid references public.customer_payments(id) on delete set null,
  invoice_id     uuid references public.invoices(id) on delete set null,
  sale_return_id uuid references public.sale_returns(id) on delete set null,
  note           text not null default '',
  created_by     uuid references public.profiles(id),
  created_at     timestamptz not null default now()
);
create index if not exists idx_customer_advance_entries_customer
  on public.customer_advance_entries (customer_id, created_at desc);

-- ============================================================
-- B. Receipts and allocations
-- ============================================================
create table if not exists public.customer_payment_allocations (
  id          uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  payment_id  uuid not null references public.customer_payments(id) on delete cascade,
  invoice_id  uuid not null references public.invoices(id) on delete cascade,
  amount      numeric(14,2) not null check (amount > 0),
  created_at  timestamptz not null default now()
);
create index if not exists idx_customer_payment_allocations_payment
  on public.customer_payment_allocations (payment_id);
create index if not exists idx_customer_payment_allocations_invoice
  on public.customer_payment_allocations (invoice_id);

-- tracked = recorded with allocations (0041+); only those can be reversed.
alter table public.customer_payments add column if not exists unapplied_amount numeric(14,2) not null default 0;
alter table public.customer_payments add column if not exists tracked boolean not null default false;
alter table public.customer_payments add column if not exists reversed_at timestamptz;
alter table public.customer_payments add column if not exists reversal_reason text not null default '';
alter table public.customer_payments add column if not exists reversed_by uuid references public.profiles(id);

-- Bill payment rows: which receipt they came from; advance use is not a
-- new cash receipt; reversed rows stay for history.
alter table public.invoice_payments add column if not exists customer_payment_id uuid
  references public.customer_payments(id) on delete set null;
alter table public.invoice_payments add column if not exists is_advance boolean not null default false;
alter table public.invoice_payments add column if not exists reversed boolean not null default false;

-- ---------- security: read for shop members, writes only via RPCs ----------
do $$
declare t text;
begin
  foreach t in array array['customer_advance_entries', 'customer_payment_allocations'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "tenant read" on public.%I', t);
    execute format('drop policy if exists "admin all" on public.%I', t);
    execute format('create policy "tenant read" on public.%I for select
      using (business_id = (select public.current_business_id()))', t);
    execute format('create policy "admin all" on public.%I for all
      using (public.is_admin()) with check (public.is_admin())', t);
  end loop;
end $$;

drop trigger if exists trg_00_tenant_refs on public.customer_advance_entries;
create trigger trg_00_tenant_refs before insert or update on public.customer_advance_entries
  for each row execute function public.enforce_tenant_refs(
    'customer_id=customers', 'payment_id=customer_payments', 'invoice_id=invoices',
    'sale_return_id=sale_returns');
drop trigger if exists trg_00_tenant_refs on public.customer_payment_allocations;
create trigger trg_00_tenant_refs before insert or update on public.customer_payment_allocations
  for each row execute function public.enforce_tenant_refs(
    'payment_id=customer_payments', 'invoice_id=invoices');

-- Balances (due and advance) change only through documents, payments and
-- the advance functions. Replaces 0037's version.
create or replace function public.guard_party_columns()
returns trigger language plpgsql as $$
begin
  if public.is_direct_api_write() then
    if tg_op = 'INSERT' then
      new.due_amount := 0;
      if tg_table_name = 'customers' then new.advance_amount := 0; end if;
    elsif new.due_amount is distinct from old.due_amount then
      raise exception 'Balances can only change through bills, purchases and payments'
        using errcode = '42501';
    elsif tg_table_name = 'customers' and new.advance_amount is distinct from old.advance_amount then
      raise exception 'Advances can only change through payments, returns and refunds'
        using errcode = '42501';
    end if;
  end if;

  if tg_table_name = 'customers' and auth.uid() is not null
     and not public.has_permission('owner') then
    if tg_op = 'INSERT' then
      new.credit_unlimited := false;
      new.credit_limit := null;          -- store default, via normalize_customer_credit
    elsif new.credit_limit is distinct from old.credit_limit
       or new.credit_unlimited is distinct from old.credit_unlimited then
      raise exception 'Only the owner can change credit limits' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;

-- ---------- advance ledger writer (internal) ----------
-- Adds (+) or uses (−) advance and records why. Refuses to go below zero.
create or replace function public.post_customer_advance(
  p_business       uuid,
  p_customer       uuid,
  p_amount         numeric,
  p_kind           text,
  p_payment_id     uuid default null,
  p_invoice_id     uuid default null,
  p_sale_return_id uuid default null,
  p_mode           public.payment_mode default null,
  p_note           text default ''
) returns numeric language plpgsql security definer set search_path = public as $$
declare
  v_balance numeric(14,2);
begin
  select advance_amount into v_balance from public.customers
    where id = p_customer and business_id = p_business for update;
  if not found then raise exception 'Customer not found'; end if;
  if coalesce(p_amount, 0) = 0 then return v_balance; end if;
  if v_balance + p_amount < -0.005 then
    raise exception 'The customer''s advance is only ₹% — not enough for ₹%', v_balance, -p_amount;
  end if;

  update public.customers set advance_amount = advance_amount + p_amount
    where id = p_customer and business_id = p_business
    returning advance_amount into v_balance;

  insert into public.customer_advance_entries
    (business_id, customer_id, amount, kind, payment_mode, payment_id, invoice_id,
     sale_return_id, note, created_by)
  values
    (p_business, p_customer, p_amount, p_kind, p_mode, p_payment_id, p_invoice_id,
     p_sale_return_id, coalesce(p_note, ''), auth.uid());
  return v_balance;
end $$;

-- ---------- allocation plan (internal, shared by preview and record) ----------
-- Oldest bill first — invoice date, then number (PD21) — or the bills in
-- the order given. Only this customer's open bills; each at most its due.
create or replace function public.plan_customer_payment(
  p_business uuid, p_customer uuid, p_amount numeric, p_invoice_ids uuid[] default null)
returns table (invoice_id uuid, invoice_no text, invoice_date timestamptz, due numeric, apply numeric)
language plpgsql stable security definer set search_path = public as $$
declare
  r      record;
  v_left numeric := p_amount;
begin
  if p_invoice_ids is not null and cardinality(p_invoice_ids) > 0 then
    if cardinality(p_invoice_ids) <> (select count(distinct x) from unnest(p_invoice_ids) x) then
      raise exception 'The same bill was chosen twice';
    end if;
    if exists (
      select 1 from unnest(p_invoice_ids) x(id)
      where not exists (
        select 1 from public.invoices i
        where i.id = x.id and i.business_id = p_business and i.customer_id = p_customer
          and not i.is_cancelled and i.invoice_type <> 'estimate' and i.due_amount > 0)) then
      raise exception 'Choose only open bills of this customer';
    end if;
    for r in
      select i.id, i.invoice_no, i.invoice_date, i.due_amount
      from unnest(p_invoice_ids) with ordinality x(id, ord)
      join public.invoices i on i.id = x.id
      order by x.ord
    loop
      exit when v_left <= 0;
      invoice_id := r.id; invoice_no := r.invoice_no; invoice_date := r.invoice_date;
      due := r.due_amount; apply := least(v_left, r.due_amount);
      v_left := v_left - apply;
      return next;
    end loop;
  else
    for r in
      select i.id, i.invoice_no, i.invoice_date, i.due_amount
      from public.invoices i
      where i.business_id = p_business and i.customer_id = p_customer
        and not i.is_cancelled and i.invoice_type <> 'estimate' and i.due_amount > 0
      order by i.invoice_date, i.invoice_no
    loop
      exit when v_left <= 0;
      invoice_id := r.id; invoice_no := r.invoice_no; invoice_date := r.invoice_date;
      due := r.due_amount; apply := least(v_left, r.due_amount);
      v_left := v_left - apply;
      return next;
    end loop;
  end if;
end $$;

-- What a payment would do, before saving it.
create or replace function public.preview_customer_payment(
  p_customer_id uuid, p_amount numeric, p_invoice_ids uuid[] default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_plan     jsonb;
  v_applied  numeric;
begin
  if not public.has_permission('can_record_payments') then
    raise exception 'You don''t have permission to %', public.permission_label('can_record_payments')
      using errcode = '42501';
  end if;
  if not exists (select 1 from public.customers where id = p_customer_id and business_id = v_business) then
    raise exception 'Customer not found';
  end if;
  select coalesce(jsonb_agg(row_to_json(p)), '[]'::jsonb), coalesce(sum(p.apply), 0)
    into v_plan, v_applied
    from public.plan_customer_payment(v_business, p_customer_id, greatest(coalesce(p_amount, 0), 0), p_invoice_ids) p;
  return jsonb_build_object(
    'allocations', v_plan,
    'applied', v_applied,
    'advance', greatest(coalesce(p_amount, 0), 0) - v_applied);
end $$;

-- Record a receipt. p_invoice_id: pay exactly that bill (amount ≤ its due).
-- p_invoice_ids: the bills to settle, in order. Neither: oldest first.
-- Whatever is not allocated becomes the customer's advance.
drop function if exists public.record_customer_payment(uuid, numeric, public.payment_mode, date, text, uuid);
create or replace function public.record_customer_payment(
  p_customer_id uuid,
  p_amount      numeric,
  p_mode        public.payment_mode default 'cash',
  p_date        date default current_date,
  p_note        text default '',
  p_invoice_id  uuid default null,
  p_invoice_ids uuid[] default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_business  uuid := public.current_business_id();
  v_id        uuid;
  v_inv       record;
  v_ids       uuid[] := p_invoice_ids;
  v_alloc     numeric(14,2) := 0;
  v_unapplied numeric(14,2);
  r           record;
begin
  if p_amount is null or p_amount <= 0 then raise exception 'Amount must be positive'; end if;
  if p_mode = 'credit' then raise exception 'Choose how the money was received (cash, UPI, card…)'; end if;

  -- Lock the customer and their open bills: concurrent receipts run one
  -- after another and see each other's allocations.
  perform 1 from public.customers where id = p_customer_id and business_id = v_business for update;
  if not found then raise exception 'Customer not found'; end if;
  perform 1 from public.invoices
    where business_id = v_business and customer_id = p_customer_id and not is_cancelled
    for update;

  if p_invoice_id is not null then
    select * into v_inv from public.invoices where id = p_invoice_id and business_id = v_business;
    if v_inv.id is null or v_inv.customer_id is distinct from p_customer_id then
      raise exception 'This bill does not belong to the selected customer';
    end if;
    if v_inv.is_cancelled then raise exception 'This bill is cancelled'; end if;
    if v_inv.invoice_type = 'estimate' then raise exception 'Estimates can''t be paid'; end if;
    if p_amount > v_inv.due_amount + 0.005 then
      raise exception 'Amount is more than the bill''s due (%)', v_inv.due_amount;
    end if;
    v_ids := array[p_invoice_id];
  end if;

  insert into public.customer_payments
    (business_id, customer_id, invoice_id, amount, payment_mode, payment_date, note, created_by, tracked)
  values (v_business, p_customer_id, p_invoice_id, p_amount, p_mode, p_date, coalesce(p_note, ''),
          auth.uid(), true)
  returning id into v_id;

  for r in select * from public.plan_customer_payment(v_business, p_customer_id, p_amount, v_ids) loop
    insert into public.customer_payment_allocations (business_id, payment_id, invoice_id, amount)
    values (v_business, v_id, r.invoice_id, r.apply);
    update public.invoices set
      paid_amount = paid_amount + r.apply,
      payment_status = public.doc_payment_status(total, paid_amount + r.apply, credit_amount)
      where id = r.invoice_id;
    insert into public.invoice_payments
      (business_id, invoice_id, amount, payment_mode, note, customer_payment_id)
    values (v_business, r.invoice_id, r.apply, p_mode, coalesce(p_note, ''), v_id);
    v_alloc := v_alloc + r.apply;
  end loop;

  if v_alloc > 0 then
    update public.customers set due_amount = due_amount - v_alloc
      where id = p_customer_id and business_id = v_business;
  end if;

  v_unapplied := p_amount - v_alloc;
  update public.customer_payments set unapplied_amount = v_unapplied where id = v_id;
  if v_unapplied > 0 then
    perform public.post_customer_advance(v_business, p_customer_id, v_unapplied, 'payment_excess',
      p_payment_id => v_id, p_note => 'Paid beyond open bills');
  end if;

  perform public.log_audit('payment.received', 'customer', p_customer_id::text,
    jsonb_build_object('payment_id', v_id, 'amount', p_amount, 'allocated', v_alloc,
                       'advance', v_unapplied, 'invoice_ids', to_jsonb(v_ids)));
  return v_id;
end $$;

-- ============================================================
-- C. Using, refunding and reversing
-- ============================================================

-- Use the customer's advance on one bill (PD22: only when the shop asks).
-- p_amount null = as much as possible. Not a new cash receipt.
create or replace function public.apply_customer_advance(p_invoice_id uuid, p_amount numeric default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_inv      record;
  v_advance  numeric(14,2);
  v_apply    numeric(14,2);
  v_left     numeric(14,2);
begin
  select * into v_inv from public.invoices
    where id = p_invoice_id and business_id = v_business for update;
  if v_inv.id is null then raise exception 'Invoice not found'; end if;
  if v_inv.customer_id is null then raise exception 'This bill has no customer'; end if;
  if v_inv.is_cancelled then raise exception 'This bill is cancelled'; end if;
  if v_inv.invoice_type = 'estimate' then raise exception 'Estimates can''t be paid'; end if;
  if v_inv.due_amount <= 0 then raise exception 'This bill has nothing due'; end if;

  select advance_amount into v_advance from public.customers
    where id = v_inv.customer_id and business_id = v_business for update;
  if coalesce(v_advance, 0) <= 0 then raise exception 'This customer has no advance'; end if;
  if p_amount is not null and p_amount <= 0 then raise exception 'Amount must be positive'; end if;
  if p_amount is not null and p_amount > v_advance + 0.005 then
    raise exception 'The customer''s advance is only ₹%', v_advance;
  end if;
  v_apply := least(coalesce(p_amount, v_advance), v_advance, v_inv.due_amount);

  update public.invoices set
    paid_amount = paid_amount + v_apply,
    payment_status = public.doc_payment_status(total, paid_amount + v_apply, credit_amount)
    where id = p_invoice_id;
  insert into public.invoice_payments (business_id, invoice_id, amount, payment_mode, note, is_advance)
  values (v_business, p_invoice_id, v_apply, 'other', 'Advance applied', true);
  update public.customers set due_amount = due_amount - v_apply
    where id = v_inv.customer_id and business_id = v_business;
  v_left := public.post_customer_advance(v_business, v_inv.customer_id, -v_apply, 'applied',
    p_invoice_id => p_invoice_id, p_note => 'Used on ' || v_inv.invoice_no);

  perform public.log_audit('advance.applied', 'invoice', p_invoice_id::text,
    jsonb_build_object('amount', v_apply, 'customer_id', v_inv.customer_id));
  return jsonb_build_object('applied', v_apply, 'advance_left', v_left,
                            'due_left', v_inv.due_amount - v_apply);
end $$;

-- Pay an advance back to the customer. Owner only.
create or replace function public.refund_customer_advance(
  p_customer_id uuid, p_amount numeric, p_mode public.payment_mode default 'cash', p_note text default '')
returns numeric language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_left     numeric(14,2);
begin
  perform public.assert_can('owner', false);
  if p_amount is null or p_amount <= 0 then raise exception 'Amount must be positive'; end if;
  if p_mode = 'credit' then raise exception 'Choose how the money was paid back (cash, UPI, card…)'; end if;
  v_left := public.post_customer_advance(v_business, p_customer_id, -p_amount, 'refund',
    p_mode => p_mode, p_note => coalesce(nullif(trim(p_note), ''), 'Advance refunded'));
  perform public.log_audit('advance.refunded', 'customer', p_customer_id::text,
    jsonb_build_object('amount', p_amount, 'mode', p_mode));
  return v_left;
end $$;

-- Undo a receipt (PD23): owner only, reason required, history kept. The
-- bills it paid become due again and its advance part is taken back.
create or replace function public.reverse_customer_payment(p_payment_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_pay      record;
  v_inv      record;
  a          record;
  v_total    numeric(14,2) := 0;
begin
  perform public.assert_can('owner', false);
  if length(trim(coalesce(p_reason, ''))) < 3 then
    raise exception 'Give a reason for reversing this payment';
  end if;

  select * into v_pay from public.customer_payments
    where id = p_payment_id and business_id = v_business for update;
  if v_pay.id is null then raise exception 'Payment not found'; end if;
  if v_pay.reversed_at is not null then raise exception 'This payment is already reversed'; end if;
  if not v_pay.tracked then
    raise exception 'Payments recorded before this update can''t be reversed in the app';
  end if;

  perform 1 from public.customers where id = v_pay.customer_id and business_id = v_business for update;

  for a in select * from public.customer_payment_allocations where payment_id = p_payment_id loop
    select * into v_inv from public.invoices where id = a.invoice_id for update;
    if v_inv.is_cancelled then
      raise exception 'Bill % was cancelled after this payment, so the payment can''t be reversed',
        v_inv.invoice_no;
    end if;
    update public.invoices set
      paid_amount = paid_amount - a.amount,
      payment_status = public.doc_payment_status(total, paid_amount - a.amount, credit_amount)
      where id = a.invoice_id;
    v_total := v_total + a.amount;
  end loop;

  update public.invoice_payments set reversed = true where customer_payment_id = p_payment_id;
  if v_total > 0 then
    update public.customers set due_amount = due_amount + v_total
      where id = v_pay.customer_id and business_id = v_business;
  end if;
  if v_pay.unapplied_amount > 0 then
    begin
      perform public.post_customer_advance(v_business, v_pay.customer_id, -v_pay.unapplied_amount,
        'reversal', p_payment_id => p_payment_id, p_note => 'Payment reversed: ' || trim(p_reason));
    exception when others then
      raise exception 'Part of this payment became an advance that has since been used or refunded — '
        'reverse that first';
    end;
  end if;

  update public.customer_payments
     set reversed_at = now(), reversal_reason = trim(p_reason), reversed_by = auth.uid()
   where id = p_payment_id;

  perform public.log_audit('payment.reversed', 'customer', v_pay.customer_id::text,
    jsonb_build_object('payment_id', p_payment_id, 'amount', v_pay.amount, 'reason', trim(p_reason)));
end $$;

-- ============================================================
-- D. Paths that used to push a due below zero
-- ============================================================

-- Sale returns (replaces 0038's version; only the final settlement changed):
-- the part neither applied to the bill nor refunded becomes an advance.
create or replace function public.create_sale_return(payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business   uuid := public.current_business_id();
  v_invoice_id uuid := (payload ->> 'invoice_id')::uuid;
  v_inv        record;
  v_customer   uuid := (payload ->> 'customer_id')::uuid;
  v_refund_req numeric(14,2) := greatest(coalesce((payload ->> 'refund_amount')::numeric, 0), 0);
  v_refund     numeric(14,2);
  v_total      numeric(14,2) := 0;
  v_apply      numeric(14,2) := 0;
  v_rest       numeric(14,2);
  v_return_id  uuid;
  v_return_no  text;
  v_item       jsonb;
  v_line       record;
  v_qty        numeric;
  v_serial     text;
  v_gross      numeric;
  v_factor     numeric := 1;
  v_unit_value numeric;
  v_unit_tax   numeric;
  v_unit_price numeric;
  v_value      numeric(14,2);
  v_advance    numeric(14,2) := 0;
begin
  if v_business is null then raise exception 'No business for current user'; end if;
  if jsonb_array_length(coalesce(payload -> 'items', '[]'::jsonb)) = 0 then
    raise exception 'Add at least one item to return';
  end if;
  if exists (select 1 from jsonb_array_elements(payload -> 'items') i
             where coalesce((i ->> 'quantity')::numeric, 0) <= 0) then
    raise exception 'Return quantities must be greater than zero';
  end if;

  -- Duplicate serials inside one request.
  if exists (select 1 from jsonb_array_elements(payload -> 'items') i
             where coalesce(i ->> 'serial_no', '') <> ''
             group by i ->> 'serial_no' having count(*) > 1) then
    raise exception 'The same serial/IMEI appears twice in this return';
  end if;

  if v_invoice_id is not null then
    -- Lock the invoice: concurrent returns against it now run one at a time.
    select * into v_inv from public.invoices
      where id = v_invoice_id and business_id = v_business for update;
    if v_inv.id is null then raise exception 'Invoice not found'; end if;
    if v_inv.is_cancelled then raise exception 'Items can''t be returned from a cancelled bill'; end if;
    if v_inv.invoice_type = 'estimate' then raise exception 'Estimates can''t be returned'; end if;
    v_customer := v_inv.customer_id;       -- the bill's customer, never the client's

    select coalesce(sum(line_total), 0) into v_gross
      from public.invoice_items where invoice_id = v_invoice_id;
    if v_gross > 0 then
      v_factor := greatest(v_gross - v_inv.discount_amount, 0) / v_gross;   -- PD26 pro-rata bill discount
    end if;

    -- Quantities per product/variant across the whole request vs sold − already returned.
    for v_line in
      with req as (
        select (i ->> 'product_id')::uuid as pid, (i ->> 'variant_id')::uuid as vid,
               sum((i ->> 'quantity')::numeric) as qty, min(i ->> 'product_name') as name
        from jsonb_array_elements(payload -> 'items') i group by 1, 2),
      sold as (
        select product_id as pid, variant_id as vid, sum(quantity) as qty
        from public.invoice_items where invoice_id = v_invoice_id group by 1, 2),
      ret as (
        select sri.product_id as pid, sri.variant_id as vid, sum(sri.quantity) as qty
        from public.sale_return_items sri
        join public.sale_returns sr on sr.id = sri.sale_return_id
        where sr.invoice_id = v_invoice_id group by 1, 2)
      select req.name, req.qty, coalesce(sold.qty, 0) as sold_qty, coalesce(ret.qty, 0) as ret_qty
      from req
      left join sold on sold.pid is not distinct from req.pid and sold.vid is not distinct from req.vid
      left join ret  on ret.pid  is not distinct from req.pid and ret.vid  is not distinct from req.vid
    loop
      if v_line.sold_qty = 0 then
        raise exception '"%" is not on this bill', v_line.name;
      end if;
      if v_line.ret_qty + v_line.qty > v_line.sold_qty then
        raise exception 'Cannot return % of "%" — only % left to return on this bill (% already returned)',
          v_line.qty, v_line.name, greatest(v_line.sold_qty - v_line.ret_qty, 0), v_line.ret_qty;
      end if;
    end loop;

    -- Serials: sold on this bill, for that product, not returned yet.
    for v_item in select * from jsonb_array_elements(payload -> 'items') loop
      v_serial := coalesce(v_item ->> 'serial_no', '');
      continue when v_serial = '';
      if not exists (select 1 from public.invoice_items ii
                     where ii.invoice_id = v_invoice_id and ii.serial_no = v_serial
                       and ii.product_id is not distinct from (v_item ->> 'product_id')::uuid) then
        raise exception 'Serial/IMEI % was not sold on this bill', v_serial;
      end if;
      if exists (select 1 from public.sale_return_items sri
                 join public.sale_returns sr on sr.id = sri.sale_return_id
                 where sr.invoice_id = v_invoice_id and sri.serial_no = v_serial) then
        raise exception 'Serial/IMEI % has already been returned', v_serial;
      end if;
    end loop;
  elsif v_customer is not null
        and not exists (select 1 from public.customers where id = v_customer and business_id = v_business) then
    raise exception 'Customer not found';
  end if;

  v_return_no := public.next_doc_no(v_business, 'sale_return', 'SR');
  insert into public.sale_returns
    (business_id, return_no, invoice_id, customer_id, total, refund_amount, refund_mode, notes, created_by)
  values
    (v_business, v_return_no, v_invoice_id, v_customer, 0, 0,
     coalesce((payload ->> 'refund_mode')::public.payment_mode, 'cash'),
     coalesce(payload ->> 'notes', ''), auth.uid())
  returning id into v_return_id;

  for v_item in select * from jsonb_array_elements(payload -> 'items') loop
    v_qty := (v_item ->> 'quantity')::numeric;

    if v_invoice_id is not null then
      -- Value from the original bill (average over that product's lines).
      select sum(line_total) / sum(quantity),
             sum(tax_amount) / sum(quantity),
             sum(quantity * unit_price - discount_amount) / sum(quantity)
        into v_unit_value, v_unit_tax, v_unit_price
        from public.invoice_items
        where invoice_id = v_invoice_id
          and product_id is not distinct from (v_item ->> 'product_id')::uuid
          and variant_id is not distinct from (v_item ->> 'variant_id')::uuid;
      v_value := round(v_qty * v_unit_value * v_factor, 2);
      insert into public.sale_return_items
        (business_id, sale_return_id, product_id, variant_id, product_name,
         serial_no, quantity, unit_price, tax_amount, line_total)
      values
        (v_business, v_return_id, (v_item ->> 'product_id')::uuid, (v_item ->> 'variant_id')::uuid,
         v_item ->> 'product_name', coalesce(v_item ->> 'serial_no', ''), v_qty,
         round(v_unit_price * v_factor, 2), round(v_qty * v_unit_tax * v_factor, 2), v_value);
    else
      -- No bill to value against: the client's figures (returns permission required).
      v_value := round(coalesce((v_item ->> 'line_total')::numeric, 0), 2);
      if v_value < 0 then raise exception 'Return value can''t be negative'; end if;
      insert into public.sale_return_items
        (business_id, sale_return_id, product_id, variant_id, product_name,
         serial_no, quantity, unit_price, tax_amount, line_total)
      values
        (v_business, v_return_id, (v_item ->> 'product_id')::uuid, (v_item ->> 'variant_id')::uuid,
         v_item ->> 'product_name', coalesce(v_item ->> 'serial_no', ''), v_qty,
         coalesce((v_item ->> 'unit_price')::numeric, 0),
         coalesce((v_item ->> 'tax_amount')::numeric, 0), v_value);
    end if;
    v_total := v_total + v_value;

    if (v_item ->> 'product_id') is not null then
      insert into public.stock_movements
        (business_id, product_id, variant_id, movement_type, quantity,
         reference_type, reference_id, created_by)
      values
        (v_business, (v_item ->> 'product_id')::uuid, (v_item ->> 'variant_id')::uuid,
         'sale_return', v_qty, 'sale_return', v_return_id, auth.uid());

      v_serial := coalesce(v_item ->> 'serial_no', '');
      if v_serial <> '' then
        update public.product_serials set status = 'returned'
          where business_id = v_business and serial_no = v_serial;
      end if;
    end if;
  end loop;

  -- D27: settle the bill's own unpaid balance first; only the rest can be
  -- refunded or kept as customer credit. Walk-in customers get it refunded.
  if v_invoice_id is not null then
    v_apply := least(v_total, greatest(v_inv.total - v_inv.paid_amount - v_inv.credit_amount, 0));
  end if;
  v_rest := v_total - v_apply;
  v_refund := case when v_customer is null then v_rest else least(v_refund_req, v_rest) end;

  update public.sale_returns set total = v_total, refund_amount = v_refund where id = v_return_id;

  if v_apply > 0 then
    update public.invoices
       set credit_amount = credit_amount + v_apply,
           payment_status = public.doc_payment_status(total, paid_amount, credit_amount + v_apply)
     where id = v_invoice_id;
  end if;

  -- Customer balance (0041): the bill credit lowers their due; whatever is
  -- neither applied to the bill nor refunded becomes an advance.
  if v_customer is not null and v_apply > 0 then
    update public.customers set due_amount = due_amount - v_apply
      where id = v_customer and business_id = v_business;
  end if;
  v_advance := v_rest - v_refund;
  if v_customer is not null and v_advance > 0 then
    perform public.post_customer_advance(v_business, v_customer, v_advance, 'return_credit',
      p_sale_return_id => v_return_id, p_invoice_id => v_invoice_id,
      p_note => 'Return ' || v_return_no);
  end if;

  perform public.log_audit('sale_return.created', 'sale_return', v_return_id::text,
    jsonb_build_object('return_no', v_return_no, 'total', v_total,
                       'applied_to_bill', v_apply, 'refund', v_refund, 'advance', v_advance));
  return jsonb_build_object('id', v_return_id, 'return_no', v_return_no, 'total', v_total,
                            'applied_to_bill', v_apply, 'refund', v_refund, 'advance', v_advance);
end $$;

-- Cancelling a bill (replaces 0008's version): money already paid on it
-- is kept for the customer as an advance instead of disappearing.
create or replace function public.cancel_invoice(p_invoice_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_inv record;
  v_item record;
begin
  select * into v_inv from public.invoices
    where id = p_invoice_id and business_id = v_business for update;
  if v_inv is null then raise exception 'Invoice not found'; end if;
  if v_inv.is_cancelled then raise exception 'Invoice already cancelled'; end if;
  if v_inv.invoice_type <> 'estimate' then
    for v_item in select * from public.invoice_items where invoice_id = p_invoice_id loop
      if v_item.product_id is not null then
        insert into public.stock_movements
          (business_id, product_id, variant_id, movement_type, quantity,
           reference_type, reference_id, note, created_by)
        values (v_business, v_item.product_id, v_item.variant_id, 'adjustment',
                v_item.quantity, 'invoice_cancel', p_invoice_id, 'Invoice cancelled', auth.uid());
        if v_item.serial_no <> '' then
          update public.product_serials set status = 'in_stock', invoice_id = null
            where business_id = v_business and serial_no = v_item.serial_no;
        end if;
      end if;
    end loop;
    if v_inv.customer_id is not null and v_inv.due_amount > 0 then
      update public.customers set due_amount = due_amount - v_inv.due_amount
        where id = v_inv.customer_id;
    end if;
  end if;
  update public.invoices set is_cancelled = true where id = p_invoice_id;
  if v_inv.invoice_type <> 'estimate' and v_inv.customer_id is not null and v_inv.paid_amount > 0 then
    perform public.post_customer_advance(v_business, v_inv.customer_id, v_inv.paid_amount,
      'cancelled_bill', p_invoice_id => p_invoice_id,
      p_note => 'Paid on cancelled bill ' || v_inv.invoice_no);
  end if;
  perform public.log_audit('invoice.cancelled', 'invoice', p_invoice_id::text,
    jsonb_build_object('paid_to_advance', case when v_inv.customer_id is null then 0 else v_inv.paid_amount end));
end $$;

-- A bill edited below what was already paid: the excess moves off the bill
-- into the customer's advance (spec: excess is an advance, never an
-- overpaid bill). update_invoice lowers the customer's due by the whole
-- total change, so the moved part is added back to the due here.
create or replace function public.settle_overpaid_invoice()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_move numeric(14,2);
begin
  if new.is_cancelled or new.customer_id is null or new.invoice_type = 'estimate' then
    return new;
  end if;
  v_move := least(-(new.total - new.paid_amount - new.credit_amount), new.paid_amount);
  if v_move > 0.005 then
    update public.invoices set
      paid_amount = paid_amount - v_move,
      payment_status = public.doc_payment_status(total, paid_amount - v_move, credit_amount)
      where id = new.id;
    update public.customers set due_amount = due_amount + v_move
      where id = new.customer_id and business_id = new.business_id;
    perform public.post_customer_advance(new.business_id, new.customer_id, v_move, 'overpaid_bill',
      p_invoice_id => new.id, p_note => 'Bill ' || new.invoice_no || ' reduced below the amount paid');
  end if;
  return new;
end $$;

drop trigger if exists trg_invoices_overpaid on public.invoices;
create trigger trg_invoices_overpaid after update of total, paid_amount, credit_amount on public.invoices
  for each row execute function public.settle_overpaid_invoice();

-- ============================================================
-- E. Backfill
-- ============================================================
alter table public.invoices disable trigger trg_00_tenant_refs;

-- Overpaid bills (edited below the amount paid before 0041): re-run the
-- settlement above.
update public.invoices set total = total
  where customer_id is not null and not is_cancelled and invoice_type <> 'estimate'
    and due_amount < -0.005;

alter table public.invoices enable trigger trg_00_tenant_refs;

-- Negative dues (credit kept as a negative balance before 0041) become advances.
do $$
declare r record;
begin
  for r in select id, business_id, due_amount from public.customers where due_amount < -0.005 loop
    perform public.post_customer_advance(r.business_id, r.id, -r.due_amount, 'opening',
      p_note => 'Credit carried over from before advances');
    update public.customers set due_amount = 0 where id = r.id;
  end loop;
end $$;

alter table public.customers drop constraint if exists customers_advance_nonnegative;
alter table public.customers add constraint customers_advance_nonnegative check (advance_amount >= 0);

-- ============================================================
-- Grants
-- ============================================================
revoke execute on function public.post_customer_advance(uuid, uuid, numeric, text, uuid, uuid, uuid, public.payment_mode, text) from public, anon, authenticated;
revoke execute on function public.plan_customer_payment(uuid, uuid, numeric, uuid[]) from public, anon, authenticated;
revoke execute on function public.settle_overpaid_invoice() from public, anon, authenticated;

revoke execute on function public.preview_customer_payment(uuid, numeric, uuid[]) from public, anon;
revoke execute on function public.record_customer_payment(uuid, numeric, public.payment_mode, date, text, uuid, uuid[]) from public, anon;
revoke execute on function public.apply_customer_advance(uuid, numeric) from public, anon;
revoke execute on function public.refund_customer_advance(uuid, numeric, public.payment_mode, text) from public, anon;
revoke execute on function public.reverse_customer_payment(uuid, text) from public, anon;
grant execute on function public.preview_customer_payment(uuid, numeric, uuid[]) to authenticated;
grant execute on function public.record_customer_payment(uuid, numeric, public.payment_mode, date, text, uuid, uuid[]) to authenticated;
grant execute on function public.apply_customer_advance(uuid, numeric) to authenticated;
grant execute on function public.refund_customer_advance(uuid, numeric, public.payment_mode, text) to authenticated;
grant execute on function public.reverse_customer_payment(uuid, text) to authenticated;
