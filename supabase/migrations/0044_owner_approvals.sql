-- ============================================================
-- 0044_owner_approvals.sql — release R1, batch 5
-- (LAUNCH_SPECIFICATION.md D17–D19, D24, D25, PD02–PD04, PD10, PD11,
--  PD15, PD16, PD19, PD20, PD24)
--
-- A sale that breaks one of these rules is not finalised until the owner
-- approves it:
--   below_cost   a line's price after all discounts (bill discount
--                allocated, excluding GST) is below its purchase cost (D17,
--                PD04). Lines without a cost are not checked (PD02).
--   credit_limit the customer's exposure after the sale — unpaid bills
--                minus advances (PD16) — exceeds their limit (D24).
--   overdue      the customer has an overdue bill and this sale adds
--                credit (D25). A fully paid sale is fine.
--   discount     a staff member went beyond their discount limit (PD10).
--
-- Staff: the bill is refused with APPROVAL_REQUIRED; they submit a request
-- (the sale is kept server-side as a pending draft, D19); the owner
-- approves or rejects it in their own app, ticking every exception
-- (PD15); staff then complete exactly that sale. An approval is bound to
-- the sale's content, expires (PD11) and is used once.
-- Owner: must acknowledge the exceptions on their own sale (D17).
-- Offline bills that sync with exceptions are kept and flagged for owner
-- review — the goods have already left (PD24).
--
-- Also: due dates on bills (PD19: store terms, default 30 days) and
-- overdue grace days (PD20, default 0).
--
-- Run AFTER 0043.
-- ============================================================

-- ============================================================
-- A. Due dates and overdue
-- ============================================================
alter table public.businesses add column if not exists payment_terms_days integer not null default 30;
alter table public.businesses add column if not exists overdue_grace_days integer not null default 0;
alter table public.businesses drop constraint if exists businesses_terms_check;
alter table public.businesses add constraint businesses_terms_check
  check (payment_terms_days between 0 and 365 and overdue_grace_days between 0 and 365);

alter table public.invoices add column if not exists due_date date;

create or replace function public.set_invoice_due_date()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.due_date is null then
    new.due_date := public.ist_date(new.invoice_date)
      + coalesce((select payment_terms_days from public.businesses where id = new.business_id), 30);
  end if;
  return new;
end $$;

drop trigger if exists trg_invoices_due_date on public.invoices;
create trigger trg_invoices_due_date before insert on public.invoices
  for each row execute function public.set_invoice_due_date();

alter table public.invoices disable trigger trg_00_tenant_refs;
update public.invoices i set due_date = public.ist_date(i.invoice_date) + b.payment_terms_days
  from public.businesses b
  where b.id = i.business_id and i.due_date is null;
alter table public.invoices enable trigger trg_00_tenant_refs;

-- Overdue balance of a customer (excluding one bill, e.g. the one being made).
create or replace function public.customer_overdue(p_customer uuid, p_exclude uuid default null)
returns table (amount numeric, bills integer, oldest_due date)
language sql stable security definer set search_path = public as $$
  select coalesce(sum(i.due_amount), 0), count(*)::integer, min(i.due_date)
  from public.invoices i
  join public.businesses b on b.id = i.business_id
  where i.customer_id = p_customer
    and i.id is distinct from p_exclude
    and not i.is_cancelled and i.invoice_type <> 'estimate'
    and i.due_amount > 0.005
    and i.due_date + b.overdue_grace_days < public.ist_date(now());
$$;

