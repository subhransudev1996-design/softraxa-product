-- ============================================================
-- 0107 — A login for influencer partners.
--
--   * the team creates it (Marketing → Influencers): an email and a
--     generated password, sent on WhatsApp, so no email has to arrive;
--     partners.user_id links the login to the partner;
--   * my_partner(): the partner's own numbers at dukania.in/partner/me;
--   * my_partner_set_upi(): they keep their own UPI ID (logged);
--   * the old private stats link can be switched off for a partner.
--
-- The login is made by the admin panel's server (service role), through
-- admin_link_partner_login, so a partner can't link themselves to another.
-- ============================================================

alter table public.partners
  add column if not exists user_id uuid unique references public.profiles(id) on delete set null,
  add column if not exists login_email text not null default '',
  add column if not exists stats_link_on boolean not null default true;

-- A partner's numbers: counts and money, no shop names or phone numbers.
create or replace function public.partner_stats_of(p_partner uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v public.partners;
  v_today date := public.ist_date(now());
begin
  select * into v from public.partners where id = p_partner;
  if v.id is null then return null; end if;
  return jsonb_build_object(
    'name', v.name, 'code', v.code, 'active', v.active, 'buyer_off_pct', v.buyer_off_pct,
    'rule', case when v.commission_kind = 'amount' then '₹' || trim(to_char(v.commission_value, 'FM99999990')) || ' per shop'
                 else rtrim(rtrim(v.commission_value::text, '0'), '.') || '% of the first payment' end,
    'hold_days', v.hold_days,
    'clicks', (select coalesce(sum(clicks), 0) from public.partner_clicks where partner_id = v.id),
    'signups', (select count(*) from public.businesses where partner_id = v.id),
    'paid_shops', (select count(*) from public.partner_commissions
                    where partner_id = v.id and kind = 'sale' and status <> 'cancelled'),
    'earned', (select coalesce(sum(amount), 0) from public.partner_commissions where partner_id = v.id and status <> 'cancelled'),
    'held', (select coalesce(sum(amount), 0) from public.partner_commissions
              where partner_id = v.id and status = 'pending' and payable_on > v_today),
    'payable', (select coalesce(sum(amount), 0) from public.partner_commissions
                 where partner_id = v.id and status = 'pending' and payable_on <= v_today),
    'paid', (select coalesce(sum(amount), 0) from public.partner_payouts where partner_id = v.id),
    'months', coalesce((
      select jsonb_agg(jsonb_build_object('month', m, 'clicks', cl, 'signups', su, 'paid_shops', ps, 'earned', er) order by m desc)
      from (
        select d as m,
          (select coalesce(sum(clicks), 0) from public.partner_clicks
            where partner_id = v.id and date_trunc('month', day)::date = d) as cl,
          (select count(*) from public.businesses
            where partner_id = v.id and date_trunc('month', public.ist_date(partner_at))::date = d) as su,
          (select count(*) from public.partner_commissions
            where partner_id = v.id and kind = 'sale' and status <> 'cancelled'
              and date_trunc('month', payable_on - v.hold_days)::date = d) as ps,
          (select coalesce(sum(amount), 0) from public.partner_commissions
            where partner_id = v.id and status <> 'cancelled' and date_trunc('month', payable_on - v.hold_days)::date = d) as er
        from (select g::date as d from generate_series(date_trunc('month', v_today::timestamp) - interval '5 months',
                             date_trunc('month', v_today::timestamp), interval '1 month') g) months
      ) x), '[]'::jsonb),
    'payouts', coalesce((
      select jsonb_agg(jsonb_build_object('paid_on', paid_on, 'amount', amount, 'reference', right(reference, 4))
                       order by paid_on desc)
      from public.partner_payouts where partner_id = v.id), '[]'::jsonb));
end $$;
revoke execute on function public.partner_stats_of(uuid) from public, anon, authenticated;

-- By the secret in the private link, unless the team switched it off.
create or replace function public.partner_stats(p_token text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_id uuid;
begin
  if coalesce(length(p_token), 0) <> 32 then return null; end if;
  select id into v_id from public.partners where stats_token = p_token and stats_link_on;
  if v_id is null then return null; end if;
  return public.partner_stats_of(v_id);
end $$;

-- The signed-in partner's own page; null for anyone else.
create or replace function public.my_partner()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v public.partners;
begin
  if auth.uid() is null then return null; end if;
  select * into v from public.partners where user_id = auth.uid();
  if v.id is null then return null; end if;
  return public.partner_stats_of(v.id) || jsonb_build_object('upi_id', v.upi_id, 'email', v.login_email);
end $$;

create or replace function public.my_partner_set_upi(p_upi text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v public.partners;
  v_upi text := btrim(coalesce(p_upi, ''));
begin
  select * into v from public.partners where user_id = auth.uid() for update;
  if v.id is null then raise exception 'Partners only' using errcode = '42501'; end if;
  if v_upi !~ '^[A-Za-z0-9._-]{2,255}@[A-Za-z][A-Za-z0-9]{1,63}$' then
    raise exception 'That doesn''t look like a UPI ID — it should be like name@okaxis';
  end if;
  update public.partners set upi_id = v_upi where id = v.id;
  perform public.admin_log(null, 'partner.upi_changed', 'partner', v.id::text,
    jsonb_build_object('from', v.upi_id, 'to', v_upi));
end $$;

-- From the admin panel's server only, after it checked the team member.
create or replace function public.admin_link_partner_login(p_partner uuid, p_user uuid, p_email text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_server_job() then raise exception 'Server only' using errcode = '42501'; end if;
  update public.partners set user_id = p_user, login_email = coalesce(p_email, '') where id = p_partner;
  if not found then raise exception 'Partner not found'; end if;
  perform public.admin_log(null, case when p_user is null then 'partner.login_removed' else 'partner.login_created' end,
    'partner', p_partner::text, jsonb_build_object('email', p_email));
end $$;

create or replace function public.admin_set_partner_link(p_partner uuid, p_on boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_admin_area('marketing');
  update public.partners set stats_link_on = coalesce(p_on, false) where id = p_partner;
  if not found then raise exception 'Partner not found'; end if;
  perform public.admin_log(null, 'partner.link', 'partner', p_partner::text, jsonb_build_object('on', p_on));
end $$;

revoke execute on function public.my_partner() from public, anon;
revoke execute on function public.my_partner_set_upi(text) from public, anon;
revoke execute on function public.admin_link_partner_login(uuid, uuid, text) from public, anon, authenticated;
revoke execute on function public.admin_set_partner_link(uuid, boolean) from public, anon;
grant execute on function public.my_partner() to authenticated;
grant execute on function public.my_partner_set_upi(text) to authenticated;
grant execute on function public.admin_link_partner_login(uuid, uuid, text) to service_role;
grant execute on function public.admin_set_partner_link(uuid, boolean) to authenticated;
grant execute on function public.partner_stats_of(uuid) to service_role;
grant execute on function public.partner_stats(text) to anon, authenticated;
