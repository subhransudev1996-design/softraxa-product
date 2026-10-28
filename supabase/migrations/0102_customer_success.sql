-- ============================================================
-- 0102 — Customer success.
--
--   * admin_shop_health(): every active shop's health score (0–100)
--     with the reasons it lost points, and its onboarding steps
--     (setup, products, customers, bills, staff, logo, UPI);
--   * client_contacts: the team's call log per shop, with a follow-up
--     date (a newer contact closes the older follow-ups);
--   * "How likely are you to recommend Dukania?" (0–10) asked in the app
--     to owners every 90 days after their first 14 days (nps_due,
--     submit_nps); admin_satisfaction() sums it up with support ratings.
-- Reading is for the whole team; logging a contact needs Clients or
-- Support (0098).
-- ============================================================

-- ============================================================
-- A. Call log
-- ============================================================
create table if not exists public.client_contacts (
  id               uuid primary key default gen_random_uuid(),
  business_id      uuid not null references public.businesses(id) on delete cascade,
  kind             text not null default 'call' check (kind in ('call', 'whatsapp', 'visit', 'training', 'note')),
  outcome          text not null default '' check (outcome in ('', 'happy', 'neutral', 'unhappy', 'no_answer')),
  note             text not null default '',
  follow_up_date   date,
  follow_up_done   boolean not null default false,
  created_by       uuid references public.profiles(id) on delete set null,
  created_at       timestamptz not null default now()
);
create index if not exists idx_client_contacts_business on public.client_contacts(business_id, created_at desc);
create index if not exists idx_client_contacts_follow_up on public.client_contacts(follow_up_date) where not follow_up_done;
alter table public.client_contacts enable row level security;
drop policy if exists "admin read" on public.client_contacts;
create policy "admin read" on public.client_contacts for select using (public.is_admin());
-- Written through admin_log_contact / admin_close_follow_up.

