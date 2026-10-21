-- ============================================================
-- 0084_offers.sql
--
-- Offers & coupons: scratch cards, coupon codes and vouchers.
--
-- An offer (owner) gives a ₹ amount or a % off the bill:
--   * kind 'amount': amounts = the allowed ₹ values. One value = a fixed
--     ₹ off; several = a scratch card's prizes (₹20 / 50 / 100 …), the
--     cashier picks the one revealed.
--   * kind 'percent': percent off the bill, at most max_discount.
--   * min_bill: the bill must be at least this (before the offer).
--   * valid_from / valid_until, is_active.
--   * needs_customer: the bill must name a customer with a phone number
--     (the scratch card's "name / WhatsApp" slip, kept in the app).
-- How a customer claims it (code_mode):
--   * 'none'   — the cashier picks the offer (unnumbered scratch cards,
--                counter promotions);
--   * 'shared' — one code everyone types ("DIWALI100"), optionally
--                limited per customer (uses_per_customer);
--   * 'unique' — each card / voucher has its own code, used once.
--                Codes are generated or typed in by the owner; a
--                cancelled bill frees its code again.
--
-- The offer's discount is taken off the whole bill (as part of the bill
-- discount) and is an allowed discount: it doesn't count towards a staff
-- member's discount limit (0043/0044, as discount cards in 0083), and the
-- server checks it is no more than the offer allows. Bills record the
-- offer, code and amount. Bills made offline sync without the date
-- checks.
--
-- Run AFTER 0083.
-- ============================================================

