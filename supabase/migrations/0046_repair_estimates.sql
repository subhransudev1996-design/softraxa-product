-- ============================================================
-- 0046_repair_estimates.sql — release R1, batch 7
-- (LAUNCH_SPECIFICATION.md D37, D38, PD60–PD64)
--
-- Repair estimates with versioned customer approval:
--   * A job card gets a parts-and-labour estimate. Every change makes a
--     new version; an unanswered older version is marked "superseded".
--   * Staff record the customer's answer (D38): who answered, how
--     (in person / phone / WhatsApp / other), when, notes, and optional
--     photos or screenshots. These records are "staff-recorded", never
--     "digitally verified".
--   * Approving version 2 doesn't approve version 3. An answer to a
--     replaced version is refused.
--   * Partial approval (PD61): the customer may approve some lines; only
--     approved lines can be worked on and billed.
--   * Work can't start (in progress / waiting for parts / ready /
--     delivered) until an estimate is approved, and a part or labour line
--     can only be added to the job from the approved estimate, up to the
--     approved quantity and at the approved price. The final bill is built
--     from those lines, so it can't include unapproved extras.
--   * Work already done stays in every later version at the same price;
--     approving a new version moves the done work onto it.
--   * Parts leave stock when marked used on the job (PD63, unchanged).
--   * Photos live in the private Storage bucket "job-attachments" under
--     <business id>/<job card id>/…, readable only by that shop and
--     SOFTRAXA support. They can't be edited or deleted from the app.
--   * Vehicle jobs (PD64): registration number (required), odometer and
--     fuel level; make/model/VIN use the existing brand/model/serial fields.
--
-- Shops that don't do repairs can turn estimates off
-- (businesses.require_repair_estimate). Job cards that existed before
-- this migration are not affected.
--
-- Not in this batch: diagnostic fees (PD59).
--
-- Run AFTER 0045.
-- ============================================================

-- ============================================================
-- A. Settings and job card fields
-- ============================================================
alter table public.businesses
  add column if not exists require_repair_estimate boolean not null default true;

-- Existing job cards keep working as before (false); new ones take the
-- shop's setting (trigger below).
alter table public.job_cards add column if not exists estimate_required boolean not null default false;
alter table public.job_cards add column if not exists job_type text not null default 'device';
alter table public.job_cards add column if not exists registration_no text not null default '';
alter table public.job_cards add column if not exists odometer_km integer;
alter table public.job_cards add column if not exists fuel_level text not null default '';

alter table public.job_cards drop constraint if exists job_cards_job_type_check;
alter table public.job_cards add constraint job_cards_job_type_check
  check (job_type in ('device', 'vehicle'));
alter table public.job_cards drop constraint if exists job_cards_odometer_check;
alter table public.job_cards add constraint job_cards_odometer_check
  check (odometer_km is null or odometer_km >= 0);

-- ============================================================
-- B. Estimates, lines, customer answers, attachments
-- ============================================================
create table if not exists public.job_estimates (
  id           uuid primary key default gen_random_uuid(),
  business_id  uuid not null references public.businesses(id) on delete cascade,
  job_card_id  uuid not null references public.job_cards(id) on delete cascade,
  version      integer not null check (version > 0),
  status       text not null default 'awaiting_approval'
               check (status in ('awaiting_approval', 'approved', 'partially_approved',
                                 'rejected', 'superseded')),
  subtotal     numeric(14,2) not null default 0,
  tax_amount   numeric(14,2) not null default 0,
  total        numeric(14,2) not null default 0,
  note         text not null default '',
  created_by   uuid references public.profiles(id),
  created_at   timestamptz not null default now(),
  decided_at   timestamptz,
  unique (job_card_id, version)
);
create index if not exists idx_job_estimates_job on public.job_estimates(job_card_id, version desc);

