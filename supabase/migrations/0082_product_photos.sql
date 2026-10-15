-- ============================================================
-- 0082_product_photos.sql
--
-- Photos on the shared product list (master products).
--   * master_products.image_url — set by SOFTRAXA in the admin panel
--     (admin_set_master_product_image). Photos are uploaded to ImageKit;
--     only the address is stored here. Shop photos never flow into the
--     shared list: a shop's photo is of its own shelf.
--   * A shop that adds a product from the list gets its photo: a trigger
--     on products copies it when the new product is linked to a master
--     product and has no photo of its own. It covers every way a product
--     is added (product form, Suggested products, a name that matches the
--     list).
--   * search_master_products and browse_master_products return the photo
--     so the app can show it while the shop picks.
--
-- Shops' own product photos need no change here: products.image_url
-- exists since 0003 and the app now uploads to it.
--
-- Run AFTER 0081.
-- ============================================================

alter table public.master_products add column if not exists image_url text;
alter table public.master_products drop constraint if exists master_products_image_url_check;
alter table public.master_products add constraint master_products_image_url_check
  check (image_url is null or image_url ~ '^https://[^ ]+$');

-- ============================================================
-- A. SOFTRAXA sets or clears a photo (logged)
-- ============================================================
create or replace function public.admin_set_master_product_image(p_id uuid, p_url text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_url text := nullif(btrim(coalesce(p_url, '')), '');
  v_old text;
  v_name text;
begin
  perform public.assert_platform_admin();
  if v_url is not null and v_url !~ '^https://[^ ]+$' then
    raise exception 'The photo address must start with https://';
  end if;
  select image_url, name into v_old, v_name from public.master_products where id = p_id for update;
  if v_name is null then raise exception 'Product not found'; end if;
  update public.master_products set image_url = v_url, updated_at = now() where id = p_id;
  perform public.admin_log(null, 'master_product.photo', 'master_product', p_id::text,
    jsonb_build_object('name', v_name, 'before', v_old, 'after', v_url));
end $$;

revoke execute on function public.admin_set_master_product_image(uuid, text) from public, anon;
grant execute on function public.admin_set_master_product_image(uuid, text) to authenticated;

-- ============================================================
-- B. New shop products take the list's photo
-- ============================================================
-- Runs after trg_products_master (triggers of the same kind run in name
-- order), so a product the name-match just linked gets the photo too.
create or replace function public.copy_master_product_image()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- Null only: '' means the shop removed the list's photo on purpose.
  if new.master_product_id is not null and new.image_url is null then
    select m.image_url into new.image_url
      from public.master_products m
      where m.id = new.master_product_id and m.status = 'published';
  end if;
  return new;
end $$;

revoke execute on function public.copy_master_product_image() from public, anon, authenticated;

drop trigger if exists trg_products_master_photo on public.products;
create trigger trg_products_master_photo
  before insert on public.products
  for each row execute function public.copy_master_product_image();

-- ============================================================
-- C. Shops see the photo while picking (0057 and 0066, plus image_url)
-- ============================================================
create or replace function public.search_master_products(p_query text, p_limit integer default 10)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_key      text := public.master_name_key(p_query);
  v_code     text := btrim(coalesce(p_query, ''));
  v_type     text;
begin
  if v_business is null then raise exception 'No shop selected'; end if;
  if char_length(v_key) < 2 then return '[]'::jsonb; end if;
  select business_type::text into v_type from public.businesses where id = v_business;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', r.id, 'name', r.name, 'brand', r.brand, 'category', r.category,
             'unit_name', r.unit_name, 'unit_short', r.unit_short, 'hsn_code', r.hsn_code,
             'gst_rate', r.gst_rate, 'barcode', r.barcode, 'image_url', r.image_url) order by r.pos)
    from (
      select m.*, row_number() over (
               order by (m.barcode <> '' and m.barcode = v_code) desc,
                        (m.business_type = v_type) desc,
                        (m.name_key like v_key || '%') desc,
                        m.verified desc, m.name) as pos
      from public.master_products m
      where m.status = 'published'
        and (m.name_key like '%' || v_key || '%' or (v_code ~ '^[0-9]{8,14}$' and m.barcode = v_code))
        and not exists (select 1 from public.products p
                        where p.business_id = v_business and p.master_product_id = m.id)
      order by pos
      limit least(greatest(coalesce(p_limit, 10), 1), 30)) r), '[]'::jsonb);
end $$;

create or replace function public.browse_master_products(
  p_type text default '', p_category text default '', p_query text default '',
  p_limit integer default 200, p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_mine     text;
  v_type     text;
  v_key      text := public.master_name_key(p_query);
  v_text     text := lower(btrim(coalesce(p_query, '')));
  v_cat      text := btrim(coalesce(p_category, ''));
  v_limit    integer := least(greatest(coalesce(p_limit, 200), 1), 500);
  v_out      jsonb;
begin
  if v_business is null then raise exception 'No shop selected'; end if;
  select business_type::text into v_mine from public.businesses where id = v_business;
  v_type := coalesce(nullif(btrim(p_type), ''), v_mine);

  with have as (
         select public.master_name_key(name) as k, master_product_id as mid
         from public.products where business_id = v_business),
       avail as (
         select m.*, coalesce(nullif(m.category, ''), 'Other') as cat
         from public.master_products m
         where m.status = 'published'
           and not exists (select 1 from have h where h.mid = m.id or h.k = m.name_key)),
       matched as (
         select * from avail
         where (v_key = '' or name_key like '%' || v_key || '%' or lower(brand) like '%' || v_text || '%')),
       scoped as (
         select * from matched where v_type = '*' or business_type = v_type),
       picked as (
         select * from scoped where v_cat = '' or cat = v_cat)
  select jsonb_build_object(
    'type', v_type,
    'mine', v_mine,
    'total', (select count(*) from picked),
    'types', coalesce((select jsonb_agg(jsonb_build_object('type', t.business_type, 'count', t.c)
                                        order by t.c desc)
                       from (select business_type, count(*) as c from matched
                             where business_type <> '' group by 1) t), '[]'::jsonb),
    'categories', coalesce((select jsonb_agg(jsonb_build_object('category', c.cat, 'count', c.n)
                                             order by c.cat)
                            from (select cat, count(*) as n from scoped group by 1) c), '[]'::jsonb),
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
                'id', r.id, 'name', r.name, 'brand', r.brand, 'category', r.cat,
                'unit_name', r.unit_name, 'unit_short', r.unit_short, 'allow_decimal', r.allow_decimal,
                'gst_rate', r.gst_rate, 'hsn_code', r.hsn_code, 'business_type', r.business_type,
                'image_url', r.image_url)
                order by r.cat, r.name)
              from (select * from picked order by cat, name
                    limit v_limit offset greatest(coalesce(p_offset, 0), 0)) r), '[]'::jsonb))
  into v_out;
  return v_out;
end $$;
