-- ============================================================
-- 0026_crm.sql — leads / sales pipeline for the admin panel
-- (mini-CRM: leads, statuses, sources, activities, conversion)
-- Admin-only tables: shop owners never see these.
-- ============================================================

create type public.lead_status as enum
  ('new', 'contacted', 'demo', 'converted', 'lost');

-- ---------- Leads ----------
create table public.leads (
  id                     uuid primary key default gen_random_uuid(),
  shop_name              text not null,
  contact_name           text not null default '',
  phone                  text not null default '',
  email                  text not null default '',
  city                   text not null default '',
  business_type          public.business_type not null default 'other',
  source                 text not null default 'other',
    -- walk_in | referral | field_visit | phone_call | whatsapp | social | other
  status                 public.lead_status not null default 'new',
  interested_plan_id     uuid references public.plans(id) on delete set null,
  expected_value         numeric(12,2),         -- expected yearly value ₹, null = unknown
  follow_up_date         date,
  notes                  text not null default '',
  lost_reason            text not null default '',
  converted_business_id  uuid references public.businesses(id) on delete set null,
  converted_at           timestamptz,
  created_by             uuid references public.profiles(id),
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);
create index idx_leads_status on public.leads(status);
create index idx_leads_follow_up on public.leads(follow_up_date);
create trigger trg_leads_updated before update on public.leads
  for each row execute function public.set_updated_at();

-- ---------- Activity log per lead ----------
create table public.lead_activities (
  id            uuid primary key default gen_random_uuid(),
  lead_id       uuid not null references public.leads(id) on delete cascade,
  activity_type text not null default 'note',
    -- call | whatsapp | visit | demo | note | status_change
  note          text not null default '',
  created_by    uuid references public.profiles(id),
  created_at    timestamptz not null default now()
);
create index idx_lead_activities_lead on public.lead_activities(lead_id, created_at desc);

-- ---------- RLS: admin only ----------
alter table public.leads enable row level security;
create policy "admin manage leads" on public.leads for all
  using (public.is_admin()) with check (public.is_admin());

alter table public.lead_activities enable row level security;
create policy "admin manage lead activities" on public.lead_activities for all
  using (public.is_admin()) with check (public.is_admin());


-- ============================================================
-- Merged from 0026_product_expiry.sql (two migrations shared the 0026 prefix; they are
-- independent, so combining them keeps version numbers unique for the
-- Supabase CLI without changing what gets applied).
-- ============================================================

-- Product expiry tracking (for the notification bell's expired /
-- near-expiry alerts). One optional date per product — batch-level expiry
-- (different dates per purchase lot) is out of scope for V1; shops that
-- need it can model batches as variants.
alter table public.products add column expiry_date date;

comment on column public.products.expiry_date is
  'Optional expiry date; drives the expired/near-expiry alerts in the app''s notification bell.';

-- The alert query filters active products with a non-null expiry_date at or
-- below a cutoff — keep it cheap even for large catalogs.
create index idx_products_expiry on public.products(business_id, expiry_date)
  where expiry_date is not null;