-- origin_line_id: the first version's line this one continues (null on a
-- line that is new in its version). Lines are matched across versions by
-- coalesce(origin_line_id, id).
create table if not exists public.job_estimate_lines (
  id              uuid primary key default gen_random_uuid(),
  business_id     uuid not null references public.businesses(id) on delete cascade,
  estimate_id     uuid not null references public.job_estimates(id) on delete cascade,
  job_card_id     uuid not null references public.job_cards(id) on delete cascade,
  line_no         integer not null,
  item_type       text not null check (item_type in ('part', 'labor')),
  product_id      uuid references public.products(id) on delete set null,
  variant_id      uuid references public.product_variants(id) on delete set null,
  service_id      uuid references public.services(id) on delete set null,
  name            text not null,
  hsn_code        text not null default '',
  quantity        numeric(12,3) not null check (quantity > 0),
  unit_price      numeric(12,2) not null check (unit_price >= 0),
  gst_rate        numeric(5,2) not null default 0 check (gst_rate between 0 and 28),
  line_total      numeric(14,2) not null default 0,
  origin_line_id  uuid references public.job_estimate_lines(id) on delete set null,
  approved        boolean not null default false,
  created_at      timestamptz not null default now()
);
create index if not exists idx_job_estimate_lines_estimate on public.job_estimate_lines(estimate_id, line_no);
create unique index if not exists uq_job_estimate_lines_origin
  on public.job_estimate_lines(estimate_id, origin_line_id) where origin_line_id is not null;

create table if not exists public.job_estimate_approvals (
  id                  uuid primary key default gen_random_uuid(),
  business_id         uuid not null references public.businesses(id) on delete cascade,
  job_card_id         uuid not null references public.job_cards(id) on delete cascade,
  estimate_id         uuid not null unique references public.job_estimates(id) on delete cascade,
  decision            text not null check (decision in ('approved', 'partially_approved', 'rejected')),
  approved_total      numeric(14,2) not null default 0,
  customer_name       text not null check (btrim(customer_name) <> ''),
  channel             text not null check (channel in ('in_person', 'phone', 'whatsapp', 'other')),
  customer_decided_at timestamptz not null,
  notes               text not null default '',
  -- D38: always staff-recorded at launch (no customer approval links).
  verification        text not null default 'staff_recorded' check (verification = 'staff_recorded'),
  recorded_by         uuid references public.profiles(id),
  recorded_at         timestamptz not null default now()
);
create index if not exists idx_job_estimate_approvals_job on public.job_estimate_approvals(job_card_id);

create table if not exists public.job_attachments (
  id            uuid primary key default gen_random_uuid(),
  business_id   uuid not null references public.businesses(id) on delete cascade,
  job_card_id   uuid not null references public.job_cards(id) on delete cascade,
  approval_id   uuid references public.job_estimate_approvals(id) on delete set null,
  kind          text not null check (kind in ('approval_evidence', 'intake_photo', 'other')),
  storage_path  text not null unique,
  file_name     text not null default '',
  content_type  text not null default '',
  size_bytes    bigint,
  uploaded_by   uuid references public.profiles(id),
  created_at    timestamptz not null default now()
);
create index if not exists idx_job_attachments_job on public.job_attachments(job_card_id, created_at);

alter table public.job_card_items
  add column if not exists estimate_line_id uuid references public.job_estimate_lines(id) on delete restrict;
create index if not exists idx_job_card_items_estimate_line on public.job_card_items(estimate_line_id)
  where estimate_line_id is not null;

-- Read-only to the shop (and SOFTRAXA support); written only by the
-- functions below, so an answer or estimate can't be edited afterwards.
do $$
declare
  t text;