-- ============================================================
-- A. Tables
-- ============================================================
create table if not exists public.offers (
  id                uuid primary key default gen_random_uuid(),
  business_id       uuid not null references public.businesses(id) on delete cascade,
  name              text not null check (btrim(name) <> '' and char_length(name) <= 80),
  kind              text not null default 'amount' check (kind in ('amount', 'percent')),
  amounts           numeric(12,2)[] not null default '{}',
  percent           numeric(5,2) not null default 0 check (percent >= 0 and percent <= 100),
  max_discount      numeric(12,2) check (max_discount is null or max_discount > 0),
  min_bill          numeric(12,2) not null default 0 check (min_bill >= 0),
  code_mode         text not null default 'none' check (code_mode in ('none', 'shared', 'unique')),
  shared_code       text not null default '',
  shared_code_key   text not null default '',
  uses_per_customer integer check (uses_per_customer is null or uses_per_customer > 0),
  needs_customer    boolean not null default false,
  valid_from        date,
  valid_until       date,
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create unique index if not exists uq_offers_shared_code
  on public.offers (business_id, shared_code_key) where shared_code_key <> '';

create table if not exists public.offer_codes (
  id                  uuid primary key default gen_random_uuid(),
  business_id         uuid not null references public.businesses(id) on delete cascade,
  offer_id            uuid not null references public.offers(id) on delete cascade,
  code                text not null check (btrim(code) <> '' and char_length(code) <= 40),
  code_key            text not null,
  amount              numeric(12,2) check (amount is null or amount > 0),
  redeemed_invoice_id uuid references public.invoices(id) on delete set null,
  redeemed_at         timestamptz,
  created_at          timestamptz not null default now()
);
create unique index if not exists uq_offer_codes_key on public.offer_codes (business_id, code_key);
create index if not exists idx_offer_codes_offer on public.offer_codes (offer_id);
create index if not exists idx_offer_codes_invoice on public.offer_codes (redeemed_invoice_id)
  where redeemed_invoice_id is not null;

alter table public.offers enable row level security;
alter table public.offer_codes enable row level security;
drop policy if exists "tenant read" on public.offers;
drop policy if exists "admin all" on public.offers;
create policy "tenant read" on public.offers for select
  using (business_id = (select public.current_business_id()));
create policy "admin all" on public.offers for all
  using (public.is_admin()) with check (public.is_admin());
drop policy if exists "tenant read" on public.offer_codes;
drop policy if exists "admin all" on public.offer_codes;
create policy "tenant read" on public.offer_codes for select
  using (business_id = (select public.current_business_id()));
create policy "admin all" on public.offer_codes for all
  using (public.is_admin()) with check (public.is_admin());

alter table public.invoices
  add column if not exists offer_id      uuid references public.offers(id) on delete set null,
  add column if not exists offer_code_id uuid references public.offer_codes(id) on delete set null,
  add column if not exists offer_name    text not null default '',
  add column if not exists offer_code    text not null default '',
  add column if not exists offer_amount  numeric(12,2) not null default 0;
create index if not exists idx_invoices_offer on public.invoices (offer_id) where offer_id is not null;

-- Only the bill functions set these (they turn the switch on).
create or replace function public.guard_invoice_offer()
returns trigger language plpgsql as $$
begin
  if coalesce(current_setting('app.offer_ok', true), '') = 'on' then return new; end if;
  if tg_op = 'INSERT' then
    if new.offer_id is not null or new.offer_amount <> 0 then
      raise exception 'An offer is added to a bill only through billing';
    end if;
  elsif (new.offer_id, new.offer_code_id, new.offer_name, new.offer_code, new.offer_amount)
        is distinct from
        (old.offer_id, old.offer_code_id, old.offer_name, old.offer_code, old.offer_amount) then
    raise exception 'An offer is added to a bill only through billing';
  end if;
  return new;
end $$;
drop trigger if exists trg_invoices_offer_guard on public.invoices;
create trigger trg_invoices_offer_guard before insert or update on public.invoices
  for each row execute function public.guard_invoice_offer();

-- A cancelled bill frees its unique code.
create or replace function public.release_offer_code()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.is_cancelled and not old.is_cancelled then
    update public.offer_codes set redeemed_invoice_id = null, redeemed_at = null
      where redeemed_invoice_id = new.id;
  end if;
  return new;
end $$;
drop trigger if exists trg_invoices_release_offer_code on public.invoices;
create trigger trg_invoices_release_offer_code after update of is_cancelled on public.invoices
  for each row execute function public.release_offer_code();
revoke execute on function public.release_offer_code() from public, anon, authenticated;

-- ============================================================
-- B. Managing offers and codes (owner)
-- ============================================================
create or replace function public.save_offer(p_id uuid, p jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_name     text := btrim(coalesce(p ->> 'name', ''));
  v_kind     text := coalesce(nullif(p ->> 'kind', ''), 'amount');
  v_amounts  numeric[] := coalesce(
    (select array_agg(distinct round(x::numeric, 2) order by round(x::numeric, 2))
     from jsonb_array_elements_text(coalesce(p -> 'amounts', '[]'::jsonb)) x), '{}');
  v_pct      numeric := coalesce((p ->> 'percent')::numeric, 0);
  v_max      numeric := nullif(p ->> 'max_discount', '')::numeric;
  v_min      numeric := coalesce(nullif(p ->> 'min_bill', '')::numeric, 0);
  v_mode     text := coalesce(nullif(p ->> 'code_mode', ''), 'none');
  v_code     text := btrim(coalesce(p ->> 'shared_code', ''));
  v_uses     integer := nullif(p ->> 'uses_per_customer', '')::integer;
  v_from     date := nullif(p ->> 'valid_from', '')::date;
  v_until    date := nullif(p ->> 'valid_until', '')::date;
  v_id       uuid;
begin
  perform public.assert_can('owner');
  if v_name = '' then raise exception 'Give the offer a name, like Scratch & Win or Diwali Sale'; end if;
  if v_kind not in ('amount', 'percent') then raise exception 'Unknown offer kind: %', v_kind; end if;
  if v_mode not in ('none', 'shared', 'unique') then raise exception 'Unknown code choice: %', v_mode; end if;
  if v_kind = 'amount' then
    if cardinality(v_amounts) = 0 then raise exception 'Enter the ₹ amount (or the prize amounts)'; end if;
    if exists (select 1 from unnest(v_amounts) a where a <= 0) then
      raise exception 'Amounts must be more than ₹0';
    end if;
    v_pct := 0; v_max := null;
  else
    if v_pct <= 0 or v_pct > 100 then raise exception 'The discount must be more than 0%% and at most 100%%'; end if;
    v_amounts := '{}';
  end if;
  if v_min < 0 then raise exception 'The minimum bill can''t be negative'; end if;
  if v_from is not null and v_until is not null and v_until < v_from then
    raise exception 'The offer ends before it starts';
  end if;
  if v_mode = 'shared' then
    if char_length(public.card_key(v_code)) < 3 then
      raise exception 'Enter the code customers will use (at least 3 letters or digits)';
    end if;
    if exists (select 1 from public.offers where business_id = v_business
               and shared_code_key = public.card_key(v_code) and id is distinct from p_id) then
      raise exception 'Another offer already uses the code %', v_code;
    end if;
    if exists (select 1 from public.offer_codes where business_id = v_business
               and code_key = public.card_key(v_code)) then
      raise exception 'The code % is already a voucher code', v_code;
    end if;
  else
    v_code := ''; v_uses := null;
  end if;
  if p_id is not null and exists (select 1 from public.offers where id = p_id and code_mode = 'unique')
     and v_mode <> 'unique' and exists (select 1 from public.offer_codes where offer_id = p_id) then
    raise exception 'This offer has its own codes — it stays an offer with codes';
  end if;

  if p_id is null then
    insert into public.offers (business_id, name, kind, amounts, percent, max_discount, min_bill,
                               code_mode, shared_code, shared_code_key, uses_per_customer,
                               needs_customer, valid_from, valid_until, is_active)
    values (v_business, v_name, v_kind, v_amounts, round(v_pct, 2), v_max, v_min, v_mode, v_code,
            public.card_key(v_code), v_uses, coalesce((p ->> 'needs_customer')::boolean, false),
            v_from, v_until, coalesce((p ->> 'is_active')::boolean, true))
    returning id into v_id;
  else
    update public.offers set name = v_name, kind = v_kind, amounts = v_amounts,
      percent = round(v_pct, 2), max_discount = v_max, min_bill = v_min, code_mode = v_mode,
      shared_code = v_code, shared_code_key = public.card_key(v_code), uses_per_customer = v_uses,
      needs_customer = coalesce((p ->> 'needs_customer')::boolean, needs_customer),
      valid_from = v_from, valid_until = v_until,
      is_active = coalesce((p ->> 'is_active')::boolean, is_active), updated_at = now()
    where id = p_id and business_id = v_business
    returning id into v_id;
    if v_id is null then raise exception 'Offer not found'; end if;
  end if;
  perform public.log_audit(case when p_id is null then 'offer.created' else 'offer.updated' end,
    'offer', v_id::text, p - 'shared_code' || jsonb_build_object('name', v_name));
  return v_id;
end $$;

-- Adds codes to an offer with its own codes: p_count new random codes
-- ("TBW-7K3QX9"), and/or p_codes typed or pasted (serials printed on the
-- cards). p_amount: each code's ₹ value, or null when the cashier picks
-- the revealed prize from the offer's amounts. Returns how many were added.
create or replace function public.add_offer_codes(
  p_offer uuid, p_count integer default 0, p_prefix text default '',
  p_codes jsonb default '[]'::jsonb, p_amount numeric default null)
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_offer    public.offers;
  v_prefix   text := upper(regexp_replace(coalesce(p_prefix, ''), '[^0-9A-Za-z]', '', 'g'));
  v_alpha    constant text := '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  v_code     text;
  v_added    integer := 0;
  v_tries    integer;
  i          integer;
  x          text;
begin
  perform public.assert_can('owner');
  select * into v_offer from public.offers where id = p_offer and business_id = v_business;
  if v_offer.id is null then raise exception 'Offer not found'; end if;
  if v_offer.code_mode <> 'unique' then raise exception 'This offer doesn''t use its own codes'; end if;
  if p_amount is not null and p_amount <= 0 then raise exception 'The amount must be more than ₹0'; end if;
  if v_offer.kind = 'percent' and p_amount is not null then
    raise exception 'A %% offer''s codes have no ₹ amount of their own';
  end if;
  if coalesce(p_count, 0) < 0 or coalesce(p_count, 0) > 2000 then
    raise exception 'Make between 1 and 2000 codes at a time';
  end if;
  if char_length(v_prefix) > 8 then raise exception 'Keep the start of the codes short (up to 8 letters)'; end if;

  -- Typed or pasted codes.
  for x in select btrim(value) from jsonb_array_elements_text(coalesce(p_codes, '[]'::jsonb)) loop
    continue when x = '';
    if char_length(public.card_key(x)) < 3 then
      raise exception 'The code "%" is too short (at least 3 letters or digits)', x;
    end if;
    if exists (select 1 from public.offer_codes where business_id = v_business and code_key = public.card_key(x))
       or exists (select 1 from public.offers where business_id = v_business and shared_code_key = public.card_key(x)) then
      raise exception 'The code % is already used', x;
    end if;
    insert into public.offer_codes (business_id, offer_id, code, code_key, amount)
      values (v_business, p_offer, x, public.card_key(x), p_amount);
    v_added := v_added + 1;
  end loop;

  -- Generated codes: no 0/O, 1/I look-alikes.
  for i in 1 .. coalesce(p_count, 0) loop
    v_tries := 0;
    loop
      v_code := (select string_agg(substr(v_alpha, 1 + floor(random() * 32)::int, 1), '')
                 from generate_series(1, 6));
      v_code := case when v_prefix = '' then v_code else v_prefix || '-' || v_code end;
      exit when not exists (select 1 from public.offer_codes
                            where business_id = v_business and code_key = public.card_key(v_code));
      v_tries := v_tries + 1;
      if v_tries > 20 then raise exception 'Could not make enough different codes — try fewer'; end if;
    end loop;
    insert into public.offer_codes (business_id, offer_id, code, code_key, amount)
      values (v_business, p_offer, v_code, public.card_key(v_code), p_amount);
    v_added := v_added + 1;
  end loop;

  if v_added = 0 then raise exception 'No codes to add'; end if;
  perform public.log_audit('offer.codes_added', 'offer', p_offer::text,
    jsonb_build_object('added', v_added, 'amount', p_amount));
  return v_added;
end $$;

-- Removes unused codes (printed by mistake, lost cards). Used codes stay.
create or replace function public.delete_offer_codes(p_ids uuid[])
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_n integer;
begin
  perform public.assert_can('owner');
  delete from public.offer_codes
    where id = any (p_ids) and business_id = public.current_business_id()
      and redeemed_invoice_id is null;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- Offers with how often each was used; with p_offer, that offer's codes
-- and the bills it was used on (customer and phone, for follow-up).
create or replace function public.get_offers(p_offer uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
begin
  if v_business is null then raise exception 'No shop selected'; end if;
  return jsonb_build_object(
    'offers', coalesce((
      select jsonb_agg(to_jsonb(o) - 'shared_code_key' || jsonb_build_object(
               'uses', (select count(*) from public.invoices i
                        where i.offer_id = o.id and not i.is_cancelled),
               'given', (select coalesce(sum(i.offer_amount), 0) from public.invoices i
                         where i.offer_id = o.id and not i.is_cancelled),
               'codes', (select count(*) from public.offer_codes c where c.offer_id = o.id),
               'codes_used', (select count(*) from public.offer_codes c
                              where c.offer_id = o.id and c.redeemed_invoice_id is not null))
             order by o.is_active desc, o.created_at desc)
      from public.offers o where o.business_id = v_business), '[]'::jsonb),
    'codes', case when p_offer is null then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', c.id, 'code', c.code, 'amount', c.amount, 'redeemed_at', c.redeemed_at,
               'invoice_no', i.invoice_no) order by c.created_at, c.code)
      from public.offer_codes c left join public.invoices i on i.id = c.redeemed_invoice_id
      where c.offer_id = p_offer and c.business_id = v_business), '[]'::jsonb) end,
    'uses', case when p_offer is null then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object(
               'invoice_id', i.id, 'invoice_no', i.invoice_no, 'date', i.invoice_date,
               'customer', coalesce(nullif(cu.name, ''), nullif(i.customer_name, ''), 'Walk-in'),
               'phone', coalesce(nullif(cu.phone, ''), i.customer_phone, ''),
               'code', i.offer_code, 'amount', i.offer_amount) order by i.invoice_date desc)
      from public.invoices i left join public.customers cu on cu.id = i.customer_id
      where i.offer_id = p_offer and i.business_id = v_business and not i.is_cancelled), '[]'::jsonb) end);
