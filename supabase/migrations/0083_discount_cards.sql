-- ============================================================
-- 0083_discount_cards.sql
--
-- Discount cards (privilege / membership cards), like a bookshop's
-- "Privilege Card": the customer shows the card and gets an extra
-- discount.
--
--   * Card types (owner): a name ("Gold"), a discount % and what it
--     covers — every item, only some categories, or all but some.
--   * Cards (owner, or staff who may change prices): the number printed
--     on the card, its type, optionally who it was given to and until
--     when it is valid. Cards are often transferable, so the discount
--     follows the card, not the customer.
--   * At billing the card is found by its full number or by its ending
--     (find_discount_card); the app takes the card's % off the covered
--     lines. The bill records the card (number, type, % and amount).
--   * The card's discount is an allowed discount: it doesn't count
--     towards a staff member's discount limit (0043/0044), so a cashier
--     with no discount rights can still honour the card.
--
-- Card numbers are matched without spaces, dashes or case ("2017 1234"
-- = "20171234"). Bills made offline are accepted with a card that was
-- valid when they were made (no expiry check when they sync).
--
-- Run AFTER 0082.
-- ============================================================

-- ============================================================
-- A. Tables
-- ============================================================
create or replace function public.card_key(p text)
returns text language sql immutable as $$
  select upper(regexp_replace(coalesce(p, ''), '[^0-9A-Za-z]', '', 'g'));
$$;