-- ============================================================
-- B. Discount limits become approvable (replaces 0043's check):
-- over-limit is reported, not refused. Missing price permission is
-- still refused outright (D15: unauthorised overrides are not allowed).
-- ============================================================
create or replace function public.check_invoice_pricing(p_invoice uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_inv       record;
  v_default   numeric := 0;
  v_actual    numeric := 0;
  v_reduction numeric := 0;
  v_role      text;
  v_limit     numeric;
  v_pct       numeric := 0;
  v_over      boolean := false;
begin
  select * into v_inv from public.invoices where id = p_invoice;
  if v_inv.id is null then return null; end if;

  update public.invoice_items ii set
    list_price = round(pl.def, 2),
    price_source = case
      when pl.def is null then 'manual'
      when abs(pl.eff - pl.def) <= 0.05 then pl.def_source
      when pl.customer is not null and abs(pl.eff - pl.customer) <= 0.05 then 'customer'
      when pl.wholesale is not null and abs(pl.eff - pl.wholesale) <= 0.05 then 'wholesale'
      when pl.retail is not null and abs(pl.eff - pl.retail) <= 0.05 then 'retail'
      else 'negotiated' end
  from public.invoice_price_lines(p_invoice) pl
  where ii.id = pl.id;

  select coalesce(sum(pl.quantity * coalesce(pl.def, pl.eff)), 0), coalesce(sum(pl.quantity * pl.eff), 0)
    into v_default, v_actual from public.invoice_price_lines(p_invoice) pl;
  v_actual := v_actual - v_inv.discount_amount;
  v_reduction := greatest(round(v_default - v_actual, 2), 0);
  v_pct := case when v_default > 0 then round(v_reduction / v_default * 100, 2) else 0 end;

  update public.invoices set default_total = round(v_default, 2), price_reduction = v_reduction
    where id = p_invoice;

  if v_inv.invoice_type <> 'estimate' and auth.uid() is not null and v_reduction > 0.05 then
    select role::text into v_role from public.profiles where id = auth.uid();
    if coalesce(v_role, '') not in ('owner', 'admin') then
      if not public.has_permission('can_edit_prices') then
        raise exception 'This bill is ₹% below the default prices — you don''t have permission to change prices or give discounts',
          v_reduction using errcode = '42501';
      end if;
      select coalesce(discount_limit_pct, 0) into v_limit
        from public.staff_permissions where profile_id = auth.uid();
      v_limit := coalesce(v_limit, 0);
      v_over := v_reduction > v_default * v_limit / 100 + 0.05;
    end if;
  end if;

  return jsonb_build_object('default_total', round(v_default, 2), 'reduction', v_reduction,
                            'pct', v_pct, 'limit_pct', v_limit, 'over_limit', v_over);
end $$;
revoke execute on function public.check_invoice_pricing(uuid) from public, anon, authenticated;

-- ============================================================
-- C. Exceptions of a saved bill
-- ============================================================
create or replace function public.sale_exceptions(p_invoice uuid, p_pricing jsonb)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_inv     record;
  v_cust    record;
  v_out     jsonb := '[]'::jsonb;
  v_lines   jsonb;
  v_loss    numeric;
  v_od      record;
  v_expo    numeric;
begin
  select * into v_inv from public.invoices where id = p_invoice;
  if v_inv.id is null or v_inv.invoice_type = 'estimate' then return v_out; end if;

  -- below cost (D17, PD02–PD04): taxable value per unit (after the bill
  -- discount, excluding GST) vs purchase cost; no cost = not checked.
  select coalesce(jsonb_agg(jsonb_build_object(
           'product_name', x.product_name, 'quantity', x.quantity,
           'price', round(x.unit_net, 2), 'cost', x.cost)), '[]'::jsonb),
         coalesce(sum((x.cost - x.unit_net) * x.quantity), 0)
    into v_lines, v_loss
  from (
    select ii.product_name, ii.quantity,
           ii.taxable_value / nullif(ii.quantity, 0) as unit_net,
           coalesce(nullif(pv.purchase_price, 0), p.purchase_price) as cost
    from public.invoice_items ii
    join public.products p on p.id = ii.product_id
    left join public.product_variants pv on pv.id = ii.variant_id
    where ii.invoice_id = p_invoice) x
  where coalesce(x.cost, 0) > 0 and x.unit_net < x.cost - 0.005;
  if jsonb_array_length(v_lines) > 0 then
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'kind', 'below_cost', 'lines', v_lines, 'loss', round(v_loss, 2)));
  end if;

  -- discount beyond the staff limit (PD10)
  if coalesce((p_pricing ->> 'over_limit')::boolean, false) then
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'kind', 'discount', 'reduction', (p_pricing ->> 'reduction')::numeric,
      'pct', (p_pricing ->> 'pct')::numeric, 'limit_pct', (p_pricing ->> 'limit_pct')::numeric));
  end if;

  -- credit checks apply only when this sale adds unpaid money
  if v_inv.customer_id is not null and v_inv.due_amount > 0.005 then
    select * into v_cust from public.customers where id = v_inv.customer_id;

    -- over the credit limit (D24, PD16: unpaid bills − advances)
    v_expo := v_cust.due_amount - coalesce(v_cust.advance_amount, 0);
    if not coalesce(v_cust.credit_unlimited, false) and v_cust.credit_limit is not null
       and v_expo > v_cust.credit_limit + 0.005 then
      v_out := v_out || jsonb_build_array(jsonb_build_object(
        'kind', 'credit_limit', 'limit', v_cust.credit_limit,
        'exposure_after', round(v_expo, 2), 'new_due', v_inv.due_amount));
    end if;

    -- overdue bills (D25, PD20)
    select * into v_od from public.customer_overdue(v_inv.customer_id, p_invoice);
    if v_od.amount > 0.005 then
      v_out := v_out || jsonb_build_array(jsonb_build_object(
        'kind', 'overdue', 'overdue_amount', v_od.amount, 'bills', v_od.bills,
        'oldest_due', v_od.oldest_due, 'new_due', v_inv.due_amount));
    end if;
  end if;

  return v_out;
