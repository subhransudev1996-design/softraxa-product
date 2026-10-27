-- ============================================================
-- 0094: Book store billing (a bookshop's bill sheet).
--
--   * Products get a publisher and an author (printed as columns on the
--     bill when any line has them) and a REGULAR DISCOUNT % — the
--     shop's standing discount on that item, filled in on the bill line
--     (the cashier can change it). set_regular_discount() sets it for
--     many products at once: by publisher, by category or all.
--   * The regular discount is an allowed discount, like the discount
--     card (0083): it doesn't count towards a staff member's discount
--     limit. The card's % now comes off what is left after the regular
--     discount, as the app works it out.
--   * Discount card numbers in the shop's own pattern: a prefix
--     ("2017-1234-1234-") and a running number of N digits;
--     next_discount_card_no() gives the next free one.
--
-- Run AFTER 0093.
-- ============================================================

alter table public.products
  add column if not exists publisher text not null default '',
  add column if not exists author text not null default '',
  add column if not exists regular_discount_pct numeric(5,2) not null default 0;
alter table public.products drop constraint if exists products_book_fields_check;
alter table public.products add constraint products_book_fields_check
  check (char_length(publisher) <= 120 and char_length(author) <= 120
         and regular_discount_pct >= 0 and regular_discount_pct < 100);
create index if not exists products_business_publisher_idx
  on public.products (business_id, lower(publisher)) where publisher <> '';

alter table public.businesses
  add column if not exists card_no_prefix text not null default '',
  add column if not exists card_no_digits smallint not null default 4;
alter table public.businesses drop constraint if exists businesses_card_no_check;
alter table public.businesses add constraint businesses_card_no_check
  check (char_length(card_no_prefix) <= 30 and card_no_digits between 1 and 12);

-- ------------------------------------------------------------
-- Regular discount for many products at once. p_publisher / p_category
-- narrow it down (both empty = every product). Returns how many changed.
-- ------------------------------------------------------------
create or replace function public.set_regular_discount(
  p_pct numeric, p_publisher text default '', p_category_id uuid default null)
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_pub      text := lower(btrim(coalesce(p_publisher, '')));
  v_n        integer;
begin
  perform public.assert_can('can_manage_products');
  perform public.assert_can('can_edit_prices');
  if p_pct is null or p_pct < 0 or p_pct >= 100 then
    raise exception 'The discount must be from 0 to 99.99%%';
  end if;
  if p_category_id is not null and not exists (
       select 1 from public.categories where id = p_category_id and business_id = v_business) then
    raise exception 'Category not found';
  end if;
  update public.products set regular_discount_pct = round(p_pct, 2)
    where business_id = v_business
      and (v_pub = '' or lower(btrim(publisher)) = v_pub)
      and (p_category_id is null or category_id = p_category_id)
      and regular_discount_pct is distinct from round(p_pct, 2);
  get diagnostics v_n = row_count;
  perform public.log_audit('product.regular_discount', 'product', 'bulk',
    jsonb_build_object('pct', p_pct, 'publisher', btrim(coalesce(p_publisher, '')),
                       'category_id', p_category_id, 'count', v_n));
  return v_n;
end $$;

-- Publishers in use, with how many products and the discounts they have.
create or replace function public.product_publishers()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x.publisher), '[]'::jsonb)
  from (select min(btrim(publisher)) as publisher, count(*) as products,
               min(regular_discount_pct) as min_pct, max(regular_discount_pct) as max_pct
        from public.products
        where business_id = public.current_business_id() and btrim(publisher) <> ''
        group by lower(btrim(publisher))) x;
$$;

-- ------------------------------------------------------------
-- The next card number in the shop's pattern: the prefix and one more
-- than the highest running number already given with it.
-- ------------------------------------------------------------
create or replace function public.next_discount_card_no()
returns text language plpgsql stable security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_prefix   text;
  v_digits   integer;
  v_key      text;
  v_max      bigint;
begin
  select card_no_prefix, card_no_digits into v_prefix, v_digits
    from public.businesses where id = v_business;
  v_key := public.card_key(v_prefix);
  select max(substr(card_key, char_length(v_key) + 1)::bigint) into v_max
    from public.discount_cards
    where business_id = v_business
      and left(card_key, char_length(v_key)) = v_key
      and char_length(card_key) > char_length(v_key)
      and char_length(card_key) <= char_length(v_key) + 15
      and substr(card_key, char_length(v_key) + 1) ~ '^[0-9]+$';
  return coalesce(v_prefix, '') || lpad((coalesce(v_max, 0) + 1)::text, v_digits, '0');
end $$;

-- ------------------------------------------------------------
-- Allowed discounts on a bill: the regular discount of each line, and
-- the card's % of what is left after it.
-- ------------------------------------------------------------
create or replace function public.invoice_regular_allowance(p_invoice uuid)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(round(sum(pl.quantity * coalesce(pl.def, pl.eff) * p.regular_discount_pct / 100), 2), 0)
  from public.invoice_price_lines(p_invoice) pl
  join public.invoice_items ii on ii.id = pl.id
  join public.products p on p.id = ii.product_id
  where p.regular_discount_pct > 0;
$$;
revoke execute on function public.invoice_regular_allowance(uuid) from public, anon, authenticated;

create or replace function public.invoice_card_allowance(p_invoice uuid)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(round(sum(pl.quantity * coalesce(pl.def, pl.eff)
                            * (1 - p.regular_discount_pct / 100) * inv.discount_card_pct / 100), 2), 0)
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

-- As 0084, with the regular discount allowed too.
create or replace function public.check_invoice_pricing(p_invoice uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_inv       record;
  v_default   numeric := 0;
  v_actual    numeric := 0;
  v_reduction numeric := 0;
  v_regular   numeric := 0;
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

  v_regular := public.invoice_regular_allowance(p_invoice);
  v_allow := public.invoice_card_allowance(p_invoice);
  v_counted := greatest(v_reduction - v_regular - v_allow - v_inv.offer_amount, 0);

  perform set_config('app.card_ok', 'on', true);
  update public.invoices set default_total = round(v_default, 2), price_reduction = v_reduction,
    discount_card_amount = least(v_allow, greatest(v_reduction - v_regular, 0))
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
                            'regular_allowance', v_regular,
                            'card_allowance', v_allow, 'offer_amount', v_inv.offer_amount);
end $$;
revoke execute on function public.check_invoice_pricing(uuid) from public, anon, authenticated;

revoke execute on function public.set_regular_discount(numeric, text, uuid) from public, anon;
revoke execute on function public.product_publishers() from public, anon;
revoke execute on function public.next_discount_card_no() from public, anon;
grant execute on function public.set_regular_discount(numeric, text, uuid) to authenticated;
grant execute on function public.product_publishers() to authenticated;
grant execute on function public.next_discount_card_no() to authenticated;
