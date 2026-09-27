-- ============================================================
-- 0049_cut_pieces.sql — release R1, batch 10
-- (LAUNCH_SPECIFICATION.md D04, D20–D22, D28; PD27, PD39–PD44)
--
-- Linear cut pieces (wire, rods, pipe, cloth) for hardware and
-- electrical shops. Before this, a cut was applied by the app after the
-- bill, as a best-effort extra step. Now the cut is part of the sale:
--
--   * Suggestion (D20, PD39): suggest_pieces() lists available pieces of
--     the same product/variant that fit the cut plus the product's
--     cutting allowance, smallest leftover first. Two short pieces never
--     count as one long one.
--   * Cutting (PD41): a bill line with a piece_id cuts that piece in the
--     same transaction as the sale. The source piece is used up; the
--     cutting allowance is recorded as stock loss; the leftover becomes
--     a new piece linked to its source (lineage), or scrap when it is
--     below the product's minimum reusable length (D21, PD42). Changing
--     that suggestion needs stock permission and a reason (PD43).
--     Scrap and cutting loss leave available stock (movement 'damage').
--   * Billing (D22 default): the bill charges the delivered length. The
--     product's optional cutting charge (PD44) is added by the app as a
--     separate line, once per cut, shown before checkout.
--   * Offline bills: the sale already happened, so a piece that is no
--     longer available is skipped (logged) instead of failing the sync.
--   * Reclassification: reclassify_piece() moves a piece between
--     reusable and scrap with a reason, adjusting stock both ways.
--   * Returns (PD27, D28): cut pieces can't be returned unless the owner
--     allows it for the product; a returned sellable length comes back
--     as its own piece.
--
-- Full-piece billing and customer-owned leftovers are R2 (D22 manual
-- option, D23).
--
-- Run AFTER 0048.
-- ============================================================

-- ============================================================
-- A. Product settings and piece lineage
-- ============================================================
alter table public.products add column if not exists cutting_allowance numeric(12,3) not null default 0;
alter table public.products add column if not exists min_remnant_length numeric(12,3) not null default 0;
alter table public.products add column if not exists cutting_charge numeric(12,2) not null default 0;
alter table public.products add column if not exists allow_piece_returns boolean not null default false;

alter table public.products drop constraint if exists products_cut_settings_check;
alter table public.products add constraint products_cut_settings_check
  check (cutting_allowance >= 0 and min_remnant_length >= 0 and cutting_charge >= 0);

alter table public.stock_pieces add column if not exists parent_piece_id uuid
  references public.stock_pieces(id) on delete set null;
alter table public.stock_pieces add column if not exists source text not null default 'manual';
alter table public.stock_pieces add column if not exists invoice_id uuid
  references public.invoices(id) on delete set null;
alter table public.stock_pieces add column if not exists note text not null default '';

alter table public.stock_pieces drop constraint if exists stock_pieces_source_check;
alter table public.stock_pieces add constraint stock_pieces_source_check
  check (source in ('manual', 'remnant', 'return'));
create index if not exists idx_stock_pieces_parent on public.stock_pieces(parent_piece_id)
  where parent_piece_id is not null;

drop trigger if exists trg_00_tenant_refs on public.stock_pieces;
create trigger trg_00_tenant_refs before insert or update on public.stock_pieces
  for each row execute function public.enforce_tenant_refs(
    'product_id=products', 'variant_id=product_variants', 'parent_piece_id=stock_pieces',
    'invoice_id=invoices');

