-- ============================================================
-- 0052_r1_leftovers.sql — release R1, batch 13
-- (LAUNCH_SPECIFICATION.md PD13, PD19, PD59; units "conversion
-- snapshots on documents")
--
-- 1. Diagnostic fee (PD59). A service can carry a fixed diagnostic fee.
--    At intake the job card records the fee and the customer's consent
--    (who recorded it, when). With consent, the fee can be added to the
--    job once — without an approved estimate — so it is billable even if
--    the repair is rejected. Without consent it can't be charged.
-- 2. Due dates (PD19). A new bill may carry its own due date (staff
--    billing it); changing the due date of an issued bill is owner-only,
--    with a reason, and is logged.
-- 3. Approval push (PD13). claim_approval_notification() lets the app's
--    approval-push Edge Function announce a new approval request to the
--    owner's phones exactly once (the in-app inbox stays authoritative).
-- 4. Unit snapshots. Bill and purchase lines keep the product's bulk unit
--    and conversion as they were (e.g. 1 Bag = 50 kg), so later product
--    changes don't alter old documents.
--
-- Run AFTER 0051.
-- ============================================================

-- ============================================================
-- A. Diagnostic fee (PD59)
-- ============================================================
alter table public.services add column if not exists diagnostic_fee numeric(12,2) not null default 0;
alter table public.services drop constraint if exists services_diagnostic_fee_check;
alter table public.services add constraint services_diagnostic_fee_check check (diagnostic_fee >= 0);

alter table public.job_cards add column if not exists diagnostic_fee numeric(12,2) not null default 0;
alter table public.job_cards add column if not exists diagnostic_gst_rate numeric(5,2) not null default 0;
alter table public.job_cards add column if not exists diagnostic_sac text not null default '';
alter table public.job_cards add column if not exists diagnostic_consent_at timestamptz;
alter table public.job_cards add column if not exists diagnostic_consent_by uuid references public.profiles(id);

alter table public.job_card_items add column if not exists is_diagnostic boolean not null default false;

-- 0046's work-scope guard, plus: the consented diagnostic fee, once, at
-- its recorded price, needs no estimate.
create or replace function public.guard_job_item_scope()
returns trigger language plpgsql as $$
declare
  v_required boolean;
  v_job      record;
  v_line     record;
  v_used     numeric;
begin
  if new.is_diagnostic then
    select * into v_job from public.job_cards where id = new.job_card_id;
    if v_job.diagnostic_consent_at is null or v_job.diagnostic_fee <= 0 then
      raise exception 'No diagnostic fee was agreed with the customer for this job';
    end if;
    if new.item_type <> 'labor' or new.quantity <> 1
       or new.unit_price <> v_job.diagnostic_fee or new.gst_rate <> v_job.diagnostic_gst_rate then
      raise exception 'The diagnostic fee must be charged as agreed (%)', v_job.diagnostic_fee;
    end if;
    if exists (select 1 from public.job_card_items
               where job_card_id = new.job_card_id and is_diagnostic and id <> new.id) then
      raise exception 'The diagnostic fee is already on this job';
    end if;
    return new;
  end if;

  select estimate_required into v_required from public.job_cards where id = new.job_card_id;
  if not coalesce(v_required, false) then return new; end if;

  if new.estimate_line_id is null then
    raise exception 'Only work from the customer''s approved estimate can be added to this job';
  end if;
  select * into v_line from public.job_estimate_lines where id = new.estimate_line_id;
  if v_line.id is null or v_line.job_card_id <> new.job_card_id or not v_line.approved
     or v_line.estimate_id is distinct from public.current_job_estimate(new.job_card_id) then
    raise exception '"%" is not in the customer''s approved estimate',
      coalesce(v_line.name, new.name);
  end if;
  if new.item_type <> v_line.item_type
     or new.product_id is distinct from v_line.product_id
     or new.variant_id is distinct from v_line.variant_id
     or new.unit_price <> v_line.unit_price or new.gst_rate <> v_line.gst_rate then
    raise exception '"%" must be billed as approved (% at %)',
      v_line.name, v_line.quantity, v_line.unit_price;
  end if;
  select coalesce(sum(quantity), 0) into v_used from public.job_card_items
    where estimate_line_id = new.estimate_line_id and id <> new.id;
  if v_used + new.quantity > v_line.quantity then
    raise exception 'The customer approved % of "%" and % is already used',
      v_line.quantity, v_line.name, v_used;
  end if;
  return new;
end $$;

-- 0046's create_job_card, plus the diagnostic fee and consent:
-- payload.diagnostic_service_id + payload.diagnostic_consent = true.
create or replace function public.create_job_card(payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_job_id   uuid;
  v_job_no   text;
  v_consent  boolean := coalesce((payload ->> 'diagnostic_consent')::boolean, false);
  v_fee      numeric := 0;
  v_gst      numeric := 0;
  v_sac      text := '';
begin
  if v_business is null then raise exception 'No business for current user'; end if;
  if nullif(payload ->> 'diagnostic_service_id', '') is not null then
    select diagnostic_fee, gst_rate, sac_code into v_fee, v_gst, v_sac from public.services
      where id = (payload ->> 'diagnostic_service_id')::uuid and business_id = v_business;
    if not found then raise exception 'Service not found'; end if;
    -- No consent, no fee.
    if not v_consent then v_fee := 0; end if;
  end if;
  v_job_no := public.next_doc_no(v_business, 'job_card', 'JOB');

  insert into public.job_cards
    (business_id, job_no, customer_id, customer_name, customer_phone, item_name, brand, model,
     serial_no, issue_description, item_condition, accessories_received, technician_name,
     estimated_cost, advance_amount, advance_mode, expected_delivery, customer_note,
     internal_note, warranty_days, service_location, job_type, registration_no, odometer_km,
     fuel_level, diagnostic_fee, diagnostic_gst_rate, diagnostic_sac, diagnostic_consent_at,
     diagnostic_consent_by, created_by)
  values
    (v_business, v_job_no, (payload ->> 'customer_id')::uuid,
     coalesce(payload ->> 'customer_name', ''), coalesce(payload ->> 'customer_phone', ''),
     coalesce(payload ->> 'item_name', ''), coalesce(payload ->> 'brand', ''),
     coalesce(payload ->> 'model', ''), coalesce(payload ->> 'serial_no', ''),
     coalesce(payload ->> 'issue_description', ''), coalesce(payload ->> 'item_condition', ''),
     coalesce(payload ->> 'accessories_received', ''), coalesce(payload ->> 'technician_name', ''),
     coalesce((payload ->> 'estimated_cost')::numeric, 0),
     coalesce((payload ->> 'advance_amount')::numeric, 0),
     coalesce((payload ->> 'advance_mode')::public.payment_mode, 'cash'),
     nullif(payload ->> 'expected_delivery', '')::date,
     coalesce(payload ->> 'customer_note', ''), coalesce(payload ->> 'internal_note', ''),
     (payload ->> 'warranty_days')::integer,
     coalesce(payload ->> 'service_location', ''),
     coalesce(nullif(payload ->> 'job_type', ''), 'device'),
     coalesce(payload ->> 'registration_no', ''),
     nullif(payload ->> 'odometer_km', '')::integer,
     coalesce(payload ->> 'fuel_level', ''),
     v_fee, v_gst, v_sac,
     case when v_fee > 0 then now() end,
     case when v_fee > 0 then auth.uid() end,
     auth.uid())
  returning id into v_job_id;

  insert into public.job_status_history (business_id, job_card_id, status, note, created_by)
  values (v_business, v_job_id, 'received',
          case when v_fee > 0
               then format('Job card created; customer agreed to a diagnostic fee of %s', v_fee)
               else 'Job card created' end,
          auth.uid());

  perform public.log_audit('job_card.created', 'job_card', v_job_id::text,
    jsonb_build_object('job_no', v_job_no));
  return jsonb_build_object('id', v_job_id, 'job_no', v_job_no);
end $$;

-- 0046's add_job_card_item, plus payload.is_diagnostic = true: adds the
-- agreed diagnostic fee as a labour line.
create or replace function public.add_job_card_item(payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_job      record;
  v_line     record;
  v_item_id  uuid;
  v_line_id  uuid := nullif(payload ->> 'estimate_line_id', '')::uuid;
  v_diag     boolean := coalesce((payload ->> 'is_diagnostic')::boolean, false);
  v_type     text := payload ->> 'item_type';
  v_qty      numeric := coalesce((payload ->> 'quantity')::numeric, 1);
  v_price    numeric := coalesce((payload ->> 'unit_price')::numeric, 0);
  v_gst      numeric := coalesce((payload ->> 'gst_rate')::numeric, 0);
  v_product  uuid := (payload ->> 'product_id')::uuid;
  v_variant  uuid := (payload ->> 'variant_id')::uuid;
  v_service  uuid := (payload ->> 'service_id')::uuid;
  v_name     text := payload ->> 'name';
  v_hsn      text := coalesce(payload ->> 'hsn_code', '');
  v_deduct   boolean;
  v_total    numeric;
begin
  select * into v_job from public.job_cards
    where id = (payload ->> 'job_card_id')::uuid and business_id = v_business for update;
  if v_job is null then raise exception 'Job card not found'; end if;

  if v_diag then
    v_type := 'labor'; v_qty := 1; v_price := v_job.diagnostic_fee;
    v_gst := v_job.diagnostic_gst_rate; v_hsn := v_job.diagnostic_sac;
    v_product := null; v_variant := null; v_service := null; v_line_id := null;
    v_name := 'Diagnostic fee';
  elsif v_line_id is not null then
    select * into v_line from public.job_estimate_lines
      where id = v_line_id and job_card_id = v_job.id;
    if v_line.id is null then raise exception 'Estimate line not found'; end if;
    v_type := v_line.item_type;
    v_price := v_line.unit_price;
    v_gst := v_line.gst_rate;
    v_product := v_line.product_id;
    v_variant := v_line.variant_id;
    v_service := v_line.service_id;
    v_name := v_line.name;
    v_hsn := v_line.hsn_code;
  end if;
  if v_type is null or v_type not in ('part', 'labor') then raise exception 'Invalid item_type'; end if;

  v_total := round(v_qty * v_price * (1 + v_gst / 100), 2);
  v_deduct := v_type = 'part' and v_product is not null;

  insert into public.job_card_items
    (business_id, job_card_id, item_type, product_id, variant_id, service_id, name, hsn_code,
     quantity, unit_price, cost_price, gst_rate, line_total, stock_deducted, estimate_line_id,
     is_diagnostic)
  values
    (v_business, v_job.id, v_type, v_product, v_variant, v_service, v_name, v_hsn,
     v_qty, v_price,
     coalesce((payload ->> 'cost_price')::numeric,
              (select p.purchase_price from public.products p where p.id = v_product), 0),
     v_gst, v_total, v_deduct, v_line_id, v_diag)
  returning id into v_item_id;

  if v_deduct then
    insert into public.stock_movements
      (business_id, product_id, variant_id, movement_type, quantity,
       reference_type, reference_id, created_by)
    values (v_business, v_product, v_variant, 'job_card', -v_qty, 'job_card', v_job.id, auth.uid());
  end if;

  perform public.log_audit('job_card.item_added', 'job_card', v_job.id::text,
    jsonb_build_object('item_type', v_type, 'name', v_name, 'estimate_line_id', v_line_id,
                       'diagnostic', v_diag));
  return jsonb_build_object('id', v_item_id, 'line_total', v_total);
end $$;

-- ============================================================
-- B. Due dates (PD19)
-- ============================================================
create or replace function public.change_invoice_due_date(
  p_invoice uuid, p_due_date date, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v record;
begin
  perform public.assert_can('owner');
  if btrim(coalesce(p_reason, '')) = '' then raise exception 'Give a reason for the change'; end if;
  select * into v from public.invoices
    where id = p_invoice and business_id = public.current_business_id() for update;
  if v.id is null then raise exception 'Bill not found'; end if;
  if v.is_cancelled or v.invoice_type = 'estimate' then
    raise exception 'This bill has no due date to change';
  end if;
  if p_due_date is null or p_due_date < public.ist_date(v.invoice_date) then
    raise exception 'The due date can''t be before the bill date';
  end if;
  update public.invoices set due_date = p_due_date where id = v.id;
  perform public.log_audit('invoice.due_date_changed', 'invoice', v.id::text,
    jsonb_build_object('from', v.due_date, 'to', p_due_date, 'reason', btrim(p_reason)));
end $$;

-- 0049's create_invoice wrapper, plus payload.due_date for a new credit
-- bill (not before the bill date).
create or replace function public.create_invoice(payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v         jsonb;
  v_id      uuid;
  v_pricing jsonb;
  v_ex      jsonb;
  v_item    jsonb;
  v_due     date := nullif(payload ->> 'due_date', '')::date;
begin
  perform set_config('app.doc_date',
    public.ist_date(coalesce(nullif(payload ->> 'invoice_date', '')::timestamptz, now()))::text,
    true);
  v := public.create_invoice_impl(payload);
  perform set_config('app.doc_date', '', true);
  if coalesce((v ->> 'already_synced')::boolean, false) then return v; end if;
  v_id := (v ->> 'id')::uuid;

  if coalesce(payload ->> 'invoice_type', '') <> 'estimate' then
    for v_item in select * from jsonb_array_elements(coalesce(payload -> 'items', '[]'::jsonb)) loop
      if nullif(v_item ->> 'piece_id', '') is not null then
        perform public.cut_piece(
          (v_item ->> 'piece_id')::uuid, (v_item ->> 'product_id')::uuid,
          (v_item ->> 'quantity')::numeric, v_id,
          (v_item ->> 'keep_remnant')::boolean, coalesce(v_item ->> 'remnant_reason', ''),
          not coalesce((payload ->> 'offline_created')::boolean, false));
      end if;
    end loop;

    if v_due is not null then
      if v_due < (select public.ist_date(invoice_date) from public.invoices where id = v_id) then
        raise exception 'The due date can''t be before the bill date';
      end if;
      update public.invoices set due_date = v_due where id = v_id;
    end if;
  end if;

  v_pricing := public.check_invoice_pricing(v_id);
  v_ex := public.sale_exceptions(v_id, v_pricing);
  perform public.settle_sale_exceptions(v_id, payload, v_ex);
  return v;
end $$;

-- ============================================================
-- C. Approval push (PD13)
-- ============================================================
alter table public.sale_approvals add column if not exists notified_at timestamptz;

-- Called with the requesting user's login by the approval-push Edge
-- Function. Returns what to announce, once per request (null otherwise):
-- only a pending request of the caller's own shop, made in the last
-- 10 minutes, and not announced before.
create or replace function public.claim_approval_notification(p_approval uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v record;
begin
  update public.sale_approvals a set notified_at = now()
   where a.id = p_approval and a.business_id = public.current_business_id()
     and a.status = 'pending' and a.notified_at is null
     and a.created_at > now() - interval '10 minutes'
  returning a.* into v;
  if v.id is null then return null; end if;
  return jsonb_build_object(
    'approval_id', v.id,
    'business_id', v.business_id,
    'total', v.total,
    'exceptions', jsonb_array_length(v.exceptions),
    'requested_by', (select full_name from public.profiles where id = v.requested_by),
    'customer', (select name from public.customers where id = v.customer_id));
end $$;

-- ============================================================
-- D. Unit snapshots on bill and purchase lines
-- ============================================================
alter table public.invoice_items add column if not exists alt_unit_name text;
alter table public.invoice_items add column if not exists alt_factor numeric(12,3);
alter table public.purchase_items add column if not exists alt_unit_name text;
alter table public.purchase_items add column if not exists alt_factor numeric(12,3);

create or replace function public.snapshot_line_units()
returns trigger language plpgsql as $$
begin
  if new.product_id is not null and new.alt_unit_name is null then
    new.alt_unit_name := (select nullif(p.secondary_unit_name, '')
                          from public.products p where p.id = new.product_id);
    new.alt_factor := case when new.alt_unit_name is null then null
                           else (select p.conversion_factor from public.products p
                                 where p.id = new.product_id) end;
  end if;
  return new;
end $$;

drop trigger if exists trg_invoice_items_units on public.invoice_items;
create trigger trg_invoice_items_units before insert on public.invoice_items
  for each row execute function public.snapshot_line_units();
drop trigger if exists trg_purchase_items_units on public.purchase_items;
create trigger trg_purchase_items_units before insert on public.purchase_items
  for each row execute function public.snapshot_line_units();

-- ============================================================
-- Grants
-- ============================================================
revoke execute on function public.change_invoice_due_date(uuid, date, text) from public, anon;
revoke execute on function public.claim_approval_notification(uuid) from public, anon;
grant execute on function public.change_invoice_due_date(uuid, date, text) to authenticated;
grant execute on function public.claim_approval_notification(uuid) to authenticated;
