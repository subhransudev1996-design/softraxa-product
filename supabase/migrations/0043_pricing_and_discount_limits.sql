-- ============================================================
-- 0043_pricing_and_discount_limits.sql — release R1, batch 4
-- (LAUNCH_SPECIFICATION.md D14–D16, PD05, PD07, PD08)
--
--   A. Customer-specific prices and wholesale customers
--   B. Default price per line (D15): customer price → wholesale (customer
--      marked wholesale, or the product's quantity tier reached on the
--      bill, PD05) → retail. Each bill line records the default price and
--      which price was charged (retail / wholesale / customer / negotiated).
--   C. Staff discount limits (PD07): one percentage per staff member,
--      measured as the whole bill's reduction from its default prices —
--      price changes, line discounts and the bill discount together, so
--      small repeated discounts or a price edit can't get round it. New
--      staff start at 0% (PD08). Owners are not limited.
--      Checked when a bill is created or edited (create_invoice /
--      update_invoice wrappers), so it holds for direct API calls too.
--
-- Run AFTER 0042.
-- ============================================================

-- ============================================================
-- A. Price data
-- ============================================================
create table if not exists public.customer_prices (
  id          uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  product_id  uuid not null references public.products(id) on delete cascade,
  variant_id  uuid references public.product_variants(id) on delete cascade,
  price       numeric(12,2) not null check (price > 0),   -- same basis as selling_price
  note        text not null default '',
  updated_by  uuid references public.profiles(id),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique nulls not distinct (customer_id, product_id, variant_id)
);
create index if not exists idx_customer_prices_customer on public.customer_prices (customer_id);

alter table public.customer_prices enable row level security;
drop policy if exists "tenant read" on public.customer_prices;
drop policy if exists "tenant insert" on public.customer_prices;
drop policy if exists "tenant update" on public.customer_prices;
drop policy if exists "tenant delete" on public.customer_prices;
drop policy if exists "admin all" on public.customer_prices;
create policy "tenant read" on public.customer_prices for select
  using (business_id = (select public.current_business_id()));
-- Maintaining agreed prices is part of the price permission.
create policy "tenant insert" on public.customer_prices for insert
  with check (business_id = (select public.current_business_id())
              and (select public.has_permission('can_edit_prices'))
              and (select public.business_is_writable(public.current_business_id())));
create policy "tenant update" on public.customer_prices for update
  using (business_id = (select public.current_business_id())
         and (select public.has_permission('can_edit_prices')))
  with check (business_id = (select public.current_business_id())
              and (select public.has_permission('can_edit_prices'))
              and (select public.business_is_writable(public.current_business_id())));
create policy "tenant delete" on public.customer_prices for delete
  using (business_id = (select public.current_business_id())
         and (select public.has_permission('can_edit_prices')));
create policy "admin all" on public.customer_prices for all
  using (public.is_admin()) with check (public.is_admin());

drop trigger if exists trg_00_tenant_refs on public.customer_prices;
create trigger trg_00_tenant_refs before insert or update on public.customer_prices
  for each row execute function public.enforce_tenant_refs(
    'customer_id=customers', 'product_id=products', 'variant_id=product_variants');

create or replace function public.stamp_customer_price()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  new.updated_by := coalesce(auth.uid(), new.updated_by);
  return new;
end $$;
drop trigger if exists trg_customer_prices_stamp on public.customer_prices;
create trigger trg_customer_prices_stamp before insert or update on public.customer_prices
  for each row execute function public.stamp_customer_price();

alter table public.customers add column if not exists is_wholesale boolean not null default false;

-- Replaces 0041's version: adds the wholesale flag, which changes a
-- customer's prices, so it needs the price permission.
create or replace function public.guard_party_columns()
returns trigger language plpgsql as $$
begin
  if public.is_direct_api_write() then
    if tg_op = 'INSERT' then
      new.due_amount := 0;
      if tg_table_name = 'customers' then new.advance_amount := 0; end if;
    elsif new.due_amount is distinct from old.due_amount then
      raise exception 'Balances can only change through bills, purchases and payments'
        using errcode = '42501';
    elsif tg_table_name = 'customers' and new.advance_amount is distinct from old.advance_amount then
      raise exception 'Advances can only change through payments, returns and refunds'
        using errcode = '42501';
    end if;
  end if;

  if tg_table_name = 'customers' and auth.uid() is not null then
    if not public.has_permission('owner') then
      if tg_op = 'INSERT' then
        new.credit_unlimited := false;
        new.credit_limit := null;          -- store default, via normalize_customer_credit
      elsif new.credit_limit is distinct from old.credit_limit
         or new.credit_unlimited is distinct from old.credit_unlimited then
        raise exception 'Only the owner can change credit limits' using errcode = '42501';
      end if;
    end if;
    if not public.has_permission('can_edit_prices') then
      if tg_op = 'INSERT' then
        new.is_wholesale := false;
      elsif new.is_wholesale is distinct from old.is_wholesale then
        raise exception 'You don''t have permission to change a customer''s prices' using errcode = '42501';
      end if;
    end if;
  end if;
  return new;