create or replace function public.admin_log_contact(p_business uuid, p jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not (public.admin_can('clients') or public.admin_can('support')) then
    raise exception 'You need Clients or Support to log a contact' using errcode = '42501';
  end if;
  if not exists (select 1 from public.businesses where id = p_business) then raise exception 'Client not found'; end if;
  -- A new contact answers the older follow-ups.
  update public.client_contacts set follow_up_done = true
   where business_id = p_business and not follow_up_done;
  insert into public.client_contacts (business_id, kind, outcome, note, follow_up_date, created_by)
  values (p_business, coalesce(nullif(p ->> 'kind', ''), 'call'), coalesce(p ->> 'outcome', ''),
          btrim(coalesce(p ->> 'note', '')), nullif(p ->> 'follow_up_date', '')::date, auth.uid())
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.admin_close_follow_up(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (public.admin_can('clients') or public.admin_can('support')) then
    raise exception 'You need Clients or Support' using errcode = '42501';
  end if;
  update public.client_contacts set follow_up_done = true where id = p_id;
end $$;

-- ============================================================
-- B. How likely to recommend (0–10)
-- ============================================================
create table if not exists public.nps_responses (
  id           uuid primary key default gen_random_uuid(),
  business_id  uuid not null references public.businesses(id) on delete cascade,
  user_id      uuid references public.profiles(id) on delete set null,
  score        smallint check (score between 0 and 10),   -- null = "Not now"
  comment      text not null default '',
  created_at   timestamptz not null default now()
);
create index if not exists idx_nps_business on public.nps_responses(business_id, created_at desc);
alter table public.nps_responses enable row level security;
drop policy if exists "admin read" on public.nps_responses;
create policy "admin read" on public.nps_responses for select using (public.is_admin());

-- Ask the owner? After 14 days; then every 90 days; "Not now" waits 30 days.
create or replace function public.nps_due()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((
    select p.role = 'owner'
       and b.created_at < now() - interval '14 days'
       and not exists (select 1 from public.nps_responses r where r.business_id = b.id
                       and ((r.score is not null and r.created_at > now() - interval '90 days')
                            or (r.score is null and r.created_at > now() - interval '30 days')))
    from public.profiles p join public.businesses b on b.id = p.business_id
    where p.id = auth.uid()), false)
$$;

create or replace function public.submit_nps(p_score integer, p_comment text default '')
returns void language plpgsql security definer set search_path = public as $$
declare v_business uuid := public.current_business_id();
begin
  if v_business is null then raise exception 'No shop'; end if;
  if p_score is not null and p_score not between 0 and 10 then raise exception 'Choose 0 to 10'; end if;
  if not public.nps_due() then return; end if;  -- once per round
  insert into public.nps_responses (business_id, user_id, score, comment)
  values (v_business, auth.uid(), p_score, left(btrim(coalesce(p_comment, '')), 1000));
end $$;

-- NPS (promoters − detractors, last 12 months, latest answer per shop) and support ratings.
create or replace function public.admin_satisfaction()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  if not public.is_admin() then raise exception 'Admin only' using errcode = '42501'; end if;
  with latest as (
    select distinct on (r.business_id) r.*
    from public.nps_responses r
    where r.score is not null and r.created_at > now() - interval '12 months'
    order by r.business_id, r.created_at desc
  )
  select jsonb_build_object(
    'answers', (select count(*) from latest),
    'promoters', (select count(*) from latest where score >= 9),
    'passives', (select count(*) from latest where score between 7 and 8),
    'detractors', (select count(*) from latest where score <= 6),
    'recent', coalesce((select jsonb_agg(x order by x.created_at desc) from (
        select r.id, r.business_id, b.name, r.score, r.comment, r.created_at
        from public.nps_responses r join public.businesses b on b.id = r.business_id
        where r.score is not null order by r.created_at desc limit 50) x), '[]'::jsonb),
    'support_rating', (select round(avg(rating)::numeric, 1) from public.support_tickets
                       where rating is not null and rated_at > now() - interval '90 days'),
    'support_rated', (select count(*) from public.support_tickets
                      where rating is not null and rated_at > now() - interval '90 days'))
  into v;
  return v;
end $$;

-- ============================================================
-- C. Health score and onboarding steps (every active shop, or one)
-- ============================================================
create or replace function public.admin_shop_health(p_business uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_today date := public.ist_date(now());
begin
  if not public.is_admin() then raise exception 'Admin only' using errcode = '42501'; end if;
  return coalesce((
    with base as (
      select b.id, b.name, b.owner_name, b.phone, b.business_type, b.created_at, b.onboarding_done,
             b.logo_url, b.upi_id,
             ls.status::text as status, ls.expiry_date, p.name as plan_name, p.billing,
             (v_today - b.created_at::date) as age_days,
             (select max(i.invoice_date) from public.invoices i where i.business_id = b.id) as last_bill,
             (select count(*) from public.invoices i where i.business_id = b.id
                and i.invoice_date > v_today - 30) as bills_30d,
             (select count(*) from public.invoices i where i.business_id = b.id) as bills_all,
             (select count(*) from public.products x where x.business_id = b.id) as products,
             (select count(*) from public.customers x where x.business_id = b.id) as customers,
             (select count(*) from public.profiles x where x.business_id = b.id and x.role::text in ('staff', 'manager')) as staff,
             (select count(*) from public.support_tickets t where t.business_id = b.id
                and t.kind = 'complaint' and t.status <> 'resolved') as complaints,
             (select round(avg(t.rating)::numeric, 1) from public.support_tickets t where t.business_id = b.id
                and t.rating is not null and t.rated_at > now() - interval '180 days') as rating,
             (select r.score from public.nps_responses r where r.business_id = b.id and r.score is not null
                order by r.created_at desc limit 1) as nps,
             (select max(c.created_at) from public.client_contacts c where c.business_id = b.id) as last_contact,
             (select min(c.follow_up_date) from public.client_contacts c where c.business_id = b.id
                and not c.follow_up_done) as follow_up
      from public.businesses b
      left join public.latest_subscriptions ls on ls.business_id = b.id
      left join public.plans p on p.id = ls.plan_id
      where b.is_active and (p_business is null or b.id = p_business)
    ), scored as (
      select base.*,
        array_remove(array[
          case when bills_all = 0 and age_days > 3 then 'No bill yet (' || age_days || ' days since joining)'
               when last_bill < v_today - 14 then 'No bills for ' || (v_today - last_bill) || ' days'
               when last_bill < v_today - 7 then 'No bills for ' || (v_today - last_bill) || ' days'
               when last_bill < v_today - 3 then 'Quiet for ' || (v_today - last_bill) || ' days' end,
          case when age_days > 14 and bills_all > 0 and bills_30d < 10 then 'Only ' || bills_30d || ' bills in 30 days' end,
          case when products < 5 and age_days > 3 then 'Only ' || products || ' products' end,
          case when not onboarding_done then 'Setup not finished' end,
          case when status = 'expired' then 'Plan expired'
               when status = 'suspended' then 'Suspended'
               -- A trial ending is a chance to sell (Leads), not a risk.
               when status = 'active' and billing is distinct from 'lifetime' and expiry_date between v_today and v_today + 7
                 then 'Plan ends in ' || (expiry_date - v_today) || ' days' end,
          case when complaints > 0 then complaints || ' open complaint' || case when complaints > 1 then 's' else '' end end,
          case when rating < 3 then 'Rated support ' || rating || '★' end,
          case when nps <= 6 then 'Would not recommend us (' || nps || '/10)' end
        ], null) as reasons,
        greatest(0, least(100, 100
          - case when bills_all = 0 and age_days > 3 then 40
                 when last_bill < v_today - 14 then 35
                 when last_bill < v_today - 7 then 20
                 when last_bill < v_today - 3 then 8 else 0 end
          - case when age_days > 14 and bills_all > 0 and bills_30d < 10 then 10 else 0 end
          - case when products < 5 and age_days > 3 then 10 else 0 end
          - case when not onboarding_done then 15 else 0 end
          - case when status in ('expired', 'suspended') then 25
                 when status = 'active' and billing is distinct from 'lifetime' and expiry_date between v_today and v_today + 7 then 10 else 0 end
          - least(complaints * 10, 20)
          - case when rating < 3 then 10 else 0 end
          - case when nps <= 6 then 15 else 0 end)) as score
      from base
    )
    select jsonb_agg(jsonb_build_object(
        'id', id, 'name', name, 'owner_name', owner_name, 'phone', phone, 'business_type', business_type,
        'created_at', created_at, 'status', status, 'expiry_date', expiry_date, 'plan_name', plan_name,
        'billing', billing, 'last_bill', last_bill, 'bills_30d', bills_30d, 'products', products,
        'customers', customers, 'staff', staff, 'complaints', complaints, 'rating', rating, 'nps', nps,
        'last_contact', last_contact, 'follow_up', follow_up,
        'score', score,
        'level', case when score >= 70 then 'healthy' when score >= 40 then 'watch' else 'risk' end,
        'reasons', to_jsonb(reasons),
        'steps', jsonb_build_array(
          jsonb_build_object('key', 'setup', 'label', 'Finished setup', 'done', onboarding_done),
          jsonb_build_object('key', 'product', 'label', 'Added a product', 'done', products > 0),
          jsonb_build_object('key', 'products10', 'label', 'Added 10 products', 'done', products >= 10),
          jsonb_build_object('key', 'customer', 'label', 'Added a customer', 'done', customers > 0),
          jsonb_build_object('key', 'bill', 'label', 'Made the first bill', 'done', bills_all > 0),
          jsonb_build_object('key', 'bills10', 'label', 'Made 10 bills', 'done', bills_all >= 10),
          jsonb_build_object('key', 'staff', 'label', 'Added a staff login', 'done', staff > 0),
          jsonb_build_object('key', 'logo', 'label', 'Put a logo on bills', 'done', coalesce(logo_url, '') <> ''),
          jsonb_build_object('key', 'upi', 'label', 'Set a UPI ID for bills', 'done', coalesce(upi_id, '') <> '')))
      order by score, name)
    from scored), '[]'::jsonb);
end $$;

-- ============================================================
-- Grants
-- ============================================================
revoke execute on function public.admin_log_contact(uuid, jsonb) from public, anon;
revoke execute on function public.admin_close_follow_up(uuid) from public, anon;
revoke execute on function public.nps_due() from public, anon;
revoke execute on function public.submit_nps(integer, text) from public, anon;
revoke execute on function public.admin_satisfaction() from public, anon;
revoke execute on function public.admin_shop_health(uuid) from public, anon;
grant execute on function public.admin_log_contact(uuid, jsonb) to authenticated;
grant execute on function public.admin_close_follow_up(uuid) to authenticated;
grant execute on function public.nps_due() to authenticated;
grant execute on function public.submit_nps(integer, text) to authenticated;
grant execute on function public.admin_satisfaction() to authenticated;
grant execute on function public.admin_shop_health(uuid) to authenticated;
