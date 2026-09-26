-- ============================================================
-- 0034_staff_permissions.sql — Staff User Management & Granular Permissions
-- ============================================================

-- 1. Add 'staff' and 'manager' values to public.user_role enum if not already present
do $$
begin
  if not exists (select 1 from pg_enum where enumlabel = 'staff' and enumtypid = 'public.user_role'::regtype) then
    alter type public.user_role add value 'staff';
  end if;
  if not exists (select 1 from pg_enum where enumlabel = 'manager' and enumtypid = 'public.user_role'::regtype) then
    alter type public.user_role add value 'manager';
  end if;
end $$;

-- 2. Staff Permissions table
create table if not exists public.staff_permissions (
  profile_id           uuid primary key references public.profiles(id) on delete cascade,
  business_id          uuid not null references public.businesses(id) on delete cascade,
  can_create_invoice   boolean not null default true,
  can_edit_prices      boolean not null default false,
  can_view_profit      boolean not null default false,
  can_manage_products  boolean not null default true,
  can_manage_stock     boolean not null default false,
  can_manage_expenses  boolean not null default false,
  can_manage_services  boolean not null default true,
  can_view_reports     boolean not null default false,
  can_manage_staff     boolean not null default false,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

create index if not exists idx_staff_permissions_business on public.staff_permissions(business_id);

create trigger trg_staff_permissions_updated before update on public.staff_permissions
  for each row execute function public.set_updated_at();

-- RLS for staff_permissions
alter table public.staff_permissions enable row level security;

drop policy if exists "Users can view staff permissions in their business" on public.staff_permissions;
create policy "Users can view staff permissions in their business" on public.staff_permissions
  for select using (business_id = public.current_business_id());

drop policy if exists "Owners can manage staff permissions" on public.staff_permissions;
create policy "Owners can manage staff permissions" on public.staff_permissions
  for all using (
    business_id = public.current_business_id() and
    exists (select 1 from public.profiles where id = auth.uid() and role in ('owner', 'admin'))
  );

-- 3. RPC: Create a staff user (store owner creates staff)
create or replace function public.create_staff_user(
  p_email text,
  p_password text,
  p_full_name text,
  p_permissions jsonb default '{}'::jsonb
)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_caller_profile record;
  v_business_id uuid;
  v_user_limit integer;
  v_current_staff integer;
  v_new_user_id uuid;
begin
  -- Caller validation: must be authenticated and owner/admin of a business
  select * into v_caller_profile from public.profiles where id = auth.uid();
  if v_caller_profile is null or v_caller_profile.business_id is null then
    raise exception 'Not authorized: no business linked to profile';
  end if;

  if v_caller_profile.role not in ('owner', 'admin') then
    raise exception 'Only store owners can add staff users';
  end if;

  v_business_id := v_caller_profile.business_id;

  -- Get staff user limit from active subscription / plan
  select coalesce(pl.user_limit, 1) into v_user_limit
  from public.subscriptions s
  left join public.plans pl on pl.id = s.plan_id
  where s.business_id = v_business_id
  order by s.created_at desc limit 1;

  if v_user_limit is null then
    v_user_limit := 999; -- null in plan means unlimited
  end if;

  -- Count total profiles for this business
  select count(*) into v_current_staff from public.profiles where business_id = v_business_id;

  -- If total profiles (owner + staff) >= user_limit, block creation
  if v_current_staff >= v_user_limit then
    raise exception 'Staff limit reached (% allowed on your plan). Upgrade your plan to add more staff.', v_user_limit;
  end if;

  -- Create the auth user in auth.users
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_user_meta_data, created_at, updated_at
  ) values (
    '00000000-0000-0000-0000-000000000000',
    gen_random_uuid(),
    'authenticated',
    'authenticated',
    p_email,
    crypt(p_password, gen_salt('bf')),
    now(),
    jsonb_build_object('full_name', p_full_name),
    now(),
    now()
  ) returning id into v_new_user_id;

  -- Update the auto-created profile to link business_id and role = 'staff'
  update public.profiles
  set business_id = v_business_id,
      role = 'staff',
      full_name = p_full_name,
      email = p_email
  where id = v_new_user_id;

  -- Insert staff permissions
  insert into public.staff_permissions (
    profile_id, business_id,
    can_create_invoice, can_edit_prices, can_view_profit,
    can_manage_products, can_manage_stock, can_manage_expenses,
    can_manage_services, can_view_reports, can_manage_staff
  ) values (
    v_new_user_id, v_business_id,
    coalesce((p_permissions ->> 'can_create_invoice')::boolean, true),
    coalesce((p_permissions ->> 'can_edit_prices')::boolean, false),
    coalesce((p_permissions ->> 'can_view_profit')::boolean, false),
    coalesce((p_permissions ->> 'can_manage_products')::boolean, true),
    coalesce((p_permissions ->> 'can_manage_stock')::boolean, false),
    coalesce((p_permissions ->> 'can_manage_expenses')::boolean, false),
    coalesce((p_permissions ->> 'can_manage_services')::boolean, true),
    coalesce((p_permissions ->> 'can_view_reports')::boolean, false),
    coalesce((p_permissions ->> 'can_manage_staff')::boolean, false)
  );

  return jsonb_build_object('user_id', v_new_user_id, 'email', p_email);
end $$;

-- 4. RPC: Update staff permissions
create or replace function public.update_staff_permissions(
  p_profile_id uuid,
  p_permissions jsonb
)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_caller_profile record;
  v_target_profile record;
