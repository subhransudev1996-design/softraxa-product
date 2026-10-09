-- ============================================================
-- 0074_product_alternatives.sql
-- Alternative products: what can replace a product when the customer wants
-- something else or it is out of stock (another brand's charger, the same
-- oil in another pack). Offered on New Bill and when adding a part to a job
-- card.
--
-- * The shop links alternatives on the product form. A link works both
--   ways: A -> B also offers A when B is chosen.
-- * Where the shop linked nothing (or too few), the same category's
--   in-stock products with the most name words in common are offered.
--
-- The table is reached only through the functions below.
-- ============================================================

create table if not exists public.product_alternatives (
  business_id uuid not null references public.businesses(id) on delete cascade,
  product_a   uuid not null references public.products(id) on delete cascade,
  product_b   uuid not null references public.products(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (product_a, product_b),
  check (product_a < product_b)          -- one row per pair, whichever way it was linked
);
create index if not exists idx_product_alternatives_b on public.product_alternatives(product_b);
create index if not exists idx_product_alternatives_business on public.product_alternatives(business_id);

alter table public.product_alternatives enable row level security;
revoke all on public.product_alternatives from public, anon, authenticated;

-- A product's in-stock test: its own stock, or any active variant's.
create or replace function public.product_in_stock(p public.products)
returns boolean language sql stable security definer set search_path = public as $$
  select p.current_stock > 0
      or (p.has_variants and exists (
            select 1 from public.product_variants v
            where v.product_id = p.id and v.is_active and v.current_stock > 0));
$$;

-- The products linked to p_product by the shop (either side of the pair).
create or replace function public.linked_alternatives(p_product uuid)
returns setof uuid language sql stable security definer set search_path = public as $$
  select case when a.product_a = p_product then a.product_b else a.product_a end
  from public.product_alternatives a
  where a.product_a = p_product or a.product_b = p_product;
$$;

-- Replace the shop's alternatives of one product (up to 30). Links where
-- this product is either side are replaced; other products' links stay.
create or replace function public.set_product_alternatives(p_product uuid, p_alternatives uuid[])
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_ids      uuid[];
  v_n        integer;
begin
  if v_business is null then raise exception 'No shop selected'; end if;
  perform public.assert_can('can_manage_products');
  if not exists (select 1 from public.products where id = p_product and business_id = v_business) then
    raise exception 'Product not found in your store';
  end if;

  select coalesce(array_agg(distinct x), '{}') into v_ids
  from unnest(coalesce(p_alternatives, '{}')) x
  where x is not null and x <> p_product;
  if cardinality(v_ids) > 30 then raise exception 'Choose up to 30 alternatives'; end if;
  if exists (select 1 from unnest(v_ids) x
             where not exists (select 1 from public.products p
                               where p.id = x and p.business_id = v_business)) then
    raise exception 'An alternative is not a product of your store';
  end if;

  delete from public.product_alternatives
  where business_id = v_business and (product_a = p_product or product_b = p_product);
  insert into public.product_alternatives (business_id, product_a, product_b)
  select v_business, least(p_product, x), greatest(p_product, x) from unnest(v_ids) x
  on conflict do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- The alternatives to offer for a product, best first:
--   1. the shop's own links, in stock first, then by name;
--   2. then, up to p_limit, active in-stock products of the same category
--      with the most name words in common (2+ letters), then by name.
-- Returns [{id, picked}] ; the app loads the products themselves.
create or replace function public.get_product_alternatives(p_product uuid, p_limit integer default 8)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_p        public.products;
  v_limit    integer := least(greatest(coalesce(p_limit, 8), 1), 30);
  v_words    text[];
  v_out      jsonb;
begin
  if v_business is null then raise exception 'No shop selected'; end if;
  select * into v_p from public.products where id = p_product and business_id = v_business;
  if v_p.id is null then return '[]'::jsonb; end if;

  select coalesce(array_agg(distinct w), '{}') into v_words
  from unnest(regexp_split_to_array(lower(v_p.name), '[^[:alnum:]]+')) w
  where char_length(w) >= 2;

  with picked as (
         select p.id, true as picked, 0 as grp,
                case when public.product_in_stock(p) then 0 else 1 end as stock_rank,
                0 as score, p.name
         from public.products p
         where p.business_id = v_business and p.is_active
           and p.id in (select public.linked_alternatives(p_product))),
       auto as (
         select p.id, false as picked, 1 as grp, 0 as stock_rank,
                (select count(*) from unnest(regexp_split_to_array(lower(p.name), '[^[:alnum:]]+')) w
                 where w = any(v_words))::int as score,
                p.name
         from public.products p
         where p.business_id = v_business and p.is_active and p.id <> p_product
           and v_p.category_id is not null and p.category_id = v_p.category_id
           and p.id not in (select id from picked)
           and public.product_in_stock(p)),
       ranked as (
         select * from picked
         union all
         select * from auto)
  select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'picked', r.picked)
                            order by r.grp, r.stock_rank, r.score desc, r.name), '[]'::jsonb)
  into v_out
  from (select * from ranked order by grp, stock_rank, score desc, name limit v_limit) r;
  return v_out;
end $$;

-- The shop's own links of a product, for the product form.
create or replace function public.get_linked_alternatives(p_product uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id, 'name', p.name, 'current_stock', p.current_stock,
           'selling_price', p.selling_price) order by p.name), '[]'::jsonb)
  from public.products p
  where p.business_id = public.current_business_id()
    and p.id in (select public.linked_alternatives(p_product));
$$;

revoke execute on function public.product_in_stock(public.products) from public, anon, authenticated;
revoke execute on function public.linked_alternatives(uuid) from public, anon, authenticated;
revoke execute on function public.set_product_alternatives(uuid, uuid[]) from public, anon;
revoke execute on function public.get_product_alternatives(uuid, integer) from public, anon;
revoke execute on function public.get_linked_alternatives(uuid) from public, anon;
grant execute on function public.set_product_alternatives(uuid, uuid[]) to authenticated;
grant execute on function public.get_product_alternatives(uuid, integer) to authenticated;
grant execute on function public.get_linked_alternatives(uuid) to authenticated;