-- One row per cut: source, what the customer got, loss and leftover.
-- source_length = cut_length + loss_length + remnant_length.
create table if not exists public.piece_cuts (
  id               uuid primary key default gen_random_uuid(),
  business_id      uuid not null references public.businesses(id) on delete cascade,
  product_id       uuid not null references public.products(id) on delete cascade,
  variant_id       uuid references public.product_variants(id) on delete cascade,
  source_piece_id  uuid not null references public.stock_pieces(id) on delete cascade,
  invoice_id       uuid references public.invoices(id) on delete set null,
  source_length    numeric(12,3) not null,
  cut_length       numeric(12,3) not null check (cut_length > 0),
  loss_length      numeric(12,3) not null default 0,
  remnant_length   numeric(12,3) not null default 0,
  remnant_piece_id uuid references public.stock_pieces(id) on delete set null,
  remnant_status   text not null check (remnant_status in ('reusable', 'scrap', 'none')),
  suggested_status text not null check (suggested_status in ('reusable', 'scrap', 'none')),
  reason           text not null default '',
  created_by       uuid references public.profiles(id),
  created_at       timestamptz not null default now()
);
create index if not exists idx_piece_cuts_source on public.piece_cuts(source_piece_id);
create index if not exists idx_piece_cuts_invoice on public.piece_cuts(invoice_id);

alter table public.piece_cuts enable row level security;
drop policy if exists "tenant read" on public.piece_cuts;
create policy "tenant read" on public.piece_cuts for select
  using (business_id = public.current_business_id() or public.is_admin());

drop trigger if exists trg_00_tenant_refs on public.piece_cuts;
create trigger trg_00_tenant_refs before insert or update on public.piece_cuts
  for each row execute function public.enforce_tenant_refs(
    'product_id=products', 'variant_id=product_variants', 'source_piece_id=stock_pieces',
    'invoice_id=invoices', 'remnant_piece_id=stock_pieces');

-- ============================================================
-- B. Suggestion (D20, PD39)
-- ============================================================
-- Available pieces that fit the cut plus the cutting allowance, smallest
-- leftover first. remnant: what would happen to the leftover.
create or replace function public.suggest_pieces(p_product uuid, p_variant uuid, p_cut numeric)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(to_jsonb(s) order by s.leftover, s.created_at), '[]'::jsonb)
  from (
    select sp.id, sp.label, sp.length, sp.source, sp.created_at,
           p.cutting_allowance as allowance,
           round(sp.length - p_cut - p.cutting_allowance, 3) as leftover,
           case when sp.length - p_cut - p.cutting_allowance <= 0.0005 then 'none'
                when sp.length - p_cut - p.cutting_allowance >= p.min_remnant_length then 'reusable'
                else 'scrap' end as remnant
    from public.stock_pieces sp
    join public.products p on p.id = sp.product_id
    where sp.business_id = public.current_business_id()
      and sp.product_id = p_product
      and sp.variant_id is not distinct from p_variant
      and sp.status = 'available'
      and coalesce(p_cut, 0) > 0
      and sp.length + 0.0005 >= p_cut + p.cutting_allowance
  ) s
$$;

-- ============================================================
-- C. Cutting (PD41–PD43)
-- ============================================================
-- Cuts p_cut off a piece for a sale. p_keep: null = follow the
-- suggestion; true/false = keep/scrap the leftover (needs stock
-- permission and a reason when it differs from the suggestion).
-- p_strict = false (offline bills): an unavailable or too-short piece is
-- skipped and logged instead of failing. Returns the cut, or null.
create or replace function public.cut_piece(
  p_piece uuid, p_product uuid, p_cut numeric, p_invoice uuid,
  p_keep boolean default null, p_reason text default '', p_strict boolean default true)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v          record;
  v_problem  text;
  v_loss     numeric;
  v_rem      numeric;
  v_suggest  text;
  v_final    text;
  v_new      uuid;
  v_cut_id   uuid;
