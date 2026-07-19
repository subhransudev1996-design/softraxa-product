-- ============================================================
-- 0031_products.sql — Softraxa SOFTWARE catalog (multi-software)
--
-- Softraxa sells more than one piece of software. This introduces a
-- `software_products` table as the spine so every plan/subscription can name
-- the software it belongs to. For now the software is a LABEL only — the app
-- does not yet enforce access by software — but the structure is ready for
-- entitlements later (features jsonb, trial_days, status).
--
-- NOTE: table is `software_products`, NOT `products`. `public.products`
-- already exists (0003_catalog.sql) and holds each shop's inventory items —
-- a completely different concept. Do not conflate the two.
-- ============================================================

create type public.software_status as enum ('live', 'coming_soon', 'retired');

-- ---------- Software products (the apps Softraxa sells) ----------
create table public.software_products (
  id           uuid primary key default gen_random_uuid(),
  slug         text not null unique,          -- 'dukania', 'salon', ...
  name         text not null,
  tagline      text not null default '',
  description  text not null default '',
  status       public.software_status not null default 'coming_soon',
  trial_days   integer not null default 14,   -- product-level trial length
  features     jsonb not null default '[]'::jsonb,  -- [{key,label}] display + (future) entitlement
  accent_color text not null default '#7c3aed',
  icon         text not null default 'Boxes',  -- lucide icon id
  sort_order   integer not null default 0,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create trigger trg_software_products_updated before update on public.software_products
  for each row execute function public.set_updated_at();

-- ---------- Link plans & subscriptions to a software product ----------
-- Nullable so existing rows stay valid; null = legacy / global.
alter table public.plans
  add column software_id uuid references public.software_products(id) on delete set null;

alter table public.subscriptions
  add column software_id uuid references public.software_products(id) on delete set null;
create index idx_subscriptions_software on public.subscriptions(software_id);

-- Which software a lead is interested in.
alter table public.leads
  add column software_id uuid references public.software_products(id) on delete set null;

-- ---------- RLS ----------
-- Website reads the software list (for the products page); only admins write.
alter table public.software_products enable row level security;
create policy "public read software" on public.software_products for select using (true);
create policy "admin manage software" on public.software_products for all
  using (public.is_admin()) with check (public.is_admin());

-- ---------- Seed: Dukania (live) + coming-soon apps ----------
insert into public.software_products (slug, name, tagline, status, trial_days, icon, accent_color, sort_order) values
  ('dukania',     'Dukania',            'Offline-first billing & inventory for real shops', 'live',        14, 'Store',       '#7c3aed', 0),
  ('salon',       'Salon Manager',      'Membership, appointments & billing for salons',    'coming_soon', 14, 'Scissors',    '#ec4899', 1),
  ('realestate',  'Realty Desk',        'Listings, leads & site-visit management',          'coming_soon', 14, 'Building2',   '#0ea5e9', 2),
  ('coaching',    'Coaching Class',     'Batches, attendance & fee tracking for tuitions',  'coming_soon', 14, 'GraduationCap', '#f59e0b', 3),
  ('repairshop',  'Repair Shop',        'Job cards, spares & service billing',              'coming_soon', 14, 'Wrench',      '#10b981', 4),
  ('freelance',   'Freelance Suite',    'Projects, invoices & client management',           'coming_soon', 14, 'Briefcase',   '#6366f1', 5);

-- ---------- Backfill: everything existing belongs to Dukania ----------
-- (Dukania is the only live software today; all current plans, subscriptions
--  and leads were sold for it.)
update public.plans
  set software_id = (select id from public.software_products where slug = 'dukania')
  where software_id is null;

update public.subscriptions
  set software_id = (select id from public.software_products where slug = 'dukania')
  where software_id is null;