end $$;

-- ============================================================
-- C. Finding an offer at billing
-- ============================================================
-- A typed code: a shared offer code or a voucher code. {found:false} when
-- there is none. The offer's rules come back so the app can apply it;
-- problems (used, expired, switched off) come back in 'problem'.
create or replace function public.find_offer_code(p_code text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_key      text := public.card_key(p_code);
  v_offer    public.offers;
  v_code     record;
  v_problem  text := '';
  v_today    date := public.ist_date(now());
begin
  if v_business is null then raise exception 'No shop selected'; end if;
  if char_length(v_key) < 3 then raise exception 'Type the code (at least 3 letters or digits)'; end if;

  select * into v_code from public.offer_codes where business_id = v_business and code_key = v_key;
  if v_code.id is not null then
    select * into v_offer from public.offers where id = v_code.offer_id;
  else
    select * into v_offer from public.offers
      where business_id = v_business and shared_code_key = v_key and code_mode = 'shared';
  end if;
  if v_offer.id is null then return jsonb_build_object('found', false, 'query', btrim(p_code)); end if;

  if not v_offer.is_active then v_problem := 'This offer has been switched off';
  elsif v_offer.valid_from is not null and v_offer.valid_from > v_today then
    v_problem := format('This offer starts on %s', to_char(v_offer.valid_from, 'DD Mon YYYY'));
  elsif v_offer.valid_until is not null and v_offer.valid_until < v_today then
    v_problem := format('This offer ended on %s', to_char(v_offer.valid_until, 'DD Mon YYYY'));
  elsif v_code.id is not null and v_code.redeemed_invoice_id is not null then
    v_problem := format('Code %s was already used on bill %s', v_code.code,
      (select invoice_no from public.invoices where id = v_code.redeemed_invoice_id));
  end if;

  return public.offer_json(v_offer) || jsonb_build_object(
    'found', true, 'code_id', v_code.id,
    'code', coalesce(v_code.code, v_offer.shared_code),
    'code_amount', v_code.amount,
    'usable', v_problem = '', 'problem', v_problem);
end $$;

-- What the app needs of an offer.
create or replace function public.offer_json(o public.offers)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'offer_id', o.id, 'name', o.name, 'kind', o.kind, 'amounts', to_jsonb(o.amounts),
    'percent', o.percent, 'max_discount', o.max_discount, 'min_bill', o.min_bill,
    'code_mode', o.code_mode, 'needs_customer', o.needs_customer,
    'uses_per_customer', o.uses_per_customer, 'valid_until', o.valid_until);