end $$;

-- ============================================================
-- B. Default price per line, recorded on the bill
-- ============================================================
alter table public.invoice_items add column if not exists list_price numeric(12,2);      -- default price per unit
alter table public.invoice_items add column if not exists price_source text not null default '';
alter table public.invoices add column if not exists default_total numeric(14,2) not null default 0;
alter table public.invoices add column if not exists price_reduction numeric(14,2) not null default 0;

-- ============================================================
-- C. Staff discount limits
-- ============================================================
alter table public.staff_permissions add column if not exists discount_limit_pct numeric(5,2) not null default 0;
alter table public.staff_permissions drop constraint if exists staff_permissions_discount_limit_check;
alter table public.staff_permissions add constraint staff_permissions_discount_limit_check
  check (discount_limit_pct between 0 and 100);

-- Each line of a bill with its effective and default unit price. Prices
-- are per unit on the display basis the POS uses: GST invoices
-- tax-inclusive (like selling_price), others as charged. The wholesale
-- tier is judged on the product's total quantity on the bill (PD05).
create or replace function public.invoice_price_lines(p_invoice uuid)
returns table (id uuid, quantity numeric, eff numeric, def numeric, def_source text,
               retail numeric, wholesale numeric, customer numeric)
language sql stable security definer set search_path = public as $$
  with i as (
    select inv.id, inv.invoice_type, inv.customer_id,
           coalesce((select c.is_wholesale from public.customers c where c.id = inv.customer_id), false)
             as wholesale_customer
    from public.invoices inv where inv.id = p_invoice),
  l as (
    select ii.id, ii.quantity,
           (ii.quantity * ii.unit_price - ii.discount_amount) / nullif(ii.quantity, 0)
             * case when i.invoice_type = 'gst' then 1 + ii.gst_rate / 100 else 1 end as eff,
           nullif(coalesce(pv.selling_price, p.selling_price), 0) as retail,
           nullif(p.wholesale_price, 0) as wholesale,
           p.wholesale_min_qty,
           cp.price as customer,
           i.wholesale_customer,
           sum(ii.quantity) over (partition by ii.product_id, ii.variant_id) as product_qty
    from i
    join public.invoice_items ii on ii.invoice_id = i.id
    left join public.products p on p.id = ii.product_id
    left join public.product_variants pv on pv.id = ii.variant_id
    left join public.customer_prices cp
      on cp.customer_id = i.customer_id and cp.product_id = ii.product_id
     and cp.variant_id is not distinct from ii.variant_id),
  t as (
    select l.*, (l.wholesale is not null
                 and (l.wholesale_customer
                      or (l.wholesale_min_qty is not null and l.product_qty >= l.wholesale_min_qty))) as ws
    from l)
  select t.id, t.quantity, t.eff,
         case when t.customer is not null then t.customer when t.ws then t.wholesale else t.retail end,
         case when t.customer is not null then 'customer' when t.ws then 'wholesale'
              when t.retail is not null then 'retail' else '' end,
         t.retail, t.wholesale, t.customer
  from t;
$$;
revoke execute on function public.invoice_price_lines(uuid) from public, anon, authenticated;