begin
  select * into v_caller_profile from public.profiles where id = auth.uid();
  if v_caller_profile is null or v_caller_profile.role not in ('owner', 'admin') then
    raise exception 'Not authorized';
  end if;

  select * into v_target_profile from public.profiles where id = p_profile_id;
  if v_target_profile is null or v_target_profile.business_id != v_caller_profile.business_id then
    raise exception 'Target staff member not found in your store';
  end if;

  insert into public.staff_permissions (
    profile_id, business_id,
    can_create_invoice, can_edit_prices, can_view_profit,
    can_manage_products, can_manage_stock, can_manage_expenses,
    can_manage_services, can_view_reports, can_manage_staff
  ) values (
    p_profile_id, v_caller_profile.business_id,
    coalesce((p_permissions ->> 'can_create_invoice')::boolean, true),
    coalesce((p_permissions ->> 'can_edit_prices')::boolean, false),
    coalesce((p_permissions ->> 'can_view_profit')::boolean, false),
    coalesce((p_permissions ->> 'can_manage_products')::boolean, true),
    coalesce((p_permissions ->> 'can_manage_stock')::boolean, false),
    coalesce((p_permissions ->> 'can_manage_expenses')::boolean, false),
    coalesce((p_permissions ->> 'can_manage_services')::boolean, true),
    coalesce((p_permissions ->> 'can_view_reports')::boolean, false),
    coalesce((p_permissions ->> 'can_manage_staff')::boolean, false)
  )
  on conflict (profile_id) do update set
    can_create_invoice   = coalesce((p_permissions ->> 'can_create_invoice')::boolean, public.staff_permissions.can_create_invoice),
    can_edit_prices      = coalesce((p_permissions ->> 'can_edit_prices')::boolean, public.staff_permissions.can_edit_prices),
    can_view_profit      = coalesce((p_permissions ->> 'can_view_profit')::boolean, public.staff_permissions.can_view_profit),
    can_manage_products  = coalesce((p_permissions ->> 'can_manage_products')::boolean, public.staff_permissions.can_manage_products),
    can_manage_stock     = coalesce((p_permissions ->> 'can_manage_stock')::boolean, public.staff_permissions.can_manage_stock),
    can_manage_expenses  = coalesce((p_permissions ->> 'can_manage_expenses')::boolean, public.staff_permissions.can_manage_expenses),
    can_manage_services  = coalesce((p_permissions ->> 'can_manage_services')::boolean, public.staff_permissions.can_manage_services),
    can_view_reports     = coalesce((p_permissions ->> 'can_view_reports')::boolean, public.staff_permissions.can_view_reports),
    can_manage_staff     = coalesce((p_permissions ->> 'can_manage_staff')::boolean, public.staff_permissions.can_manage_staff),
    updated_at           = now();
end $$;

-- 5. RPC: Delete / Revoke staff user access
create or replace function public.delete_staff_user(p_profile_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_caller_profile record;
  v_target_profile record;
begin
  select * into v_caller_profile from public.profiles where id = auth.uid();
  if v_caller_profile is null or v_caller_profile.role not in ('owner', 'admin') then
    raise exception 'Not authorized';
  end if;

  select * into v_target_profile from public.profiles where id = p_profile_id;
  if v_target_profile is null or v_target_profile.business_id != v_caller_profile.business_id then
    raise exception 'Staff member not found in your store';
  end if;

  if v_target_profile.role = 'owner' then
    raise exception 'Cannot delete the store owner profile';
  end if;

  -- Delete auth user (cascades to profiles & staff_permissions)
  delete from auth.users where id = p_profile_id;
end $$;

-- 6. Update public.get_my_context() RPC to include permissions and staff usage
create or replace function public.get_my_context()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_profile record;
  v_user_limit integer;
  v_current_staff integer;
begin
  select * into v_profile from public.profiles where id = auth.uid();

  -- Calculate staff limits
  select coalesce(pl.user_limit, 1) into v_user_limit
  from public.subscriptions s
  left join public.plans pl on pl.id = s.plan_id
  where s.business_id = v_business
  order by s.created_at desc limit 1;

  if v_user_limit is null then v_user_limit := 999; end if;

  select count(*) into v_current_staff from public.profiles where business_id = v_business;

  return jsonb_build_object(
    'profile',  to_jsonb(v_profile),
    'business', (select to_jsonb(b) from public.businesses b where b.id = v_business),
    'features', (select to_jsonb(f) from public.feature_flags f where f.business_id = v_business),
    'permissions', (
      case
        when v_profile.role in ('owner', 'admin') then
          jsonb_build_object(
            'can_create_invoice', true, 'can_edit_prices', true, 'can_view_profit', true,
            'can_manage_products', true, 'can_manage_stock', true, 'can_manage_expenses', true,
            'can_manage_services', true, 'can_view_reports', true, 'can_manage_staff', true
          )
        else
          coalesce(
            (select to_jsonb(sp) from public.staff_permissions sp where sp.profile_id = auth.uid()),
            jsonb_build_object(
              'can_create_invoice', true, 'can_edit_prices', false, 'can_view_profit', false,
              'can_manage_products', true, 'can_manage_stock', false, 'can_manage_expenses', false,
              'can_manage_services', true, 'can_view_reports', false, 'can_manage_staff', false
            )
          )
      end
    ),
    'subscription', (
      select to_jsonb(s) || jsonb_build_object(
        'plan', to_jsonb(pl),
        'user_limit', v_user_limit,
        'staff_count', v_current_staff
      )
      from public.subscriptions s left join public.plans pl on pl.id = s.plan_id
      where s.business_id = v_business
      order by s.created_at desc limit 1)
  );
end $$;

grant execute on function public.create_staff_user(text, text, text, jsonb) to authenticated;
grant execute on function public.update_staff_permissions(uuid, jsonb) to authenticated;
grant execute on function public.delete_staff_user(uuid) to authenticated;