begin
  foreach t in array array['job_estimates', 'job_estimate_lines', 'job_estimate_approvals',
                           'job_attachments'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "tenant read" on public.%I', t);
    execute format(
      'create policy "tenant read" on public.%I for select
         using (business_id = public.current_business_id() or public.is_admin())', t);
  end loop;
end $$;

drop trigger if exists trg_00_tenant_refs on public.job_estimates;
create trigger trg_00_tenant_refs before insert or update on public.job_estimates
  for each row execute function public.enforce_tenant_refs('job_card_id=job_cards');
drop trigger if exists trg_00_tenant_refs on public.job_estimate_lines;
create trigger trg_00_tenant_refs before insert or update on public.job_estimate_lines
  for each row execute function public.enforce_tenant_refs(
    'estimate_id=job_estimates', 'job_card_id=job_cards', 'product_id=products',
    'variant_id=product_variants', 'service_id=services');
drop trigger if exists trg_00_tenant_refs on public.job_estimate_approvals;
create trigger trg_00_tenant_refs before insert or update on public.job_estimate_approvals
  for each row execute function public.enforce_tenant_refs(
    'job_card_id=job_cards', 'estimate_id=job_estimates');
drop trigger if exists trg_00_tenant_refs on public.job_attachments;
create trigger trg_00_tenant_refs before insert or update on public.job_attachments
  for each row execute function public.enforce_tenant_refs(
    'job_card_id=job_cards', 'approval_id=job_estimate_approvals');
drop trigger if exists trg_00_tenant_refs on public.job_card_items;
create trigger trg_00_tenant_refs before insert or update on public.job_card_items
  for each row execute function public.enforce_tenant_refs(
    'job_card_id=job_cards', 'product_id=products', 'variant_id=product_variants',
    'service_id=services', 'estimate_line_id=job_estimate_lines');

-- ============================================================
-- C. Storage bucket for photos and screenshots
-- ============================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('job-attachments', 'job-attachments', false, 5242880,
        array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'application/pdf'])
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Path: <business id>/<job card id>/<file>. No update or delete policy:
-- evidence can't be replaced or removed from the app.
drop policy if exists "job attachments read" on storage.objects;
create policy "job attachments read" on storage.objects for select to authenticated
  using (bucket_id = 'job-attachments'
         and (split_part(name, '/', 1) = public.current_business_id()::text or public.is_admin()));

drop policy if exists "job attachments upload" on storage.objects;
create policy "job attachments upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'job-attachments'
              and split_part(name, '/', 1) = public.current_business_id()::text
              and public.has_permission('can_manage_services')
              and exists (select 1 from public.job_cards jc
                          where jc.id::text = split_part(name, '/', 2)
                            and jc.business_id = public.current_business_id()));

-- ============================================================
-- D. Rules
-- ============================================================

