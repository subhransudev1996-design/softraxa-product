-- ============================================================
-- 0001_core.sql — extensions, enums, tenancy (businesses, profiles)
-- Run first, in the Supabase SQL editor.
-- ============================================================

create extension if not exists "uuid-ossp";

-- ---------- Enums ----------
create type public.user_role as enum ('owner', 'admin');
create type public.business_type as enum ('mobile', 'garment', 'hardware', 'other');
create type public.tax_preference as enum ('gst', 'non_gst');
create type public.subscription_status as enum ('trial', 'active', 'expired', 'suspended');
create type public.invoice_type as enum ('gst', 'non_gst', 'cash_memo', 'estimate');
create type public.payment_status as enum ('paid', 'partial', 'unpaid');
create type public.payment_mode as enum ('cash', 'upi', 'card', 'credit', 'other');
create type public.movement_type as enum
  ('opening', 'purchase', 'sale', 'sale_return', 'purchase_return', 'adjustment', 'damage', 'import');
create type public.ticket_status as enum ('open', 'in_progress', 'resolved');

-- ---------- updated_at helper ----------
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ---------- Businesses (one row per client shop) ----------
create table public.businesses (
  id              uuid primary key default gen_random_uuid(),
  name            text not null,
  owner_name      text not null default '',
  business_type   public.business_type not null default 'other',
  phone           text not null default '',
  email           text not null default '',
  address         text not null default '',
  gst_number      text not null default '',
  logo_url        text,
  invoice_prefix  text not null default 'INV',
  tax_preference  public.tax_preference not null default 'gst',
  is_active       boolean not null default true,
  setup_complete  boolean not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create trigger trg_businesses_updated before update on public.businesses
  for each row execute function public.set_updated_at();

-- ---------- Profiles (auth.users <-> business) ----------
create table public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  business_id uuid references public.businesses(id) on delete set null,
  role        public.user_role not null default 'owner',
  full_name   text not null default '',
  email       text not null default '',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index idx_profiles_business on public.profiles(business_id);
create trigger trg_profiles_updated before update on public.profiles
  for each row execute function public.set_updated_at();

-- Auto-create a profile row whenever an auth user is created.
-- Role is always 'owner' here — admin users are promoted manually:
--   update public.profiles set role = 'admin' where email = '<you>';
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, full_name, role)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    'owner'
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- RLS helper functions ----------
create or replace function public.current_business_id()
returns uuid language sql stable security definer set search_path = public as $$
  select business_id from public.profiles where id = auth.uid()
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select role = 'admin' from public.profiles where id = auth.uid()), false)
$$;

-- ---------- Per-business feature flags (PRD 8.5) ----------
create table public.feature_flags (
  business_id      uuid primary key references public.businesses(id) on delete cascade,
  gst_billing      boolean not null default true,
  barcode_scanning boolean not null default true,
  excel_import     boolean not null default true,
  reports          boolean not null default true,
  pdf_invoice      boolean not null default true,
  thermal_print    boolean not null default true,
  a4_print         boolean not null default true,
  offline_billing  boolean not null default true,
  expense_module   boolean not null default true,
  updated_at       timestamptz not null default now()
);
create trigger trg_feature_flags_updated before update on public.feature_flags
  for each row execute function public.set_updated_at();

-- ---------- Per-business document number counters ----------
-- doc_type: 'invoice' | 'cash_memo' | 'estimate' | 'purchase' | 'sale_return' | 'purchase_return'
create table public.doc_counters (
  business_id uuid not null references public.businesses(id) on delete cascade,
  doc_type    text not null,
  counter     bigint not null default 0,
  primary key (business_id, doc_type)
);