end $$;

-- What staff may see: no cost or loss without the profit permission (D17).
create or replace function public.public_exceptions(p_ex jsonb)
returns jsonb language sql stable security definer set search_path = public as $$
  select case when public.has_permission('can_view_profit') then p_ex else
    coalesce((select jsonb_agg(
      case when e ->> 'kind' = 'below_cost' then jsonb_build_object(
        'kind', 'below_cost',
        'lines', (select jsonb_agg(l - 'cost' - 'price') from jsonb_array_elements(e -> 'lines') l))
      else e end)
    from jsonb_array_elements(p_ex) e), '[]'::jsonb) end;
$$;

-- What an approval is bound to: customer, type, lines, discounts, payment.
create or replace function public.sale_fingerprint(p jsonb)
returns text language sql immutable as $$
  select md5(jsonb_build_object(
    'c', p -> 'customer_id',
    't', coalesce(p ->> 'invoice_type', 'gst'),
    'd', round(coalesce((p ->> 'discount_amount')::numeric, 0), 2),
    'paid', round(coalesce((p ->> 'paid_amount')::numeric, 0), 2),
    'pay', coalesce((select jsonb_agg(jsonb_build_object('m', x ->> 'mode',
                      'a', round(coalesce((x ->> 'amount')::numeric, 0), 2)) order by x ->> 'mode', x ->> 'amount')
                     from jsonb_array_elements(coalesce(p -> 'payments', '[]'::jsonb)) x), '[]'::jsonb),
    'i', coalesce((select jsonb_agg(jsonb_build_object(
            'p', i -> 'product_id', 'v', i -> 'variant_id', 's', coalesce(i ->> 'serial_no', ''),
            'q', round((i ->> 'quantity')::numeric, 3),
            'u', round((i ->> 'unit_price')::numeric, 2),
            'x', round(coalesce((i ->> 'discount_amount')::numeric, 0), 2),
            'g', round(coalesce((i ->> 'gst_rate')::numeric, 0), 2))
          order by i ->> 'product_id', i ->> 'variant_id', i ->> 'serial_no', i ->> 'quantity', i ->> 'unit_price')
         from jsonb_array_elements(coalesce(p -> 'items', '[]'::jsonb)) i), '[]'::jsonb)
  )::text);
$$;

-- ============================================================
-- D. Approval requests
-- ============================================================
create table if not exists public.sale_approvals (
  id                 uuid primary key default gen_random_uuid(),
  business_id        uuid not null references public.businesses(id) on delete cascade,
  requested_by       uuid references public.profiles(id),
  customer_id        uuid references public.customers(id) on delete set null,
  payload            jsonb not null,
  fingerprint        text not null,
  exceptions         jsonb not null,
  total              numeric(14,2) not null default 0,
  reason             text not null default '',
  status             text not null default 'pending' check (status in
                       ('pending', 'approved', 'rejected', 'withdrawn', 'consumed', 'expired', 'flagged', 'reviewed')),
  decided_by         uuid references public.profiles(id),
  decided_at         timestamptz,
  decision_note      text not null default '',
  expires_at         timestamptz,
  consumed_invoice_id uuid references public.invoices(id) on delete set null,
  created_at         timestamptz not null default now()
);
create index if not exists idx_sale_approvals_business
  on public.sale_approvals (business_id, status, created_at desc);

alter table public.sale_approvals enable row level security;
drop policy if exists "owner read" on public.sale_approvals;
drop policy if exists "admin all" on public.sale_approvals;
-- Full details (with cost) for the owner; staff use my_sale_approvals().
create policy "owner read" on public.sale_approvals for select
  using (business_id = (select public.current_business_id())
         and (select public.has_permission('owner')));