begin
  select sp.*, p.name as product_name, p.cutting_allowance, p.min_remnant_length
    into v
    from public.stock_pieces sp join public.products p on p.id = sp.product_id
    where sp.id = p_piece and sp.business_id = v_business
    for update of sp;

  v_problem := case
    when v.id is null then 'Piece not found'
    when v.product_id <> p_product then format('That piece isn''t %s', v.product_name)
    when v.status <> 'available' then format('%s piece "%s" is no longer available — choose another',
                                             v.product_name, v.label)
    when coalesce(p_cut, 0) <= 0 then 'Cut length must be more than 0'
    when v.length + 0.0005 < p_cut + v.cutting_allowance then
      format('%s piece "%s" (%s) is too short for %s plus %s cutting allowance',
             v.product_name, v.label, v.length, p_cut, v.cutting_allowance)
  end;
  if v_problem is not null then
    if p_strict then raise exception '%', v_problem; end if;
    perform public.log_audit('piece.cut_skipped', 'invoice', p_invoice::text,
      jsonb_build_object('piece_id', p_piece, 'cut', p_cut, 'problem', v_problem));
    return null;
  end if;

  v_loss := least(v.cutting_allowance, v.length - p_cut);
  v_rem := round(v.length - p_cut - v_loss, 3);
  if v_rem <= 0.0005 then v_rem := 0; end if;
  v_suggest := case when v_rem = 0 then 'none'
                    when v_rem >= v.min_remnant_length then 'reusable' else 'scrap' end;
  v_final := case when v_rem = 0 then 'none'
                  when p_keep is null then v_suggest
                  when p_keep then 'reusable' else 'scrap' end;
  if v_final <> v_suggest then
    if not public.has_permission('can_manage_stock') then
      raise exception 'Only staff with stock permission can % the leftover of %',
        case when v_final = 'reusable' then 'keep' else 'scrap' end, v.product_name
        using errcode = '42501';
    end if;
    if btrim(coalesce(p_reason, '')) = '' then
      raise exception 'Give a reason for % the leftover (%) of %',
        case when v_final = 'reusable' then 'keeping' else 'scrapping' end, v_rem, v.product_name;
    end if;
  end if;

  update public.stock_pieces set status = 'consumed' where id = v.id;

  if v_rem > 0 then
    insert into public.stock_pieces
      (business_id, product_id, variant_id, label, length, status, parent_piece_id, source,
       invoice_id, note)
    values
      (v_business, v.product_id, v.variant_id, v.label, v_rem,
       case when v_final = 'scrap' then 'scrap' else 'available' end,
       v.id, 'remnant', p_invoice, coalesce(p_reason, ''))
    returning id into v_new;
  end if;

  insert into public.piece_cuts
    (business_id, product_id, variant_id, source_piece_id, invoice_id, source_length, cut_length,
     loss_length, remnant_length, remnant_piece_id, remnant_status, suggested_status, reason,
     created_by)
  values
    (v_business, v.product_id, v.variant_id, v.id, p_invoice, v.length, p_cut, v_loss, v_rem,
     v_new, v_final, v_suggest, coalesce(p_reason, ''), auth.uid())
  returning id into v_cut_id;

  -- Cutting loss and scrap are the shop's stock loss (D22); the sold
  -- length itself was deducted by the bill.
  if v_loss > 0 then
    insert into public.stock_movements
      (business_id, product_id, variant_id, movement_type, quantity, reference_type,
       reference_id, note, created_by)
    values (v_business, v.product_id, v.variant_id, 'damage', -v_loss, 'piece_cut', v_cut_id,
            'Cutting loss', auth.uid());
  end if;
  if v_final = 'scrap' then
    insert into public.stock_movements
      (business_id, product_id, variant_id, movement_type, quantity, reference_type,
       reference_id, note, created_by)
    values (v_business, v.product_id, v.variant_id, 'damage', -v_rem, 'piece_cut', v_cut_id,
            'Offcut scrapped', auth.uid());
  end if;

  return jsonb_build_object('id', v_cut_id, 'loss', v_loss, 'remnant', v_rem,
    'remnant_status', v_final, 'remnant_piece_id', v_new);
end $$;