$$;

-- Offers the cashier can pick at the counter (no code needed), open today.
create or replace function public.counter_offers()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(public.offer_json(o) order by o.name), '[]'::jsonb)
  from public.offers o
  where o.business_id = public.current_business_id() and o.is_active and o.code_mode = 'none'
    and (o.valid_from is null or o.valid_from <= public.ist_date(now()))
    and (o.valid_until is null or o.valid_until >= public.ist_date(now()));
$$;

-- ============================================================
-- D. The offer on a bill
-- ============================================================
-- From the payload: offer_id, offer_code (when it has codes) and
-- offer_amount (what the app took off). Checks every rule and records
-- it. On an edit, a payload without offer_id keeps the bill's offer.
-- Returns the allowed amount (0 when none).
create or replace function public.apply_invoice_offer(p_invoice uuid, payload jsonb, p_is_update boolean)
returns numeric language plpgsql security definer set search_path = public as $$
declare
  v_inv     record;
  v_offer   public.offers;
  v_code    public.offer_codes;
  v_id      uuid;
  v_amount  numeric := round(coalesce((payload ->> 'offer_amount')::numeric, 0), 2);
  v_gross   numeric;
  v_allowed numeric;
  v_date    date;
  v_offline boolean := coalesce((payload ->> 'offline_created')::boolean, false);
  v_phone   text;
  v_used    integer;