-- Stamps each line's default price and source, stores the bill's default
-- total and reduction, then enforces the caller's limit.
create or replace function public.check_invoice_pricing(p_invoice uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_inv       record;
  v_default   numeric := 0;
  v_actual    numeric := 0;
  v_reduction numeric := 0;
  v_role      text;
  v_limit     numeric;
  v_pct       numeric;
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

  update public.invoices set default_total = round(v_default, 2), price_reduction = v_reduction
    where id = p_invoice;

  -- Enforcement: staff only, and not for estimates (not a sale).
  if v_inv.invoice_type <> 'estimate' and auth.uid() is not null and v_reduction > 0.05 then
    select role::text into v_role from public.profiles where id = auth.uid();
    if coalesce(v_role, '') not in ('owner', 'admin') then
      if not public.has_permission('can_edit_prices') then
        raise exception 'This bill is ₹% below the default prices — you don''t have permission to change prices or give discounts',
          v_reduction using errcode = '42501';
      end if;
      select coalesce(discount_limit_pct, 0) into v_limit
        from public.staff_permissions where profile_id = auth.uid();
      v_limit := coalesce(v_limit, 0);
      v_pct := case when v_default > 0 then round(v_reduction / v_default * 100, 2) else 100 end;
      if v_reduction > v_default * v_limit / 100 + 0.05 then
        raise exception '%', format(
          'This bill is ₹%s (%s%%) below the default prices — your discount limit is %s%%. Ask the owner.',
          v_reduction, v_pct, v_limit) using errcode = '42501';
      end if;
    end if;
  end if;

  return jsonb_build_object('default_total', round(v_default, 2), 'reduction', v_reduction);
end $$;

revoke execute on function public.check_invoice_pricing(uuid) from public, anon, authenticated;

-- Per-line price guard (0037) is replaced by the bill-level check above:
-- it compared against the catalogue price only and couldn't see customer
-- prices or the bill discount.
create or replace function public.guard_invoice_items()
returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    perform public.assert_can('can_edit_invoices');
    return old;
  end if;
  -- New bills need create permission; re-inserting lines while editing a
  -- bill (update_invoice) is covered by edit permission.
  if public.has_permission('can_create_invoice') then
    perform public.assert_can('can_create_invoice');
  else
    perform public.assert_can('can_edit_invoices');
  end if;
  return new;
end $$;

-- create_invoice / update_invoice: keep the bodies as *_impl and check
-- pricing once the whole bill (all lines + bill discount) is written.
do $$
begin
  if not exists (select 1 from pg_proc where proname = 'create_invoice_impl') then
    alter function public.create_invoice(jsonb) rename to create_invoice_impl;
  end if;
  if not exists (select 1 from pg_proc where proname = 'update_invoice_impl') then
    alter function public.update_invoice(uuid, jsonb) rename to update_invoice_impl;
  end if;
end $$;
revoke execute on function public.create_invoice_impl(jsonb) from public, anon, authenticated;
revoke execute on function public.update_invoice_impl(uuid, jsonb) from public, anon, authenticated;

create or replace function public.create_invoice(payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v jsonb;
begin
  v := public.create_invoice_impl(payload);
  if not coalesce((v ->> 'already_synced')::boolean, false) then
    perform public.check_invoice_pricing((v ->> 'id')::uuid);
  end if;
  return v;
end $$;

create or replace function public.update_invoice(p_invoice_id uuid, payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v jsonb;
begin
  v := public.update_invoice_impl(p_invoice_id, payload);
  perform public.check_invoice_pricing(p_invoice_id);
  return v;
end $$;

revoke execute on function public.create_invoice(jsonb) from public, anon;
revoke execute on function public.update_invoice(uuid, jsonb) from public, anon;
grant execute on function public.create_invoice(jsonb) to authenticated;
grant execute on function public.update_invoice(uuid, jsonb) to authenticated;

-- Owner sets a staff member's limit (percent of the bill's default total).
create or replace function public.set_staff_discount_limit(p_profile uuid, p_pct numeric)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
begin
  perform public.assert_can('owner');
  if p_pct is null or p_pct < 0 or p_pct > 100 then
    raise exception 'The limit must be between 0 and 100 percent';
  end if;
  if not exists (select 1 from public.profiles
                 where id = p_profile and business_id = v_business and role::text <> 'owner') then
    raise exception 'Staff member not found';
  end if;
  perform public.write_staff_permissions(p_profile, v_business, '{}'::jsonb);  -- make sure a row exists
  update public.staff_permissions set discount_limit_pct = round(p_pct, 2), updated_at = now()
    where profile_id = p_profile;
  perform public.log_audit('staff.discount_limit', 'profile', p_profile::text,
    jsonb_build_object('discount_limit_pct', round(p_pct, 2)));
end $$;

-- The caller's own pricing rights, for the POS to warn before saving.
create or replace function public.get_my_pricing_rights()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_role  text;
  v_limit numeric;
begin
  select role::text into v_role from public.profiles where id = auth.uid();
  if v_role in ('owner', 'admin') then
    return jsonb_build_object('unlimited', true, 'can_edit_prices', true, 'discount_limit_pct', 100);
  end if;
  select discount_limit_pct into v_limit from public.staff_permissions where profile_id = auth.uid();
  return jsonb_build_object(
    'unlimited', false,
    'can_edit_prices', public.has_permission('can_edit_prices'),
    'discount_limit_pct', coalesce(v_limit, 0));
end $$;

revoke execute on function public.set_staff_discount_limit(uuid, numeric) from public, anon;
revoke execute on function public.get_my_pricing_rights() from public, anon;
grant execute on function public.set_staff_discount_limit(uuid, numeric) to authenticated;
grant execute on function public.get_my_pricing_rights() to authenticated;