-- The version work may be done and billed against: the newest approved
-- (fully or partly) version. A newer version still awaiting an answer
-- doesn't count.
create or replace function public.current_job_estimate(p_job uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select e.id from public.job_estimates e
  where e.job_card_id = p_job and e.status in ('approved', 'partially_approved')
  order by e.version desc limit 1
$$;

create or replace function public.guard_job_card_estimate()
returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    new.estimate_required := coalesce(
      (select b.require_repair_estimate from public.businesses b where b.id = new.business_id), true);
  else
    new.estimate_required := old.estimate_required;
  end if;

  new.registration_no := upper(regexp_replace(coalesce(new.registration_no, ''), '\s', '', 'g'));
  if new.job_type = 'vehicle' and new.registration_no = ''
     and (tg_op = 'INSERT' or new.registration_no is distinct from old.registration_no
          or new.job_type is distinct from old.job_type) then
    raise exception 'Enter the vehicle''s registration number';
  end if;

  if tg_op = 'UPDATE' and new.estimate_required
     and new.status is distinct from old.status
     and new.status in ('in_progress', 'waiting_parts', 'ready', 'delivered')
     and public.current_job_estimate(new.id) is null then
    raise exception 'Record the customer''s approval of the estimate before starting work on job %',
      new.job_no;
  end if;
  return new;
end $$;

drop trigger if exists trg_job_cards_estimate on public.job_cards;
create trigger trg_job_cards_estimate before insert or update on public.job_cards
  for each row execute function public.guard_job_card_estimate();

-- On a job that needs an estimate, every part/labour line must come from
-- the approved estimate: same item and price, within the approved quantity.
create or replace function public.guard_job_item_scope()
returns trigger language plpgsql as $$
declare
  v_required boolean;
  v_line     record;
  v_used     numeric;
begin
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

drop trigger if exists trg_job_card_items_scope on public.job_card_items;
create trigger trg_job_card_items_scope before insert or update on public.job_card_items
  for each row execute function public.guard_job_item_scope();

-- ============================================================
-- E. Functions
-- ============================================================

-- Make a new estimate version. p_lines: [{item_type, name, quantity,
-- unit_price, gst_rate, product_id?, variant_id?, service_id?, hsn_code?,
-- from_line_id?}] — from_line_id is the line of an earlier version this
-- one continues (kept when editing an estimate).
create or replace function public.create_job_estimate(
  p_job_id uuid, p_lines jsonb, p_note text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business  uuid := public.current_business_id();
  v_job       record;
  v_version   integer;
  v_est       uuid;
  v_current   uuid;
  v_line      jsonb;
  v_i         integer := 0;
  v_type      text;
  v_name      text;
  v_qty       numeric;
  v_price     numeric;
  v_gst       numeric;
  v_product   uuid;
  v_variant   uuid;
  v_from      uuid;
  v_origin    uuid;
  v_total     numeric;
  v_sub       numeric := 0;
  v_tax       numeric := 0;
  v_done      record;
  v_new       record;
  v_status    public.job_status;
begin
  perform public.assert_can('can_manage_services');
  select * into v_job from public.job_cards
    where id = p_job_id and business_id = v_business for update;
  if v_job.id is null then raise exception 'Job card not found'; end if;
  if v_job.invoice_id is not null
     or v_job.status in ('delivered', 'cancelled', 'returned_unrepaired') then
    raise exception 'Job % is closed', v_job.job_no;
  end if;
  if jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'Add at least one part or labour line to the estimate';
  end if;

  select coalesce(max(version), 0) + 1 into v_version
    from public.job_estimates where job_card_id = p_job_id;
  update public.job_estimates set status = 'superseded'
    where job_card_id = p_job_id and status = 'awaiting_approval';
  insert into public.job_estimates (business_id, job_card_id, version, note, created_by)
    values (v_business, p_job_id, v_version, coalesce(p_note, ''), auth.uid())
    returning id into v_est;
  v_current := public.current_job_estimate(p_job_id);

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_i := v_i + 1;
    v_type := v_line ->> 'item_type';
    v_name := btrim(coalesce(v_line ->> 'name', ''));
    v_qty := coalesce((v_line ->> 'quantity')::numeric, 1);
    v_price := coalesce((v_line ->> 'unit_price')::numeric, 0);
    v_gst := coalesce((v_line ->> 'gst_rate')::numeric, 0);
    v_product := nullif(v_line ->> 'product_id', '')::uuid;
    v_variant := nullif(v_line ->> 'variant_id', '')::uuid;
    v_from := nullif(v_line ->> 'from_line_id', '')::uuid;
    if v_type is null or v_type not in ('part', 'labor') then
      raise exception 'Line %: choose part or labour', v_i;
    end if;
    if v_name = '' then raise exception 'Line %: enter a name', v_i; end if;
    if v_qty <= 0 then raise exception 'Line % (%): quantity must be more than 0', v_i, v_name; end if;
    if v_price < 0 then raise exception 'Line % (%): price can''t be negative', v_i, v_name; end if;
    if v_type = 'part' then
      -- Customer approval doesn't waive the shop's own price rules.
      perform public.check_line_price(v_product, v_variant, v_qty, v_price, 0, v_gst, v_gst > 0, v_name);
    end if;
    v_origin := null;
    if v_from is not null then
      select coalesce(l.origin_line_id, l.id) into v_origin from public.job_estimate_lines l
        where l.id = v_from and l.job_card_id = p_job_id;
      if v_origin is null then raise exception 'Line % (%): unknown earlier line', v_i, v_name; end if;
    end if;
    v_total := round(v_qty * v_price * (1 + v_gst / 100), 2);
    insert into public.job_estimate_lines
      (business_id, estimate_id, job_card_id, line_no, item_type, product_id, variant_id,
       service_id, name, hsn_code, quantity, unit_price, gst_rate, line_total, origin_line_id)
    values
      (v_business, v_est, p_job_id, v_i, v_type, v_product, v_variant,
       nullif(v_line ->> 'service_id', '')::uuid, v_name, coalesce(v_line ->> 'hsn_code', ''),
       v_qty, v_price, v_gst, v_total, v_origin);
    v_sub := v_sub + round(v_qty * v_price, 2);
    v_tax := v_tax + (v_total - round(v_qty * v_price, 2));
  end loop;

  -- Work already done under the approved estimate stays, unchanged in
  -- price, with at least the quantity already used.
  if v_current is not null then
    for v_done in
      select l.id, coalesce(l.origin_line_id, l.id) as origin, l.name, l.item_type, l.product_id,
             l.variant_id, l.unit_price, l.gst_rate, sum(i.quantity) as used
      from public.job_estimate_lines l
      join public.job_card_items i on i.estimate_line_id = l.id
      where l.estimate_id = v_current
      group by l.id
    loop
      select * into v_new from public.job_estimate_lines n
        where n.estimate_id = v_est and n.origin_line_id = v_done.origin;
      if v_new.id is null or v_new.quantity < v_done.used
         or v_new.unit_price <> v_done.unit_price or v_new.gst_rate <> v_done.gst_rate
         or v_new.item_type <> v_done.item_type
         or v_new.product_id is distinct from v_done.product_id
         or v_new.variant_id is distinct from v_done.variant_id then
        raise exception '"%" is already done (% used) — keep it in the new estimate at the same price',
          v_done.name, v_done.used;
      end if;
    end loop;
  end if;

  update public.job_estimates set subtotal = v_sub, tax_amount = v_tax, total = v_sub + v_tax
    where id = v_est;

  v_status := case when v_job.status in ('received', 'checking', 'estimate_given')
                   then 'waiting_approval'::public.job_status else v_job.status end;
  update public.job_cards set estimated_cost = v_sub + v_tax, status = v_status where id = p_job_id;
  insert into public.job_status_history (business_id, job_card_id, status, note, created_by)
    values (v_business, p_job_id, v_status,
            format('Estimate version %s: %s', v_version, v_sub + v_tax), auth.uid());

  perform public.log_audit('job_estimate.created', 'job_card', p_job_id::text,
    jsonb_build_object('estimate_id', v_est, 'version', v_version, 'total', v_sub + v_tax));
  return jsonb_build_object('id', v_est, 'version', v_version, 'total', v_sub + v_tax);
end $$;

-- Record the customer's answer to the latest estimate version (D38).
-- p_decision: 'approved' (p_line_ids null = every line, else only those
-- lines — PD61) or 'rejected'.
create or replace function public.record_estimate_decision(
  p_estimate_id uuid, p_decision text, p_customer_name text, p_channel text,
  p_line_ids uuid[] default null, p_decided_at timestamptz default null, p_notes text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business  uuid := public.current_business_id();
  v_est       record;
  v_job       record;
  v_latest    integer;
  v_prev      uuid;
  v_when      timestamptz := coalesce(p_decided_at, now());
  v_decision  text;
  v_total     numeric := 0;
  v_approval  uuid;
  v_done      record;
  v_status    public.job_status;
begin
  perform public.assert_can('can_manage_services');
  select e.job_card_id into v_est from public.job_estimates e
    where e.id = p_estimate_id and e.business_id = v_business;
  if v_est.job_card_id is null then raise exception 'Estimate not found'; end if;
  select * into v_job from public.job_cards where id = v_est.job_card_id for update;
  select * into v_est from public.job_estimates where id = p_estimate_id;

  if v_est.status <> 'awaiting_approval' then
    select max(version) into v_latest from public.job_estimates where job_card_id = v_job.id;
    if v_est.status = 'superseded' then
      raise exception 'Version % was replaced by version % — record the customer''s answer on the latest estimate',
        v_est.version, v_latest;
    end if;
    raise exception 'The customer''s answer to version % is already recorded', v_est.version;
  end if;
  if btrim(coalesce(p_customer_name, '')) = '' then
    raise exception 'Enter the name of the person who gave the answer';
  end if;
  if p_channel is null or p_channel not in ('in_person', 'phone', 'whatsapp', 'other') then
    raise exception 'Choose how the customer answered';
  end if;
  if v_when > now() + interval '5 minutes' then
    raise exception 'The answer time can''t be in the future';
  end if;
  if v_when < v_est.created_at - interval '1 minute' then
    raise exception 'The answer time is before the estimate was made';
  end if;

  if p_decision = 'rejected' then
    v_decision := 'rejected';
  elsif p_decision = 'approved' then
    if p_line_ids is not null then
      if cardinality(p_line_ids) = 0 then
        raise exception 'Choose at least one line the customer approved';
      end if;
      if exists (select 1 from unnest(p_line_ids) x
                 where not exists (select 1 from public.job_estimate_lines l
                                   where l.id = x and l.estimate_id = p_estimate_id)) then
        raise exception 'A chosen line is not part of this estimate';
      end if;
    end if;
    update public.job_estimate_lines set approved = (p_line_ids is null or id = any(p_line_ids))
      where estimate_id = p_estimate_id;

    -- Work already done under the previous approval stays approved.
    v_prev := public.current_job_estimate(v_job.id);
    if v_prev is not null then
      for v_done in
        select l.id, coalesce(l.origin_line_id, l.id) as origin, l.name
        from public.job_estimate_lines l
        where l.estimate_id = v_prev
          and exists (select 1 from public.job_card_items i where i.estimate_line_id = l.id)
      loop
        if not exists (select 1 from public.job_estimate_lines n
                       where n.estimate_id = p_estimate_id and n.origin_line_id = v_done.origin
                         and n.approved) then
          raise exception '"%" is already done — it must stay approved', v_done.name;
        end if;
      end loop;
    end if;

    v_decision := case when exists (select 1 from public.job_estimate_lines
                                    where estimate_id = p_estimate_id and not approved)
                       then 'partially_approved' else 'approved' end;
    select coalesce(sum(line_total), 0) into v_total from public.job_estimate_lines
      where estimate_id = p_estimate_id and approved;
  else
    raise exception 'Unknown answer %', p_decision;
  end if;

  update public.job_estimates set status = v_decision, decided_at = now() where id = p_estimate_id;

  -- Move work already done onto the newly approved version.
  if v_decision <> 'rejected' and v_prev is not null then
    update public.job_card_items i set estimate_line_id = n.id
      from public.job_estimate_lines o, public.job_estimate_lines n
      where i.estimate_line_id = o.id and o.estimate_id = v_prev
        and n.estimate_id = p_estimate_id and n.origin_line_id = coalesce(o.origin_line_id, o.id);
  end if;

  insert into public.job_estimate_approvals
    (business_id, job_card_id, estimate_id, decision, approved_total, customer_name, channel,
     customer_decided_at, notes, recorded_by)
  values
    (v_business, v_job.id, p_estimate_id, v_decision, v_total, btrim(p_customer_name), p_channel,
     v_when, coalesce(p_notes, ''), auth.uid())
  returning id into v_approval;

  v_status := v_job.status;
  if v_decision <> 'rejected' then
    if v_job.status in ('received', 'checking', 'estimate_given', 'waiting_approval') then
      v_status := 'in_progress';
    end if;
    update public.job_cards set status = v_status, estimated_cost = v_total where id = v_job.id;
  end if;
  insert into public.job_status_history (business_id, job_card_id, status, note, created_by)
    values (v_business, v_job.id, v_status,
            format('Estimate version %s %s by %s (%s, staff-recorded)', v_est.version,
                   replace(v_decision, '_', ' '), btrim(p_customer_name), replace(p_channel, '_', ' ')),
            auth.uid());

  perform public.log_audit('job_estimate.' || v_decision, 'job_card', v_job.id::text,
    jsonb_build_object('estimate_id', p_estimate_id, 'version', v_est.version,
                       'approved_total', v_total, 'channel', p_channel));
  return jsonb_build_object('id', v_approval, 'decision', v_decision, 'approved_total', v_total);
end $$;

-- Register a file already uploaded to the job-attachments bucket.
create or replace function public.add_job_attachment(
  p_job_id uuid, p_path text, p_kind text, p_file_name text default '',
  p_content_type text default '', p_size bigint default null, p_approval_id uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_id       uuid;
begin
  perform public.assert_can('can_manage_services');
  if not exists (select 1 from public.job_cards where id = p_job_id and business_id = v_business) then
    raise exception 'Job card not found';
  end if;
  if p_kind is null or p_kind not in ('approval_evidence', 'intake_photo', 'other') then
    raise exception 'Unknown attachment type %', p_kind;
  end if;
  if p_path is null or p_path not like v_business::text || '/' || p_job_id::text || '/%' then
    raise exception 'This file doesn''t belong to this job';
  end if;
  if not exists (select 1 from storage.objects
                 where bucket_id = 'job-attachments' and name = p_path) then
    raise exception 'Upload the file before attaching it';
  end if;
  if p_approval_id is not null then
    if p_kind <> 'approval_evidence' or not exists (
         select 1 from public.job_estimate_approvals
         where id = p_approval_id and job_card_id = p_job_id) then
      raise exception 'This evidence doesn''t match the customer''s answer on this job';
    end if;
  end if;

  insert into public.job_attachments
    (business_id, job_card_id, approval_id, kind, storage_path, file_name, content_type,
     size_bytes, uploaded_by)
  values (v_business, p_job_id, p_approval_id, p_kind, p_path, coalesce(p_file_name, ''),
          coalesce(p_content_type, ''), p_size, auth.uid())
  returning id into v_id;
  perform public.log_audit('job_card.attachment_added', 'job_card', p_job_id::text,
    jsonb_build_object('kind', p_kind, 'approval_id', p_approval_id));
  return v_id;
end $$;

-- 0017's add_job_card_item, now also taking estimate_line_id: the line's
-- item, name and price are used (the payload's are ignored).
create or replace function public.add_job_card_item(payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_job      record;
  v_line     record;
  v_item_id  uuid;
  v_line_id  uuid := nullif(payload ->> 'estimate_line_id', '')::uuid;
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

  if v_line_id is not null then
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
     quantity, unit_price, cost_price, gst_rate, line_total, stock_deducted, estimate_line_id)
  values
    (v_business, v_job.id, v_type, v_product, v_variant, v_service, v_name, v_hsn,
     v_qty, v_price,
     coalesce((payload ->> 'cost_price')::numeric,
              (select p.purchase_price from public.products p where p.id = v_product), 0),
     v_gst, v_total, v_deduct, v_line_id)
  returning id into v_item_id;

  if v_deduct then
    insert into public.stock_movements
      (business_id, product_id, variant_id, movement_type, quantity,
       reference_type, reference_id, created_by)
    values (v_business, v_product, v_variant, 'job_card', -v_qty, 'job_card', v_job.id, auth.uid());
  end if;

  perform public.log_audit('job_card.item_added', 'job_card', v_job.id::text,
    jsonb_build_object('item_type', v_type, 'name', v_name, 'estimate_line_id', v_line_id));
  return jsonb_build_object('id', v_item_id, 'line_total', v_total);
end $$;

-- 0027's create_job_card plus the vehicle fields.
create or replace function public.create_job_card(payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_job_id   uuid;
  v_job_no   text;
begin
  if v_business is null then raise exception 'No business for current user'; end if;
  v_job_no := public.next_doc_no(v_business, 'job_card', 'JOB');

  insert into public.job_cards
    (business_id, job_no, customer_id, customer_name, customer_phone, item_name, brand, model,
     serial_no, issue_description, item_condition, accessories_received, technician_name,
     estimated_cost, advance_amount, advance_mode, expected_delivery, customer_note,
     internal_note, warranty_days, service_location, job_type, registration_no, odometer_km,
     fuel_level, created_by)
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
     coalesce(payload ->> 'fuel_level', ''), auth.uid())
  returning id into v_job_id;

  insert into public.job_status_history (business_id, job_card_id, status, note, created_by)
  values (v_business, v_job_id, 'received', 'Job card created', auth.uid());

  perform public.log_audit('job_card.created', 'job_card', v_job_id::text,
    jsonb_build_object('job_no', v_job_no));
  return jsonb_build_object('id', v_job_id, 'job_no', v_job_no);
end $$;

-- ============================================================
-- Grants
-- ============================================================
revoke execute on function public.current_job_estimate(uuid) from public, anon;
revoke execute on function public.create_job_estimate(uuid, jsonb, text) from public, anon;
revoke execute on function public.record_estimate_decision(uuid, text, text, text, uuid[], timestamptz, text) from public, anon;
revoke execute on function public.add_job_attachment(uuid, text, text, text, text, bigint, uuid) from public, anon;
grant execute on function public.current_job_estimate(uuid) to authenticated;
grant execute on function public.create_job_estimate(uuid, jsonb, text) to authenticated;
grant execute on function public.record_estimate_decision(uuid, text, text, text, uuid[], timestamptz, text) to authenticated;
grant execute on function public.add_job_attachment(uuid, text, text, text, text, bigint, uuid) to authenticated;
