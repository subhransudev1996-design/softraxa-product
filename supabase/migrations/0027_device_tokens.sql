-- FCM device tokens for push notifications (low stock / expiry / jobs due).
-- One row per device; the app upserts its token on login and on token
-- refresh. The push-alerts Edge Function (service role) reads all tokens,
-- groups by business, and deletes rows FCM reports as unregistered.
create table public.device_tokens (
  id          uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  token       text not null unique,
  platform    text not null default 'android',
  updated_at  timestamptz not null default now()
);
create index idx_device_tokens_business on public.device_tokens(business_id);

alter table public.device_tokens enable row level security;
create policy "tenant all" on public.device_tokens for all
  using (business_id = public.current_business_id() or public.is_admin())
  with check (business_id = public.current_business_id() or public.is_admin());