create policy "admin all" on public.sale_approvals for all
  using (public.is_admin()) with check (public.is_admin());

drop trigger if exists trg_00_tenant_refs on public.sale_approvals;
create trigger trg_00_tenant_refs before insert or update on public.sale_approvals
  for each row execute function public.enforce_tenant_refs(
    'customer_id=customers', 'consumed_invoice_id=invoices');

alter table public.invoices add column if not exists approval_id uuid references public.sale_approvals(id) on delete set null;
alter table public.invoices add column if not exists approved_by uuid references public.profiles(id);
alter table public.invoices add column if not exists approved_exceptions jsonb;
alter table public.invoices add column if not exists exception_status text not null default '';

-- PD11: end of the business day (IST midnight) or 12 hours, whichever first.
create or replace function public.approval_expiry(p_from timestamptz)
returns timestamptz language sql immutable as $$
  select least(p_from + interval '12 hours',
               ((public.ist_date(p_from) + 1)::timestamp at time zone 'Asia/Kolkata'));
$$;

-- Decides what happens to a bill with exceptions: allowed (approval or
-- owner acknowledgement), flagged (offline), or refused with the
-- exceptions for the app to show.
create or replace function public.settle_sale_exceptions(p_invoice uuid, p_payload jsonb, p_ex jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_role     text;
  v_appr     record;
  v_kinds    text[];
  v_ok_kinds text[];
begin
  if jsonb_array_length(p_ex) = 0 or auth.uid() is null then return; end if;
  select role::text into v_role from public.profiles where id = auth.uid();
  select array_agg(e ->> 'kind') into v_kinds from jsonb_array_elements(p_ex) e;

  -- PD24: an offline bill already happened — keep it, flag it for the owner.
  if coalesce((p_payload ->> 'offline_created')::boolean, false) then
    insert into public.sale_approvals
      (business_id, requested_by, customer_id, payload, fingerprint, exceptions, total,
       status, consumed_invoice_id, reason)
    select v_business, auth.uid(), customer_id, p_payload, public.sale_fingerprint(p_payload),
           p_ex, total, 'flagged', id, 'Billed offline'
    from public.invoices where id = p_invoice;
    update public.invoices set exception_status = 'flagged', approved_exceptions = p_ex
      where id = p_invoice;
    return;
  end if;

  -- An approved request for exactly this sale.
  if (p_payload ->> 'approval_id') is not null then
    select * into v_appr from public.sale_approvals
      where id = (p_payload ->> 'approval_id')::uuid and business_id = v_business
      for update;
    if v_appr.id is null then raise exception 'Approval not found'; end if;
    if v_appr.status = 'consumed' then raise exception 'This approval has already been used'; end if;
    if v_appr.status <> 'approved' then
      raise exception 'This sale is not approved (%)', v_appr.status;
    end if;
    if v_appr.expires_at is not null and now() > v_appr.expires_at then
      update public.sale_approvals set status = 'expired' where id = v_appr.id;
      raise exception 'The approval has expired — submit the sale again';
    end if;
    if v_appr.requested_by is distinct from auth.uid() and coalesce(v_role, '') <> 'owner' then
      raise exception 'Only the person who asked for this approval can use it';
    end if;
    if v_appr.fingerprint <> public.sale_fingerprint(p_payload) then
      raise exception 'The sale changed after it was approved — ask for approval again';
    end if;
    select array_agg(e ->> 'kind') into v_ok_kinds from jsonb_array_elements(v_appr.exceptions) e;
    if not (v_kinds <@ coalesce(v_ok_kinds, '{}')) then
      raise exception 'APPROVAL_REQUIRED %', public.public_exceptions(p_ex)::text;
    end if;
    update public.sale_approvals set status = 'consumed', consumed_invoice_id = p_invoice
      where id = v_appr.id;
    update public.invoices set approval_id = v_appr.id, approved_by = v_appr.decided_by,
           approved_exceptions = p_ex, exception_status = 'approved'
      where id = p_invoice;
    return;
  end if;

  -- The owner's own sale: explicit acknowledgement (D17).
  if coalesce(v_role, '') = 'owner' and coalesce((p_payload ->> 'owner_ack')::boolean, false) then
    update public.invoices set approved_by = auth.uid(), approved_exceptions = p_ex,
           exception_status = 'acknowledged'
      where id = p_invoice;
    return;
  end if;

  raise exception 'APPROVAL_REQUIRED %', public.public_exceptions(p_ex)::text;
end $$;

revoke execute on function public.customer_overdue(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.sale_exceptions(uuid, jsonb) from public, anon, authenticated;
revoke execute on function public.public_exceptions(jsonb) from public, anon, authenticated;
revoke execute on function public.settle_sale_exceptions(uuid, jsonb, jsonb) from public, anon, authenticated;

-- ============================================================
-- E. create_invoice / update_invoice (replace 0043's wrappers)
-- ============================================================
create or replace function public.create_invoice(payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v         jsonb;
  v_id      uuid;
  v_pricing jsonb;
  v_ex      jsonb;
begin
  v := public.create_invoice_impl(payload);
  if coalesce((v ->> 'already_synced')::boolean, false) then return v; end if;
  v_id := (v ->> 'id')::uuid;
  v_pricing := public.check_invoice_pricing(v_id);
  v_ex := public.sale_exceptions(v_id, v_pricing);
  perform public.settle_sale_exceptions(v_id, payload, v_ex);
  return v;
end $$;

-- Edits can't request approval at launch: staff edits that create an
-- exception are refused; the owner acknowledges (payload.owner_ack).
create or replace function public.update_invoice(p_invoice_id uuid, payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v         jsonb;
  v_pricing jsonb;
  v_ex      jsonb;
begin
  v := public.update_invoice_impl(p_invoice_id, payload);
  v_pricing := public.check_invoice_pricing(p_invoice_id);
  v_ex := public.sale_exceptions(p_invoice_id, v_pricing);
  perform public.settle_sale_exceptions(p_invoice_id, payload - 'approval_id' - 'offline_created', v_ex);
  return v;
end $$;

-- ============================================================
-- F. Requesting, deciding and completing
-- ============================================================

-- Staff: keep the sale as a pending draft and ask the owner (D18, D19).
-- The sale is evaluated by creating it inside a rolled-back
-- sub-transaction, so the exceptions are exactly what the real bill has.
create or replace function public.request_sale_approval(payload jsonb, p_reason text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_payload  jsonb := payload - 'approval_id' - 'owner_ack' - 'local_id' - 'offline_created';
  v          jsonb;
  v_ex       jsonb;
  v_id       uuid;
  v_pricing  jsonb;
  v_expires  timestamptz := public.approval_expiry(now());
begin
  perform public.assert_can('can_create_invoice');
  begin
    v := public.create_invoice_impl(v_payload);
    v_pricing := public.check_invoice_pricing((v ->> 'id')::uuid);
    v_ex := public.sale_exceptions((v ->> 'id')::uuid, v_pricing);
    raise exception 'dry run' using errcode = 'SX001';
  exception when sqlstate 'SX001' then
    null;   -- everything above is rolled back; v and v_ex keep their values
  end;
  if jsonb_array_length(coalesce(v_ex, '[]'::jsonb)) = 0 then
    raise exception 'This sale doesn''t need approval — create the bill normally';
  end if;

  -- A newer request for the same sale replaces an older pending one.
  update public.sale_approvals set status = 'withdrawn'
    where business_id = v_business and requested_by = auth.uid()
      and fingerprint = public.sale_fingerprint(v_payload) and status = 'pending';

  insert into public.sale_approvals
    (business_id, requested_by, customer_id, payload, fingerprint, exceptions, total,
     reason, expires_at)
  values (v_business, auth.uid(), (v_payload ->> 'customer_id')::uuid, v_payload,
          public.sale_fingerprint(v_payload), v_ex, coalesce((v ->> 'total')::numeric, 0),
          coalesce(trim(p_reason), ''), v_expires)
  returning id into v_id;

  perform public.log_audit('approval.requested', 'sale_approval', v_id::text,
    jsonb_build_object('kinds', (select jsonb_agg(e -> 'kind') from jsonb_array_elements(v_ex) e)));
  return jsonb_build_object('id', v_id, 'status', 'pending', 'expires_at', v_expires,
                            'exceptions', public.public_exceptions(v_ex));
end $$;

-- Owner decides. Approving needs every listed exception ticked (PD15).
create or replace function public.decide_sale_approval(
  p_id uuid, p_approve boolean, p_note text default '', p_ticked text[] default '{}')
returns void language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_appr     record;
  v_kinds    text[];
begin
  if (select role::text from public.profiles where id = auth.uid()) is distinct from 'owner' then
    raise exception 'Only the shop owner can approve or reject sales' using errcode = '42501';
  end if;
  select * into v_appr from public.sale_approvals
    where id = p_id and business_id = v_business for update;
  if v_appr.id is null then raise exception 'Request not found'; end if;

  if v_appr.status = 'flagged' then
    -- An offline bill that already happened: the owner reviews it.
    update public.sale_approvals set status = 'reviewed', decided_by = auth.uid(),
           decided_at = now(), decision_note = coalesce(p_note, '')
      where id = p_id;
    return;
  end if;
  if v_appr.status <> 'pending' then
    raise exception 'This request is already %', v_appr.status;
  end if;
  if v_appr.expires_at is not null and now() > v_appr.expires_at then
    update public.sale_approvals set status = 'expired' where id = p_id;
    raise exception 'This request has expired — staff need to submit it again';
  end if;

  if p_approve then
    select array_agg(e ->> 'kind') into v_kinds from jsonb_array_elements(v_appr.exceptions) e;
    if not (v_kinds <@ coalesce(p_ticked, '{}')) then
      raise exception 'Tick every exception to approve this sale';
    end if;
  end if;

  update public.sale_approvals
     set status = case when p_approve then 'approved' else 'rejected' end,
         decided_by = auth.uid(), decided_at = now(), decision_note = coalesce(p_note, '')
   where id = p_id;
  perform public.log_audit(case when p_approve then 'approval.approved' else 'approval.rejected' end,
    'sale_approval', p_id::text, jsonb_build_object('note', coalesce(p_note, '')));
end $$;

-- Staff (or the owner) finalise an approved sale: exactly the stored sale,
-- once. A retry returns the bill already made.
create or replace function public.complete_approved_sale(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_appr     record;
begin
  select * into v_appr from public.sale_approvals where id = p_id and business_id = v_business;
  if v_appr.id is null then raise exception 'Request not found'; end if;
  if v_appr.status = 'consumed' then
    return jsonb_build_object('id', v_appr.consumed_invoice_id, 'already_done', true,
      'invoice_no', (select invoice_no from public.invoices where id = v_appr.consumed_invoice_id));
  end if;
  return public.create_invoice(v_appr.payload || jsonb_build_object('approval_id', p_id));
end $$;

-- The requester (or owner) withdraws a request they no longer need.
create or replace function public.withdraw_sale_approval(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.sale_approvals set status = 'withdrawn'
    where id = p_id and business_id = public.current_business_id()
      and status in ('pending', 'approved')
      and (requested_by = auth.uid() or public.has_permission('owner'));
  if not found then raise exception 'Nothing to withdraw'; end if;
end $$;

-- Staff's own requests, without cost details unless allowed.
create or replace function public.my_sale_approvals()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', a.id, 'status', case when a.status in ('pending', 'approved') and a.expires_at < now()
                               then 'expired' else a.status end,
    'customer_name', coalesce(c.name, a.payload ->> 'customer_name', ''),
    'total', a.total, 'reason', a.reason, 'decision_note', a.decision_note,
    'exceptions', public.public_exceptions(a.exceptions),
    'payload', a.payload,
    'expires_at', a.expires_at, 'created_at', a.created_at,
    'invoice_id', a.consumed_invoice_id) order by a.created_at desc), '[]'::jsonb)
  from public.sale_approvals a
  left join public.customers c on c.id = a.customer_id
  where a.business_id = public.current_business_id() and a.requested_by = auth.uid()
    and a.created_at > now() - interval '7 days';
$$;

revoke execute on function public.request_sale_approval(jsonb, text) from public, anon;
revoke execute on function public.decide_sale_approval(uuid, boolean, text, text[]) from public, anon;
revoke execute on function public.complete_approved_sale(uuid) from public, anon;
revoke execute on function public.withdraw_sale_approval(uuid) from public, anon;
revoke execute on function public.my_sale_approvals() from public, anon;
grant execute on function public.request_sale_approval(jsonb, text) to authenticated;
grant execute on function public.decide_sale_approval(uuid, boolean, text, text[]) to authenticated;
grant execute on function public.complete_approved_sale(uuid) to authenticated;
grant execute on function public.withdraw_sale_approval(uuid) to authenticated;
grant execute on function public.my_sale_approvals() to authenticated;