create table if not exists public.discount_card_types (
  id           uuid primary key default gen_random_uuid(),
  business_id  uuid not null references public.businesses(id) on delete cascade,
  name         text not null check (btrim(name) <> '' and char_length(name) <= 60),
  discount_pct numeric(5,2) not null check (discount_pct > 0 and discount_pct <= 100),
  applies_to   text not null default 'all' check (applies_to in ('all', 'only', 'except')),
  category_ids uuid[] not null default '{}',
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create unique index if not exists uq_discount_card_types_name
  on public.discount_card_types (business_id, lower(btrim(name)));

create table if not exists public.discount_cards (
  id           uuid primary key default gen_random_uuid(),
  business_id  uuid not null references public.businesses(id) on delete cascade,
  card_type_id uuid not null references public.discount_card_types(id) on delete restrict,
  card_no      text not null check (btrim(card_no) <> '' and char_length(card_no) <= 40),
  card_key     text not null,
  customer_id  uuid references public.customers(id) on delete set null,
  holder_name  text not null default '' check (char_length(holder_name) <= 100),
  valid_until  date,
  is_active    boolean not null default true,
  notes        text not null default '' check (char_length(notes) <= 300),
  created_by   uuid references public.profiles(id),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create unique index if not exists uq_discount_cards_key
  on public.discount_cards (business_id, card_key);
create index if not exists idx_discount_cards_type on public.discount_cards (card_type_id);

create or replace function public.stamp_discount_card()
returns trigger language plpgsql as $$
begin
  new.card_no := btrim(new.card_no);
  new.card_key := public.card_key(new.card_no);
  if char_length(new.card_key) < 3 then
    raise exception 'A card number needs at least 3 letters or digits';
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists trg_discount_cards_stamp on public.discount_cards;
create trigger trg_discount_cards_stamp before insert or update on public.discount_cards
  for each row execute function public.stamp_discount_card();

drop trigger if exists trg_00_tenant_refs on public.discount_cards;
create trigger trg_00_tenant_refs before insert or update on public.discount_cards
  for each row execute function public.enforce_tenant_refs(
    'customer_id=customers', 'card_type_id=discount_card_types');

-- Reads for everyone in the shop; writes only through the functions below.
alter table public.discount_card_types enable row level security;
alter table public.discount_cards enable row level security;
drop policy if exists "tenant read" on public.discount_card_types;
drop policy if exists "admin all" on public.discount_card_types;
create policy "tenant read" on public.discount_card_types for select
  using (business_id = (select public.current_business_id()));
create policy "admin all" on public.discount_card_types for all
  using (public.is_admin()) with check (public.is_admin());
drop policy if exists "tenant read" on public.discount_cards;
drop policy if exists "admin all" on public.discount_cards;
create policy "tenant read" on public.discount_cards for select
  using (business_id = (select public.current_business_id()));
create policy "admin all" on public.discount_cards for all
  using (public.is_admin()) with check (public.is_admin());

-- The card on a bill, as it was when billed.
alter table public.invoices
  add column if not exists discount_card_id     uuid references public.discount_cards(id) on delete set null,
  add column if not exists discount_card_no     text not null default '',
  add column if not exists discount_card_type   text not null default '',
  add column if not exists discount_card_pct    numeric(5,2) not null default 0,
  add column if not exists discount_card_amount numeric(12,2) not null default 0;

-- Only the bill functions set these (they turn the switch on).
create or replace function public.guard_invoice_card()
returns trigger language plpgsql as $$
begin
  if coalesce(current_setting('app.card_ok', true), '') = 'on' then return new; end if;
  if tg_op = 'INSERT' then
    if new.discount_card_id is not null or new.discount_card_pct <> 0
       or new.discount_card_amount <> 0 then
      raise exception 'A discount card is added to a bill only through billing';
    end if;
  elsif (new.discount_card_id, new.discount_card_no, new.discount_card_type,
         new.discount_card_pct, new.discount_card_amount)
        is distinct from
        (old.discount_card_id, old.discount_card_no, old.discount_card_type,
         old.discount_card_pct, old.discount_card_amount) then
    raise exception 'A discount card is added to a bill only through billing';
  end if;
  return new;
end $$;
drop trigger if exists trg_invoices_card_guard on public.invoices;
create trigger trg_invoices_card_guard before insert or update on public.invoices
  for each row execute function public.guard_invoice_card();

-- ============================================================
-- B. Managing types and cards
-- ============================================================
create or replace function public.save_discount_card_type(p_id uuid, p jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_name     text := btrim(coalesce(p ->> 'name', ''));
  v_pct      numeric := (p ->> 'discount_pct')::numeric;
  v_applies  text := coalesce(nullif(p ->> 'applies_to', ''), 'all');
  v_cats     uuid[] := coalesce(
    (select array_agg(distinct x::uuid) from jsonb_array_elements_text(
       coalesce(p -> 'category_ids', '[]'::jsonb)) x), '{}');
  v_id       uuid;
begin
  perform public.assert_can('owner');
  if v_name = '' then raise exception 'Give the card type a name, like Gold or Student'; end if;
  if v_pct is null or v_pct <= 0 or v_pct > 100 then
    raise exception 'The discount must be more than 0%% and at most 100%%';
  end if;
  if v_applies not in ('all', 'only', 'except') then raise exception 'Unknown choice: %', v_applies; end if;
  if v_applies = 'all' then v_cats := '{}'; end if;
  if v_applies <> 'all' and cardinality(v_cats) = 0 then
    raise exception 'Choose at least one category';
  end if;
  if exists (select 1 from unnest(v_cats) c
             where not exists (select 1 from public.categories k
                               where k.id = c and k.business_id = v_business)) then
    raise exception 'A chosen category is not in this shop';
  end if;
  if exists (select 1 from public.discount_card_types
             where business_id = v_business and lower(btrim(name)) = lower(v_name)
               and id is distinct from p_id) then
    raise exception 'There is already a card type called "%"', v_name;
  end if;

  if p_id is null then
    insert into public.discount_card_types (business_id, name, discount_pct, applies_to, category_ids, is_active)
    values (v_business, v_name, round(v_pct, 2), v_applies, v_cats,
            coalesce((p ->> 'is_active')::boolean, true))
    returning id into v_id;
  else
    update public.discount_card_types set
      name = v_name, discount_pct = round(v_pct, 2), applies_to = v_applies,
      category_ids = v_cats, is_active = coalesce((p ->> 'is_active')::boolean, is_active),
      updated_at = now()
    where id = p_id and business_id = v_business
    returning id into v_id;
    if v_id is null then raise exception 'Card type not found'; end if;
  end if;
  perform public.log_audit(case when p_id is null then 'discount_card_type.created'
                                else 'discount_card_type.updated' end,
    'discount_card_type', v_id::text,
    jsonb_build_object('name', v_name, 'discount_pct', round(v_pct, 2),
                       'applies_to', v_applies, 'category_ids', to_jsonb(v_cats)));
  return v_id;
end $$;

create or replace function public.save_discount_card(p_id uuid, p jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_no       text := btrim(coalesce(p ->> 'card_no', ''));
  v_type     uuid := nullif(p ->> 'card_type_id', '')::uuid;
  v_customer uuid := nullif(p ->> 'customer_id', '')::uuid;
  v_other    text;
  v_id       uuid;
begin
  perform public.assert_can('can_edit_prices');
  if char_length(public.card_key(v_no)) < 3 then
    raise exception 'Enter the card number (at least 3 letters or digits)';
  end if;
  if v_type is null or not exists (select 1 from public.discount_card_types
                                   where id = v_type and business_id = v_business) then
    raise exception 'Choose the card type';
  end if;
  if p_id is null and not exists (select 1 from public.discount_card_types
                                  where id = v_type and is_active) then
    raise exception 'That card type is switched off';
  end if;
  select card_no into v_other from public.discount_cards
    where business_id = v_business and card_key = public.card_key(v_no) and id is distinct from p_id;
  if v_other is not null then raise exception 'Card % is already in the list', v_other; end if;

  if p_id is null then
    insert into public.discount_cards (business_id, card_type_id, card_no, card_key, customer_id,
                                       holder_name, valid_until, is_active, notes, created_by)
    values (v_business, v_type, v_no, public.card_key(v_no), v_customer,
            btrim(coalesce(p ->> 'holder_name', '')), nullif(p ->> 'valid_until', '')::date,
            coalesce((p ->> 'is_active')::boolean, true), btrim(coalesce(p ->> 'notes', '')),
            auth.uid())
    returning id into v_id;
  else
    update public.discount_cards set
      card_type_id = v_type, card_no = v_no, customer_id = v_customer,
      holder_name = btrim(coalesce(p ->> 'holder_name', '')),
      valid_until = nullif(p ->> 'valid_until', '')::date,
      is_active = coalesce((p ->> 'is_active')::boolean, is_active),
      notes = btrim(coalesce(p ->> 'notes', ''))
    where id = p_id and business_id = v_business
    returning id into v_id;
    if v_id is null then raise exception 'Card not found'; end if;
  end if;
  perform public.log_audit(case when p_id is null then 'discount_card.created'
                                else 'discount_card.updated' end,
    'discount_card', v_id::text, jsonb_build_object('card_no', v_no, 'card_type_id', v_type));
  return v_id;
end $$;

-- Types and cards for the management screen, with how often each card was
-- used and the discount it gave.
create or replace function public.get_discount_cards(p_search text default '', p_limit integer default 300)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_key      text := public.card_key(p_search);
  v_text     text := lower(btrim(coalesce(p_search, '')));
begin
  if v_business is null then raise exception 'No shop selected'; end if;
  return jsonb_build_object(
    'types', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', t.id, 'name', t.name, 'discount_pct', t.discount_pct,
               'applies_to', t.applies_to, 'category_ids', to_jsonb(t.category_ids),
               'is_active', t.is_active,
               'cards', (select count(*) from public.discount_cards c where c.card_type_id = t.id))
             order by t.is_active desc, t.name)
      from public.discount_card_types t where t.business_id = v_business), '[]'::jsonb),
    'cards', coalesce((
      select jsonb_agg(row_to_json(r)::jsonb order by r.created_at desc)
      from (
        select c.id, c.card_no, c.card_type_id, t.name as type_name, t.discount_pct,
               c.customer_id, cu.name as customer_name, c.holder_name, c.valid_until,
               c.is_active, c.notes, c.created_at,
               (select count(*) from public.invoices i
                where i.discount_card_id = c.id and not i.is_cancelled) as uses,
               (select coalesce(sum(i.discount_card_amount), 0) from public.invoices i
                where i.discount_card_id = c.id and not i.is_cancelled) as discount_given
        from public.discount_cards c
        join public.discount_card_types t on t.id = c.card_type_id
        left join public.customers cu on cu.id = c.customer_id
        where c.business_id = v_business
          and (v_text = '' or c.card_key like '%' || v_key || '%'
               or lower(c.holder_name) like '%' || v_text || '%'
               or lower(coalesce(cu.name, '')) like '%' || v_text || '%')
        order by c.created_at desc
        limit least(greatest(coalesce(p_limit, 300), 1), 1000)) r), '[]'::jsonb));