begin
  select * into v_inv from public.invoices where id = p_invoice;
  if not (payload ? 'offer_id') then
    if p_is_update then return v_inv.offer_amount; end if;
    v_id := null;
  else
    v_id := nullif(payload ->> 'offer_id', '')::uuid;
  end if;

  perform set_config('app.offer_ok', 'on', true);
  -- An edit that drops the offer, or changes it: free the old code.
  if p_is_update and (v_id is null or v_id is distinct from v_inv.offer_id
                      or public.card_key(payload ->> 'offer_code') is distinct from public.card_key(v_inv.offer_code)) then
    update public.offer_codes set redeemed_invoice_id = null, redeemed_at = null
      where redeemed_invoice_id = p_invoice;
  end if;
  if v_id is null then
    update public.invoices set offer_id = null, offer_code_id = null, offer_name = '',
      offer_code = '', offer_amount = 0
    where id = p_invoice and (offer_id is not null or offer_amount <> 0);
    perform set_config('app.offer_ok', '', true);
    return 0;
  end if;

  select * into v_offer from public.offers where id = v_id and business_id = v_inv.business_id;
  if v_offer.id is null then
    raise exception 'That offer isn''t in this shop''s list';
  end if;
  v_date := public.ist_date(v_inv.invoice_date);
  if not v_offline and v_id is distinct from v_inv.offer_id then
    if not v_offer.is_active then raise exception 'The offer "%" is switched off', v_offer.name; end if;
    if (v_offer.valid_from is not null and v_offer.valid_from > v_date)
       or (v_offer.valid_until is not null and v_offer.valid_until < v_date) then
      raise exception 'The offer "%" isn''t open on this date', v_offer.name;
    end if;
  end if;

  -- The bill before the offer: what is charged (before rounding) plus the
  -- offer — items with GST, less every other discount.
  v_gross := v_inv.total - coalesce(v_inv.round_off, 0) + v_amount;
  if v_gross + 0.005 < v_offer.min_bill then
    raise exception 'The offer "%" needs a bill of at least ₹%', v_offer.name, v_offer.min_bill;
  end if;

  -- Customer details.
  if v_offer.needs_customer then
    select phone into v_phone from public.customers where id = v_inv.customer_id;
    if v_inv.customer_id is null or btrim(coalesce(v_phone, '')) = '' then
      raise exception 'The offer "%" needs the customer''s name and phone number on the bill', v_offer.name;
    end if;
  end if;

  -- The code.
  if v_offer.code_mode = 'unique' then
    select * into v_code from public.offer_codes
      where business_id = v_inv.business_id and offer_id = v_offer.id
        and code_key = public.card_key(payload ->> 'offer_code')
      for update;
    if v_code.id is null then raise exception 'That code isn''t one of this offer''s codes'; end if;
    if v_code.redeemed_invoice_id is not null and v_code.redeemed_invoice_id <> p_invoice then
      raise exception 'Code % was already used', v_code.code;
    end if;
  elsif v_offer.code_mode = 'shared' then
    if public.card_key(payload ->> 'offer_code') is distinct from v_offer.shared_code_key then
      raise exception 'That isn''t this offer''s code';
    end if;
    if v_offer.uses_per_customer is not null then
      if v_inv.customer_id is null then
        raise exception 'The offer "%" is limited per customer — choose the customer first', v_offer.name;
      end if;
      select count(*) into v_used from public.invoices
        where offer_id = v_offer.id and customer_id = v_inv.customer_id and not is_cancelled
          and id <> p_invoice;
      if v_used >= v_offer.uses_per_customer then
        raise exception 'This customer has already used "%" % time(s)', v_offer.name, v_used;
      end if;
    end if;
  end if;

  -- The amount.
  if v_offer.kind = 'percent' then
    v_allowed := round(greatest(v_gross, 0) * v_offer.percent / 100, 2);
    if v_offer.max_discount is not null then v_allowed := least(v_allowed, v_offer.max_discount); end if;
    if v_amount > v_allowed + 0.05 then
      raise exception 'The offer gives at most ₹% on this bill', v_allowed;
    end if;
  elsif v_code.id is not null and v_code.amount is not null then
    if v_amount > v_code.amount + 0.005 then
      raise exception 'Code % is worth ₹%', v_code.code, v_code.amount;
    end if;
  else
    -- One of the offer's amounts — or less, when the bill itself is less.
    if not exists (select 1 from unnest(v_offer.amounts) a
                   where abs(a - v_amount) <= 0.005
                      or (v_amount < a and v_amount >= v_gross - 0.05)) then
      raise exception 'The offer "%" gives ₹%', v_offer.name, array_to_string(v_offer.amounts, ', ₹');
    end if;
  end if;
  v_amount := least(v_amount, greatest(v_gross, 0));

  if v_code.id is not null then
    update public.offer_codes set redeemed_invoice_id = p_invoice, redeemed_at = coalesce(redeemed_at, now())
      where id = v_code.id;
  end if;
  update public.invoices set offer_id = v_offer.id, offer_code_id = v_code.id, offer_name = v_offer.name,
    offer_code = coalesce(v_code.code, case when v_offer.code_mode = 'shared' then v_offer.shared_code else '' end),
    offer_amount = v_amount
  where id = p_invoice;
  perform set_config('app.offer_ok', '', true);
  return v_amount;
