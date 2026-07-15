-- ============================================================
-- 0002_admin.sql — plans, subscriptions, payments, support, audit
-- ============================================================

-- ---------- Plans (PRD 8.3) ----------
create table public.plans (
  id             uuid primary key default gen_random_uuid(),
  name           text not null,
  monthly_price  numeric(12,2) not null default 0,
  yearly_price   numeric(12,2) not null default 0,
  product_limit  integer,            -- null = unlimited
  invoice_limit  integer,            -- per month, null = unlimited
  duration_days  integer,            -- for custom fixed-duration plans
  is_custom      boolean not null default false,
  is_active      boolean not null default true,
  notes          text not null default '',
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create trigger trg_plans_updated before update on public.plans
  for each row execute function public.set_updated_at();

-- ---------- Subscriptions (PRD 8.4) ----------
create table public.subscriptions (
  id           uuid primary key default gen_random_uuid(),
  business_id  uuid not null references public.businesses(id) on delete cascade,
  plan_id      uuid references public.plans(id) on delete set null,
  status       public.subscription_status not null default 'trial',
  start_date   date not null default current_date,
  expiry_date  date not null,
  grace_days   integer not null default 0,
  notes        text not null default '',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index idx_subscriptions_business on public.subscriptions(business_id);
create trigger trg_subscriptions_updated before update on public.subscriptions
  for each row execute function public.set_updated_at();

-- Manual payment records against subscriptions (PRD 8.4)
create table public.subscription_payments (
  id              uuid primary key default gen_random_uuid(),
  business_id     uuid not null references public.businesses(id) on delete cascade,
  subscription_id uuid references public.subscriptions(id) on delete set null,
  amount          numeric(12,2) not null,
  payment_date    date not null default current_date,
  payment_mode    public.payment_mode not null default 'cash',
  note            text not null default '',
  recorded_by     uuid references public.profiles(id),
  created_at      timestamptz not null default now()
);
create index idx_sub_payments_business on public.subscription_payments(business_id);

-- ---------- Support tickets (PRD 8.6) ----------
create table public.support_tickets (
  id            uuid primary key default gen_random_uuid(),
  business_id   uuid not null references public.businesses(id) on delete cascade,
  subject       text not null,
  message       text not null default '',
  status        public.ticket_status not null default 'open',
  internal_note text not null default '',
  created_by    uuid references public.profiles(id),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index idx_tickets_business on public.support_tickets(business_id);
create trigger trg_tickets_updated before update on public.support_tickets
  for each row execute function public.set_updated_at();

-- ---------- Audit logs (PRD 8.7) ----------
create table public.audit_logs (
  id          bigint generated always as identity primary key,
  business_id uuid references public.businesses(id) on delete cascade,
  user_id     uuid,
  action      text not null,          -- e.g. 'login', 'product.created', 'invoice.created'
  entity      text not null default '',
  entity_id   text not null default '',
  details     jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);
create index idx_audit_business_time on public.audit_logs(business_id, created_at desc);

create or replace function public.log_audit(
  p_action text, p_entity text default '', p_entity_id text default '', p_details jsonb default '{}'::jsonb
) returns void language sql security definer set search_path = public as $$
  insert into public.audit_logs (business_id, user_id, action, entity, entity_id, details)
  values (public.current_business_id(), auth.uid(), p_action, p_entity, p_entity_id, p_details);
$$;

-- ---------- Seed a default trial plan ----------
insert into public.plans (name, monthly_price, yearly_price, product_limit, invoice_limit, notes)
values ('Free Trial', 0, 0, 100, 100, '14-day default trial plan');