end $$;

-- ============================================================
-- C. Finding a card at billing
-- ============================================================
-- By its full number, or by its ending when only one card ends that way
-- (cards often share a printed pattern, like "2017 1234 1234 4109").
-- {found:false} when there is none, so the app can offer to add it.
create or replace function public.find_discount_card(p_query text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_key      text := public.card_key(p_query);
  v_ids      uuid[];
  c          record;
  v_problem  text := '';
begin
  if v_business is null then raise exception 'No shop selected'; end if;
  if char_length(v_key) < 3 then raise exception 'Type at least 3 letters or digits of the card number'; end if;

  select array_agg(id) into v_ids from public.discount_cards
    where business_id = v_business and card_key = v_key;
  if v_ids is null then
    select array_agg(id) into v_ids from (
      select id from public.discount_cards
      where business_id = v_business and card_key like '%' || v_key limit 2) x;
  end if;
  if v_ids is null then return jsonb_build_object('found', false, 'query', btrim(p_query)); end if;
  if cardinality(v_ids) > 1 then
    raise exception 'More than one card ends with %: type more of the number', btrim(p_query);
  end if;

  select d.*, t.name as type_name, t.discount_pct, t.applies_to, t.category_ids,
         t.is_active as type_active, cu.name as customer_name
    into c
  from public.discount_cards d
  join public.discount_card_types t on t.id = d.card_type_id
  left join public.customers cu on cu.id = d.customer_id
  where d.id = v_ids[1];

  if not c.is_active then v_problem := 'This card has been switched off';
  elsif not c.type_active then v_problem := format('%s cards are switched off', c.type_name);
  elsif c.valid_until is not null and c.valid_until < public.ist_date(now()) then
    v_problem := format('This card expired on %s', to_char(c.valid_until, 'DD Mon YYYY'));
  end if;

  return jsonb_build_object(
    'found', true, 'id', c.id, 'card_no', c.card_no, 'card_type_id', c.card_type_id,
    'type_name', c.type_name, 'discount_pct', c.discount_pct, 'applies_to', c.applies_to,
    'category_ids', to_jsonb(c.category_ids), 'holder_name', c.holder_name,
    'customer_id', c.customer_id, 'customer_name', c.customer_name,
    'valid_until', c.valid_until, 'usable', v_problem = '', 'problem', v_problem);
end $$;

-- ============================================================
-- D. The card on a bill, and its allowed discount
-- ============================================================
-- Records the bill's card from the payload's discount_card_id. On an
-- edit, a payload without the key keeps the card already on the bill.
create or replace function public.apply_invoice_discount_card(
  p_invoice uuid, payload jsonb, p_is_update boolean)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_inv    record;
  v_card   uuid;
  c        record;
begin
  if not (payload ? 'discount_card_id') then
    if p_is_update then return; end if;
    v_card := null;
  else
    v_card := nullif(payload ->> 'discount_card_id', '')::uuid;
  end if;
  select id, business_id, invoice_date, discount_card_id into v_inv
    from public.invoices where id = p_invoice;

  perform set_config('app.card_ok', 'on', true);
  if v_card is null then
    if v_inv.discount_card_id is not null or not p_is_update then
      update public.invoices set discount_card_id = null, discount_card_no = '',
        discount_card_type = '', discount_card_pct = 0, discount_card_amount = 0
      where id = p_invoice and (discount_card_id is not null or discount_card_pct <> 0);
    end if;
    perform set_config('app.card_ok', '', true);
    return;
  end if;

  select d.id, d.card_no, d.is_active, d.valid_until, t.name, t.discount_pct, t.is_active as type_active
    into c
  from public.discount_cards d join public.discount_card_types t on t.id = d.card_type_id
  where d.id = v_card and d.business_id = v_inv.business_id;
  if c.id is null then
    perform set_config('app.card_ok', '', true);
    raise exception 'That discount card isn''t in this shop''s list';
  end if;
  -- A bill made offline syncs with the card it was made with; an edit
  -- keeps the card already on the bill.
  if not coalesce((payload ->> 'offline_created')::boolean, false)
     and v_card is distinct from v_inv.discount_card_id then
    if not c.is_active or not c.type_active then
      perform set_config('app.card_ok', '', true);
      raise exception 'Card % is switched off', c.card_no;
    end if;
    if c.valid_until is not null and c.valid_until < public.ist_date(v_inv.invoice_date) then
      perform set_config('app.card_ok', '', true);
      raise exception 'Card % expired on %', c.card_no, to_char(c.valid_until, 'DD Mon YYYY');
    end if;
  end if;

  update public.invoices set discount_card_id = c.id, discount_card_no = c.card_no,
    discount_card_type = c.name, discount_card_pct = c.discount_pct
  where id = p_invoice;
  perform set_config('app.card_ok', '', true);
end $$;
revoke execute on function public.apply_invoice_discount_card(uuid, jsonb, boolean) from public, anon, authenticated;

-- What the card allows off the bill: its % of the default value of the
-- lines it covers (stock items only; charges and services aren't covered).
create or replace function public.invoice_card_allowance(p_invoice uuid)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(round(sum(pl.quantity * coalesce(pl.def, pl.eff) * inv.discount_card_pct / 100), 2), 0)
  from public.invoices inv
  join public.discount_cards d on d.id = inv.discount_card_id
  join public.discount_card_types t on t.id = d.card_type_id
  join public.invoice_price_lines(p_invoice) pl on true
  join public.invoice_items ii on ii.id = pl.id
  join public.products p on p.id = ii.product_id
  where inv.id = p_invoice and inv.discount_card_pct > 0
    and (t.applies_to = 'all'
         or (t.applies_to = 'only' and p.category_id = any (t.category_ids))
         or (t.applies_to = 'except' and not coalesce(p.category_id = any (t.category_ids), false)));
$$;
revoke execute on function public.invoice_card_allowance(uuid) from public, anon, authenticated;

-- 0044, plus the card: the card's discount is allowed, so only the rest
-- of the reduction counts towards the staff member's limit.
create or replace function public.check_invoice_pricing(p_invoice uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_inv       record;
  v_default   numeric := 0;
  v_actual    numeric := 0;
  v_reduction numeric := 0;
  v_allow     numeric := 0;
  v_counted   numeric := 0;
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

  v_allow := public.invoice_card_allowance(p_invoice);
  v_counted := greatest(v_reduction - v_allow, 0);

  perform set_config('app.card_ok', 'on', true);
  update public.invoices set default_total = round(v_default, 2), price_reduction = v_reduction,
    discount_card_amount = least(v_allow, v_reduction)
    where id = p_invoice;
  perform set_config('app.card_ok', '', true);

  if v_inv.invoice_type <> 'estimate' and auth.uid() is not null and v_counted > 0.05 then
    select role::text into v_role from public.profiles where id = auth.uid();
    if coalesce(v_role, '') not in ('owner', 'admin') then
      if not public.has_permission('can_edit_prices') then
        raise exception 'This bill is ₹% below the default prices — you don''t have permission to change prices or give discounts',
          v_counted using errcode = '42501';
      end if;
      select coalesce(discount_limit_pct, 0) into v_limit
        from public.staff_permissions where profile_id = auth.uid();
      v_limit := coalesce(v_limit, 0);
      v_over := v_counted > v_default * v_limit / 100 + 0.05;
    end if;
  end if;

  return jsonb_build_object('default_total', round(v_default, 2), 'reduction', v_reduction,
                            'pct', v_pct, 'limit_pct', v_limit, 'over_limit', v_over,
                            'card_allowance', v_allow);
end $$;
revoke execute on function public.check_invoice_pricing(uuid) from public, anon, authenticated;

-- ============================================================
-- E. Bill functions (0064 / 0065) record the card before pricing
-- ============================================================
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

  perform public.apply_invoice_discount_card(v_id, payload, false);
  v_pricing := public.check_invoice_pricing(v_id);
  v_ex := public.sale_exceptions(v_id, v_pricing);
  perform public.settle_sale_exceptions(v_id, payload, v_ex);
  return v;
end $$;

create or replace function public.update_invoice(p_invoice_id uuid, payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v         jsonb;
  v_pricing jsonb;
  v_ex      jsonb;
  v_item    jsonb;
begin
  if (select invoice_type::text from public.invoices where id = p_invoice_id) = 'opening' then
    raise exception 'An opening balance can''t be edited — cancel it and enter it again';
  end if;
  v := public.update_invoice_impl(p_invoice_id, payload);
  perform public.mark_pack_lines(p_invoice_id, payload -> 'items');

  if (select invoice_type::text from public.invoices where id = p_invoice_id) <> 'estimate' then
    for v_item in select * from jsonb_array_elements(coalesce(payload -> 'items', '[]'::jsonb)) loop
      if nullif(v_item ->> 'variant_id', '') is null
         and nullif(v_item ->> 'product_id', '') is not null
         and coalesce((v_item ->> 'quantity')::numeric, 0) > 0
         and exists (select 1 from public.products
                     where id = (v_item ->> 'product_id')::uuid and track_pieces) then
        perform public.cut_best_pieces((v_item ->> 'product_id')::uuid,
                                       (v_item ->> 'quantity')::numeric, p_invoice_id);
      end if;
    end loop;
  end if;

  perform public.apply_invoice_discount_card(p_invoice_id, payload, true);
  v_pricing := public.check_invoice_pricing(p_invoice_id);
  v_ex := public.sale_exceptions(p_invoice_id, v_pricing);
  perform public.settle_sale_exceptions(p_invoice_id, payload - 'approval_id' - 'offline_created', v_ex);
  return v;
end $$;

-- ============================================================
-- Grants
-- ============================================================
revoke execute on function public.save_discount_card_type(uuid, jsonb) from public, anon;
revoke execute on function public.save_discount_card(uuid, jsonb) from public, anon;
revoke execute on function public.get_discount_cards(text, integer) from public, anon;
revoke execute on function public.find_discount_card(text) from public, anon;
revoke execute on function public.create_invoice(jsonb) from public, anon;
revoke execute on function public.update_invoice(uuid, jsonb) from public, anon;
grant execute on function public.save_discount_card_type(uuid, jsonb) to authenticated;
grant execute on function public.save_discount_card(uuid, jsonb) to authenticated;
grant execute on function public.get_discount_cards(text, integer) to authenticated;
grant execute on function public.find_discount_card(text) to authenticated;
grant execute on function public.create_invoice(jsonb) to authenticated;
grant execute on function public.update_invoice(uuid, jsonb) to authenticated;
