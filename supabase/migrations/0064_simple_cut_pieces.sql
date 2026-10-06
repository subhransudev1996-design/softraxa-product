-- ============================================================
-- 0064_simple_cut_pieces.sql — cut pieces without the paperwork
--
-- Before this, a shop selling rods, pipe, wire or cloth had to type every
-- piece in by hand, keep the pieces in step with stock, and pick a piece
-- at every sale (before even typing the length). Now:
--
--   * Full length (products.piece_length): "1 rod = 12 ft". New stock —
--     opening stock, purchases, imports, stock added by hand — becomes
--     pieces by itself: 120 ft of 12 ft rods is 10 rods; an odd
--     remainder is one shorter piece. Without a full length the new
--     stock is one piece. Only the part of stock not already in pieces
--     is added, so a purchase edit can't double the pieces.
--   * Selling: a bill line of a cut-piece product without a piece_id
--     cuts the best-fitting piece on the server (smallest leftover, same
--     rules as 0049). A length longer than any piece takes whole pieces,
--     longest first, then cuts the rest: 20 ft of 12 ft rods = one whole
--     rod + 8 ft cut from another. Nothing fits → the sale goes through
--     anyway (stock is the truth; pieces are a helper).
--   * match_pieces_to_stock(): one tap on the product page puts the
--     pieces back in step with stock — adds the missing length as pieces,
--     or removes the extra starting from the smallest bits.
--   * Existing cut-piece products with no pieces at all get their stock
--     as pieces now.
--
-- Bill lines that still send a piece_id (older app versions) work as
-- before. Variants don't take part (pieces are per product, as in 0049).
--
-- Run AFTER 0063.
-- ============================================================

alter table public.products add column if not exists piece_length numeric(12,3) not null default 0;
alter table public.products drop constraint if exists products_piece_length_check;
alter table public.products add constraint products_piece_length_check check (piece_length >= 0);

comment on column public.products.piece_length is
  'Full length of one new piece (1 rod = 12 ft → 12) in the base unit; 0 = new stock is one piece.';

-- ------------------------------------------------------------
-- Adds p_len of a product as available pieces, split into full lengths.
-- ------------------------------------------------------------
create or replace function public.add_stock_as_pieces(p_business uuid, p_product uuid, p_len numeric)
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_full  numeric;
  v_count integer;
  v_rest  numeric;
begin
  if coalesce(p_len, 0) <= 0.0005 then return 0; end if;
  select case when piece_length > 0 then piece_length
              when coalesce(btrim(secondary_unit_name), '') <> '' and conversion_factor > 0
                then conversion_factor
              else 0 end
    into v_full
    from public.products where id = p_product and business_id = p_business;

  v_count := case when v_full > 0 then floor((p_len + 0.0005) / v_full)::integer else 0 end;
  -- 0 or absurdly many (a 5000 m coil at a 1 m "length"): one piece.
  if v_count = 0 or v_count > 500 then
    insert into public.stock_pieces (business_id, product_id, length, source, note)
    values (p_business, p_product, round(p_len, 3), 'manual', 'New stock');
    return 1;
  end if;

  insert into public.stock_pieces (business_id, product_id, length, source, note)
  select p_business, p_product, v_full, 'manual', 'New stock' from generate_series(1, v_count);
  v_rest := round(p_len - v_count * v_full, 3);
  if v_rest > 0.0005 then
    insert into public.stock_pieces (business_id, product_id, length, source, note)
    values (p_business, p_product, v_rest, 'manual', 'New stock');
    v_count := v_count + 1;
  end if;
  return v_count;
end $$;

-- Stock that isn't in pieces yet (current stock − available pieces).
create or replace function public.unpieced_stock(p_product uuid)
returns numeric language sql stable security definer set search_path = public as $$
  select round(p.current_stock - coalesce((
           select sum(sp.length) from public.stock_pieces sp
           where sp.product_id = p.id and sp.status = 'available' and sp.variant_id is null), 0), 3)
  from public.products p where p.id = p_product
$$;

-- ------------------------------------------------------------
-- New stock becomes pieces. Runs after trg_apply_stock_movement (name
-- order), so current_stock already includes this movement. Sale returns
-- are left out: return_piece_to_stock (0049) adds the returned piece.
-- ------------------------------------------------------------
create or replace function public.pieces_follow_stock()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_gap numeric;
begin
  if new.quantity <= 0 or new.variant_id is not null
     or new.movement_type in ('sale', 'sale_return', 'damage') then
    return new;
  end if;
  if not exists (select 1 from public.products where id = new.product_id and track_pieces) then
    return new;
  end if;
  v_gap := least(public.unpieced_stock(new.product_id), new.quantity);
  perform public.add_stock_as_pieces(new.business_id, new.product_id, v_gap);
  return new;
end $$;

drop trigger if exists trg_zz_pieces_follow_stock on public.stock_movements;
create trigger trg_zz_pieces_follow_stock after insert on public.stock_movements
  for each row execute function public.pieces_follow_stock();

-- ------------------------------------------------------------
-- A whole piece goes to the customer as it is (no cut, no loss).
-- ------------------------------------------------------------
create or replace function public.sell_whole_piece(p_piece uuid, p_invoice uuid)
returns numeric language plpgsql security definer set search_path = public as $$
declare
  v record;
begin
  update public.stock_pieces set status = 'consumed'
    where id = p_piece and status = 'available'
    returning * into v;
  if v.id is null then return 0; end if;
  insert into public.piece_cuts
    (business_id, product_id, variant_id, source_piece_id, invoice_id, source_length, cut_length,
     loss_length, remnant_length, remnant_status, suggested_status, created_by)
  values
    (v.business_id, v.product_id, v.variant_id, v.id, p_invoice, v.length, v.length, 0, 0,
     'none', 'none', auth.uid());
  return v.length;
