-- ============================================================
-- 0073_sign_out_staff.sql
-- The owner signs a staff member out of every device (a lost phone, someone
-- who left, a shared PC). Their account and permissions stay; they log in
-- again with their password.
--
-- sign_out_staff_user() ends all of the staff member's sessions, so no
-- device can renew its login. The app asks my_session_active() about once
-- a minute and goes to the login screen when its session is gone, instead
-- of waiting for its access token to run out (up to an hour).
-- ============================================================

create or replace function public.sign_out_staff_user(p_profile_id uuid)
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_target   record;
  v_n        integer;
begin
  if v_business is null or not public.has_permission('owner') then
    raise exception 'Only the store owner can sign staff out' using errcode = '42501';
  end if;
  select * into v_target from public.profiles where id = p_profile_id;
  if v_target.id is null or v_target.business_id is distinct from v_business
     or v_target.role::text not in ('staff', 'manager') then
    raise exception 'Staff member not found in your store';
  end if;

  delete from auth.refresh_tokens where user_id = p_profile_id::text;
  delete from auth.sessions where user_id = p_profile_id;
  get diagnostics v_n = row_count;

  perform public.log_audit('staff.signed_out', 'profile', p_profile_id::text,
    jsonb_build_object('email', v_target.email, 'sessions', v_n));
  return v_n;
end $$;

-- Is the session this request was made with still there? True when the
-- token carries no session id (nothing to check).
create or replace function public.my_session_active()
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when nullif(auth.jwt() ->> 'session_id', '') is null then true
    else exists (select 1 from auth.sessions s
                 where s.id = (auth.jwt() ->> 'session_id')::uuid)
  end;
$$;

revoke execute on function public.sign_out_staff_user(uuid) from public, anon;
revoke execute on function public.my_session_active() from public, anon;
grant execute on function public.sign_out_staff_user(uuid) to authenticated;
grant execute on function public.my_session_active() to authenticated;
