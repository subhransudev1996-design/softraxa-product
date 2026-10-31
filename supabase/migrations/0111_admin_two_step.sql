-- ============================================================
-- 0111 — Two-step login enforced by the database.
--
-- A team member who has turned on two-step login counts as an admin only
-- when their session has passed it (aal2). Until now only the panel's page
-- checked this, so a stolen password alone could call the API. Every admin
-- check goes through these three functions: table rules, admin_* functions,
-- the panel's API routes and the AI connector. Server jobs are unchanged.
-- ============================================================

create or replace function public.admin_mfa_ok()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(auth.jwt() ->> 'aal', '') = 'aal2'
      or not exists (select 1 from auth.mfa_factors f
                      where f.user_id = auth.uid() and f.status = 'verified')
$$;
revoke execute on function public.admin_mfa_ok() from public, anon, authenticated;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((
    select p.role = 'admin' and t.active and public.admin_mfa_ok()
    from public.profiles p join public.admin_team t on t.user_id = p.id
    where p.id = auth.uid()), false)
$$;

create or replace function public.admin_can(p_area text, p_user uuid default null)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((
    select p.role = 'admin' and t.active and (t.team_role = 'owner' or p_area = any(t.areas))
           and public.admin_mfa_ok()
    from public.profiles p join public.admin_team t on t.user_id = p.id
    where p.id = coalesce(p_user, auth.uid())
      -- only admins may ask about someone else
      and (p_user is null or p_user = auth.uid() or public.is_admin())), false)
$$;

create or replace function public.admin_is_owner()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((
    select p.role = 'admin' and t.active and t.team_role = 'owner' and public.admin_mfa_ok()
    from public.profiles p join public.admin_team t on t.user_id = p.id
    where p.id = auth.uid()), false)
$$;