end $$;

-- ------------------------------------------------------------
-- Cuts p_qty of a product for a bill from the best pieces (see header).
-- Never fails the sale: what can't be matched to a piece is skipped.
-- ------------------------------------------------------------
create or replace function public.cut_best_pieces(p_product uuid, p_qty numeric, p_invoice uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_left  numeric := p_qty;
  v_best  jsonb;
  v_long  record;
  v_guard integer := 0;
begin
  while v_left > 0.0005 and v_guard < 200 loop
    v_guard := v_guard + 1;
    v_best := public.suggest_pieces(p_product, null, v_left) -> 0;
    if v_best is not null then
      perform public.cut_piece((v_best ->> 'id')::uuid, p_product, v_left, p_invoice,
                               null, '', false);
      return;
    end if;
    -- Longer than any piece: hand over the longest whole piece, cut the rest.
    select id, length into v_long from public.stock_pieces
      where product_id = p_product and variant_id is null and status = 'available'
        and business_id = public.current_business_id()
      order by length desc, created_at limit 1;
    if v_long.id is null or v_long.length >= v_left then
      return;  -- no pieces left (or only ones too short for the allowance)
    end if;
    v_left := round(v_left - public.sell_whole_piece(v_long.id, p_invoice), 3);
  end loop;
end $$;

-- ------------------------------------------------------------
-- Bills cut their pieces (replaces 0061's create_invoice wrapper; only
-- the piece loop changed).
-- ------------------------------------------------------------
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

  perform public.mark_pack_lines(v_id, payload -> 'items');

  if coalesce(payload ->> 'invoice_type', '') <> 'estimate' then
    for v_item in select * from jsonb_array_elements(coalesce(payload -> 'items', '[]'::jsonb)) loop
      if nullif(v_item ->> 'piece_id', '') is not null then
        perform public.cut_piece(
          (v_item ->> 'piece_id')::uuid, (v_item ->> 'product_id')::uuid,
          (v_item ->> 'quantity')::numeric, v_id,
          (v_item ->> 'keep_remnant')::boolean, coalesce(v_item ->> 'remnant_reason', ''),
          not coalesce((payload ->> 'offline_created')::boolean, false));
      elsif nullif(v_item ->> 'variant_id', '') is null
            and nullif(v_item ->> 'product_id', '') is not null
            and coalesce((v_item ->> 'quantity')::numeric, 0) > 0
            and exists (select 1 from public.products
                        where id = (v_item ->> 'product_id')::uuid and track_pieces) then
        perform public.cut_best_pieces((v_item ->> 'product_id')::uuid,
                                       (v_item ->> 'quantity')::numeric, v_id);
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

-- ------------------------------------------------------------
-- One tap: pieces back in step with stock. Returns the change in length
-- (+ added as pieces, − removed from pieces). Stock itself doesn't move.
-- ------------------------------------------------------------
create or replace function public.match_pieces_to_stock(p_product uuid)
returns numeric language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_gap      numeric;
  v_extra    numeric;
  v          record;
begin
  perform public.assert_can('can_manage_stock');
  if not exists (select 1 from public.products
                 where id = p_product and business_id = v_business and track_pieces) then
    raise exception 'This product isn''t sold in cut lengths';
  end if;
  v_gap := public.unpieced_stock(p_product);
  if v_gap > 0.0005 then
    perform public.add_stock_as_pieces(v_business, p_product, v_gap);
  elsif v_gap < -0.0005 then
    -- Pieces add up to more than stock: the missing length went without a
    -- record (sold, damaged). Take it off the smallest bits first.
    v_extra := -v_gap;
    for v in select id, length from public.stock_pieces
             where product_id = p_product and variant_id is null and status = 'available'
             order by length, created_at
             for update loop
      exit when v_extra <= 0.0005;
      if v.length <= v_extra + 0.0005 then
        update public.stock_pieces set status = 'consumed',
          note = btrim(note || ' Matched to stock') where id = v.id;
        v_extra := round(v_extra - v.length, 3);
      else
        update public.stock_pieces set length = round(v.length - v_extra, 3),
          note = btrim(note || ' Matched to stock') where id = v.id;
        v_extra := 0;
      end if;
    end loop;
  else
    return 0;
  end if;
  perform public.log_audit('piece.matched_to_stock', 'product', p_product::text,
    jsonb_build_object('change', v_gap));
  return v_gap;
end $$;

-- ------------------------------------------------------------
-- Existing cut-piece products with stock but no pieces at all.
-- ------------------------------------------------------------
do $$
declare
  p record;
begin
  for p in select pr.id, pr.business_id, pr.current_stock from public.products pr
           where pr.track_pieces and pr.current_stock > 0
             and not exists (select 1 from public.stock_pieces sp
                             where sp.product_id = pr.id and sp.status = 'available') loop
    perform public.add_stock_as_pieces(p.business_id, p.id, p.current_stock);
  end loop;
end $$;

-- ============================================================
-- Grants
-- ============================================================
revoke execute on function public.add_stock_as_pieces(uuid, uuid, numeric) from public, anon, authenticated;
revoke execute on function public.unpieced_stock(uuid) from public, anon, authenticated;
revoke execute on function public.pieces_follow_stock() from public, anon, authenticated;
revoke execute on function public.sell_whole_piece(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.cut_best_pieces(uuid, numeric, uuid) from public, anon, authenticated;
revoke execute on function public.match_pieces_to_stock(uuid) from public, anon;
grant execute on function public.match_pieces_to_stock(uuid) to authenticated;