end $$;
revoke execute on function public.apply_invoice_offer(uuid, jsonb, boolean) from public, anon, authenticated;

-- 0083 plus the offer: its amount is allowed too.
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
  v_counted := greatest(v_reduction - v_allow - v_inv.offer_amount, 0);

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
                            'card_allowance', v_allow, 'offer_amount', v_inv.offer_amount);
end $$;
revoke execute on function public.check_invoice_pricing(uuid) from public, anon, authenticated;

-- 0038's bill guard, plus the offer: a cashier without discount rights may
-- save a bill discount up to the offer the bill claims. The bill functions
-- pass the claim (app.offer_claim) and check the offer right after
-- (apply_invoice_offer, then check_invoice_pricing with the checked
-- amount), so a false claim still fails the whole bill.
create or replace function public.guard_invoices()
returns trigger language plpgsql as $$
declare
  v_claim numeric := coalesce(nullif(current_setting('app.offer_claim', true), '')::numeric, 0);
begin
  if tg_op = 'INSERT' then
    perform public.assert_can('can_create_invoice');
    if new.invoice_type = 'gst' then
      perform public.assert_feature('gst_billing', 'GST billing');
    end if;
    if new.discount_amount > v_claim + 0.005 and not public.has_permission('can_edit_prices') then
      raise exception 'You don''t have permission to give discounts' using errcode = '42501';
    end if;
    return new;
  end if;

  if row(new.business_id, new.invoice_no, new.invoice_type, new.invoice_date, new.customer_id,
         new.subtotal, new.discount_amount, new.tax_amount, new.round_off, new.total,
         new.is_cancelled, new.notes)
     is distinct from
     row(old.business_id, old.invoice_no, old.invoice_type, old.invoice_date, old.customer_id,
         old.subtotal, old.discount_amount, old.tax_amount, old.round_off, old.total,
         old.is_cancelled, old.notes) then
    perform public.assert_can('can_edit_invoices');
    if new.discount_amount - v_claim > old.discount_amount - old.offer_amount + 0.005
       and not public.has_permission('can_edit_prices') then
      raise exception 'You don''t have permission to give discounts' using errcode = '42501';
    end if;
    -- D. A bill with returns can't be edited or cancelled.
    if exists (select 1 from public.sale_returns where invoice_id = new.id) then
      raise exception 'This bill has returns, so it can''t be edited or cancelled — return the remaining items instead'
        using errcode = '42501';
    end if;
    if new.credit_amount is distinct from old.credit_amount then
      raise exception 'Return credits can only change through sale returns' using errcode = '42501';
    end if;
  elsif new.credit_amount is distinct from old.credit_amount then
    perform public.assert_can('can_manage_returns');
  elsif new.place_of_supply is distinct from old.place_of_supply then
    perform public.assert_can('can_create_invoice');
  elsif new.paid_amount is distinct from old.paid_amount
     or new.payment_status is distinct from old.payment_status then
    perform public.assert_can('can_record_payments', false);
  end if;
  return new;