-- Move a piece between reusable (available) and scrap, with a reason.
create or replace function public.reclassify_piece(p_piece uuid, p_status text, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v record;
begin
  perform public.assert_can('can_manage_stock');
  if p_status not in ('available', 'scrap') then raise exception 'Choose reusable or scrap'; end if;
  if btrim(coalesce(p_reason, '')) = '' then raise exception 'Give a reason'; end if;
  select * into v from public.stock_pieces
    where id = p_piece and business_id = public.current_business_id() for update;
  if v.id is null then raise exception 'Piece not found'; end if;
  if v.status not in ('available', 'scrap') then raise exception 'This piece is already used'; end if;
  if v.status = p_status then return; end if;

  update public.stock_pieces set status = p_status,
    note = btrim(note || ' ' || p_reason) where id = v.id;
  insert into public.stock_movements
    (business_id, product_id, variant_id, movement_type, quantity, reference_type,
     reference_id, note, created_by)
  values (v.business_id, v.product_id, v.variant_id,
          case when p_status = 'scrap' then 'damage' else 'adjustment' end::public.movement_type,
          case when p_status = 'scrap' then -v.length else v.length end,
          'piece', v.id, p_reason, auth.uid());
  perform public.log_audit('piece.reclassified', 'stock_piece', v.id::text,
    jsonb_build_object('status', p_status, 'reason', p_reason, 'length', v.length));
end $$;

-- ============================================================
-- D. Bills cut their pieces (replaces 0048's create_invoice wrapper)
-- ============================================================
-- Bill line fields: piece_id, keep_remnant (optional), remnant_reason.
create or replace function public.create_invoice(payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v         jsonb;
  v_id      uuid;
  v_pricing jsonb;
  v_ex      jsonb;
  v_item    jsonb;
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
  end if;

  v_pricing := public.check_invoice_pricing(v_id);
  v_ex := public.sale_exceptions(v_id, v_pricing);
  perform public.settle_sale_exceptions(v_id, payload, v_ex);
  return v;
end $$;

-- ============================================================
-- E. Returns of cut pieces (PD27, D28)
-- ============================================================
create or replace function public.guard_piece_return()
returns trigger language plpgsql as $$
declare
  v record;
begin
  select track_pieces, allow_piece_returns, name into v
    from public.products where id = new.product_id;
  if coalesce(v.track_pieces, false) and not v.allow_piece_returns then
    raise exception 'Cut pieces of % can''t be returned — the owner can allow returns for this product',
      v.name;
  end if;
  return new;
end $$;

drop trigger if exists trg_sale_return_items_piece on public.sale_return_items;
create trigger trg_sale_return_items_piece before insert on public.sale_return_items
  for each row execute function public.guard_piece_return();

-- A sellable returned length comes back as its own piece.
create or replace function public.return_piece_to_stock()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if coalesce(new.condition, 'sellable') = 'sellable'
     and exists (select 1 from public.products where id = new.product_id and track_pieces) then
    insert into public.stock_pieces
      (business_id, product_id, variant_id, label, length, source, note)
    values (new.business_id, new.product_id, new.variant_id, 'Returned', new.quantity, 'return',
            'Sale return');
  end if;
  return new;
end $$;

drop trigger if exists trg_sale_return_items_piece_stock on public.sale_return_items;
create trigger trg_sale_return_items_piece_stock after insert on public.sale_return_items
  for each row execute function public.return_piece_to_stock();

-- ============================================================
-- Grants
-- ============================================================
revoke execute on function public.suggest_pieces(uuid, uuid, numeric) from public, anon;
revoke execute on function public.cut_piece(uuid, uuid, numeric, uuid, boolean, text, boolean) from public, anon, authenticated;
revoke execute on function public.reclassify_piece(uuid, text, text) from public, anon;
grant execute on function public.suggest_pieces(uuid, uuid, numeric) to authenticated;
grant execute on function public.reclassify_piece(uuid, text, text) to authenticated;
