-- ============================================================
-- 0035_imei_serial_helpers.sql — IMEI/Serial number management RPCs
-- ============================================================

-- ---------- RPC: Batch insert IMEIs / Serial numbers ----------
create or replace function public.add_product_serials(
  p_product_id uuid,
  p_variant_id uuid default null,
  p_serials    text[] default array[]::text[],
  p_purchase_id uuid default null
)
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_s text;
  v_count integer := 0;
begin
  if v_business is null then raise exception 'Not authenticated or missing business'; end if;

  foreach v_s in array p_serials loop
    v_s := trim(v_s);
    if v_s <> '' then
      insert into public.product_serials
        (business_id, product_id, variant_id, serial_no, status, purchase_id)
      values
        (v_business, p_product_id, p_variant_id, v_s, 'in_stock', p_purchase_id)
      on conflict (business_id, serial_no)
      do update set status = 'in_stock', product_id = p_product_id, variant_id = p_variant_id;

      v_count := v_count + 1;
    end if;
  end loop;

  return v_count;
end $$;

-- ---------- RPC: Get available in-stock serials for product / variant ----------
create or replace function public.get_available_serials(
  p_product_id uuid,
  p_variant_id uuid default null
)
returns table (
  id uuid,
  serial_no text,
  status text,
  created_at timestamptz
) language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
begin
  return query
  select ps.id, ps.serial_no, ps.status, ps.created_at
  from public.product_serials ps
  where ps.business_id = v_business
    and ps.product_id = p_product_id
    and (p_variant_id is null or ps.variant_id = p_variant_id)
    and ps.status = 'in_stock'
  order by ps.created_at desc;
end $$;