end $$;

-- ============================================================
-- E. Bill functions (0083) record the offer before pricing
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
  -- The offer this bill claims, for the bill guard (checked below).
  perform set_config('app.offer_claim',
    case when payload ? 'offer_id' then coalesce(payload ->> 'offer_amount', '0') else '0' end, true);
  v := public.create_invoice_impl(payload);
  perform set_config('app.offer_claim', '', true);
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
  perform public.apply_invoice_offer(v_id, payload, false);
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
  perform set_config('app.offer_claim',
    case when payload ? 'offer_id' then coalesce(payload ->> 'offer_amount', '0')
         else (select offer_amount::text from public.invoices where id = p_invoice_id) end, true);
  v := public.update_invoice_impl(p_invoice_id, payload);
  perform set_config('app.offer_claim', '', true);
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
  perform public.apply_invoice_offer(p_invoice_id, payload, true);
  v_pricing := public.check_invoice_pricing(p_invoice_id);
  v_ex := public.sale_exceptions(p_invoice_id, v_pricing);
  perform public.settle_sale_exceptions(p_invoice_id, payload - 'approval_id' - 'offline_created', v_ex);
  return v;
end $$;

-- ============================================================
-- Grants
-- ============================================================
revoke execute on function public.save_offer(uuid, jsonb) from public, anon;
revoke execute on function public.add_offer_codes(uuid, integer, text, jsonb, numeric) from public, anon;
revoke execute on function public.delete_offer_codes(uuid[]) from public, anon;
revoke execute on function public.get_offers(uuid) from public, anon;
revoke execute on function public.find_offer_code(text) from public, anon;
revoke execute on function public.counter_offers() from public, anon;
revoke execute on function public.offer_json(public.offers) from public, anon;
revoke execute on function public.create_invoice(jsonb) from public, anon;
revoke execute on function public.update_invoice(uuid, jsonb) from public, anon;
grant execute on function public.save_offer(uuid, jsonb) to authenticated;
grant execute on function public.add_offer_codes(uuid, integer, text, jsonb, numeric) to authenticated;
grant execute on function public.delete_offer_codes(uuid[]) to authenticated;
grant execute on function public.get_offers(uuid) to authenticated;
grant execute on function public.find_offer_code(text) to authenticated;
grant execute on function public.counter_offers() to authenticated;
grant execute on function public.offer_json(public.offers) to authenticated;
grant execute on function public.create_invoice(jsonb) to authenticated;
grant execute on function public.update_invoice(uuid, jsonb) to authenticated;
