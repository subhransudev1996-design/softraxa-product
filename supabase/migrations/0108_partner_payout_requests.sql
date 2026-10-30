-- ============================================================
-- 0108 — What an influencer partner sees, and asking for a payout.
--
--   * partner_stats_of adds the funnel (on trial now, trial ended without
--     buying), code uses and each sale or refund, without the shop;
--   * my_partner_request_payout(): when what's payable reaches the minimum
--     (Settings on the Influencers tab, default ₹500), the partner asks to
--     be paid. The team gets an alert; paying them closes the request.
-- ============================================================

alter table public.platform_settings
  add column if not exists partner_min_payout numeric(12,2) not null default 500
    check (partner_min_payout >= 0);

create table if not exists public.partner_payout_requests (
  id          uuid primary key default gen_random_uuid(),
  partner_id  uuid not null references public.partners(id) on delete cascade,
  amount      numeric(12,2) not null check (amount > 0),
  upi_id      text not null default '',
  status      text not null default 'open' check (status in ('open', 'paid')),
  payout_id   uuid references public.partner_payouts(id) on delete set null,
  created_at  timestamptz not null default now(),
  closed_at   timestamptz
);
create unique index if not exists idx_partner_payout_request_open
  on public.partner_payout_requests(partner_id) where status = 'open';
alter table public.partner_payout_requests enable row level security;
drop policy if exists "admin all" on public.partner_payout_requests;
create policy "admin all" on public.partner_payout_requests for all using (public.is_admin()) with check (public.is_admin());
drop policy if exists "team area" on public.partner_payout_requests;
create policy "team area" on public.partner_payout_requests as restrictive for all
  using (not public.is_admin() or public.admin_can('marketing') or public.admin_can('payments'))
  with check (not public.is_admin() or public.admin_can('marketing') or public.admin_can('payments'));

create or replace function public.my_partner_request_payout()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v public.partners;
  v_today date := public.ist_date(now());
  v_payable numeric;
  v_min numeric := (select partner_min_payout from public.platform_settings where id = 1);
begin
  select * into v from public.partners where user_id = auth.uid() for update;
  if v.id is null then raise exception 'Partners only' using errcode = '42501'; end if;
  if exists (select 1 from public.partner_payout_requests where partner_id = v.id and status = 'open') then
    raise exception 'You have already asked for this payout — Dukania will pay you soon';
  end if;
  if btrim(v.upi_id) = '' then raise exception 'Add your UPI ID first'; end if;
  select coalesce(sum(amount), 0) into v_payable from public.partner_commissions
   where partner_id = v.id and status = 'pending' and payable_on <= v_today;
  if v_payable <= 0 then raise exception 'Nothing is ready to be paid yet'; end if;
  if v_payable < v_min then raise exception 'The minimum payout is ₹%', trim(to_char(v_min, 'FM99999990')); end if;
  insert into public.partner_payout_requests (partner_id, amount, upi_id) values (v.id, v_payable, v.upi_id);
  perform public.admin_log(null, 'partner.payout_requested', 'partner', v.id::text, jsonb_build_object('amount', v_payable));
  return jsonb_build_object('amount', v_payable, 'upi_id', v.upi_id);
end $$;

-- Paying the partner closes their request.
create or replace function public.partner_payout_closes_request()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.partner_payout_requests set status = 'paid', payout_id = new.id, closed_at = now()
   where partner_id = new.partner_id and status = 'open';
  return new;
end $$;
drop trigger if exists trg_partner_payout_closes_request on public.partner_payouts;
create trigger trg_partner_payout_closes_request after insert on public.partner_payouts
  for each row execute function public.partner_payout_closes_request();

create or replace function public.partner_stats_of(p_partner uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v public.partners;
  v_today date := public.ist_date(now());
begin
  select * into v from public.partners where id = p_partner;
  if v.id is null then return null; end if;
  return jsonb_build_object(
    -- The funnel: joined shops by where they stand now.
    'on_trial', (select count(*) from public.businesses b
      join lateral (select s.plan_id, s.expiry_date from public.subscriptions s where s.business_id = b.id
                     order by s.created_at desc limit 1) s on true
      join public.plans pl on pl.id = s.plan_id
      where b.partner_id = v.id and pl.is_trial and s.expiry_date >= v_today),
    'trial_ended', (select count(*) from public.businesses b
      join lateral (select s.plan_id, s.expiry_date from public.subscriptions s where s.business_id = b.id
                     order by s.created_at desc limit 1) s on true
      join public.plans pl on pl.id = s.plan_id
      where b.partner_id = v.id and pl.is_trial and s.expiry_date < v_today),
    -- Their code used on a payment (it can also be entered in the app: "signups").
    'code_uses', (select count(*) from public.promo_redemptions r where r.promo_id = v.promo_id and v.promo_id is not null),
    -- Each sale or refund, without the shop.
    'purchases', coalesce((
      select jsonb_agg(x order by x.day desc, x.at desc) from (
        select coalesce(pay.payment_date, public.ist_date(c.created_at)) as day, c.created_at as at, c.kind,
               coalesce(pl.name, '') as plan, c.paid_amount as paid, c.amount as commission, c.payable_on, c.status
          from public.partner_commissions c
          left join public.subscription_payments pay on pay.id = c.payment_id
          left join public.plans pl on pl.id = pay.plan_id
         where c.partner_id = v.id
         order by day desc, c.created_at desc limit 50) x), '[]'::jsonb),
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

create or replace function public.my_partner()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v public.partners;
begin
  if auth.uid() is null then return null; end if;
  select * into v from public.partners where user_id = auth.uid();
  if v.id is null then return null; end if;
  return public.partner_stats_of(v.id) || jsonb_build_object(
    'upi_id', v.upi_id, 'email', v.login_email,
    'min_payout', (select partner_min_payout from public.platform_settings where id = 1),
    'payout_request', (select jsonb_build_object('amount', r.amount, 'upi_id', r.upi_id, 'at', r.created_at)
                         from public.partner_payout_requests r where r.partner_id = v.id and r.status = 'open'));
end $$;

create or replace function public.admin_partners()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_today date := public.ist_date(now());
  v_fy date := make_date(extract(year from v_today)::int - case when extract(month from v_today) < 4 then 1 else 0 end, 4, 1);
begin
  if not (public.admin_can('marketing') or public.admin_can('payments')) then
    raise exception 'Admin only' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(to_jsonb(p) || jsonb_build_object(
      'clicks', (select coalesce(sum(c.clicks), 0) from public.partner_clicks c where c.partner_id = p.id),
      'clicks_30', (select coalesce(sum(c.clicks), 0) from public.partner_clicks c
                     where c.partner_id = p.id and c.day > v_today - 30),
      'signups', (select count(*) from public.businesses b where b.partner_id = p.id),
      'paid_shops', (select count(*) from public.partner_commissions m
                      where m.partner_id = p.id and m.kind = 'sale' and m.status <> 'cancelled'),
      'sales', (select coalesce(sum(m.paid_amount), 0) from public.partner_commissions m
                 where m.partner_id = p.id and m.status <> 'cancelled'),
      'earned', (select coalesce(sum(m.amount), 0) from public.partner_commissions m
                  where m.partner_id = p.id and m.status <> 'cancelled'),
      'payable', (select coalesce(sum(m.amount), 0) from public.partner_commissions m
                   where m.partner_id = p.id and m.status = 'pending' and m.payable_on <= v_today),
      'held', (select coalesce(sum(m.amount), 0) from public.partner_commissions m
                where m.partner_id = p.id and m.status = 'pending' and m.payable_on > v_today),
      'paid', (select coalesce(sum(o.amount), 0) from public.partner_payouts o where o.partner_id = p.id),
      'paid_this_fy', (select coalesce(sum(o.amount), 0) from public.partner_payouts o
                        where o.partner_id = p.id and o.paid_on >= v_fy),
      'last_paid_on', (select max(o.paid_on) from public.partner_payouts o where o.partner_id = p.id),
      'payout_request', (select jsonb_build_object('amount', r.amount, 'upi_id', r.upi_id, 'at', r.created_at)
                           from public.partner_payout_requests r where r.partner_id = p.id and r.status = 'open')
    ) order by p.active desc, p.created_at desc)
    from public.partners p), '[]'::jsonb);
end $$;

create or replace function public.admin_set_partner_defaults(p jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_admin_area('marketing');
  update public.platform_settings set
    partner_buyer_off_pct = coalesce((p ->> 'buyer_off_pct')::numeric, partner_buyer_off_pct),
    partner_commission_pct = coalesce((p ->> 'commission_pct')::numeric, partner_commission_pct),
    partner_hold_days = coalesce((p ->> 'hold_days')::int, partner_hold_days),
    partner_min_payout = coalesce((p ->> 'min_payout')::numeric, partner_min_payout)
  where id = 1;
  perform public.admin_log(null, 'partner.defaults', 'platform_settings', '1', p);
end $$;

create or replace function public.admin_alerts()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_seen timestamptz := coalesce((select alerts_seen_at from public.admin_team where user_id = auth.uid()), now() - interval '1 day');
  v_since timestamptz := now() - interval '7 days';
begin
  if not public.is_admin() then raise exception 'Admin only' using errcode = '42501'; end if;
  return jsonb_build_object('seen_at', v_seen, 'items', coalesce((select jsonb_agg(a order by a.at desc) from (
    select b.created_at as at, 'signup' as kind, 'New shop: ' || b.name as title, '/clients/' || b.id as href
      from public.businesses b where b.created_at > v_since
    union all
    select l.created_at, 'lead', 'New lead: ' || l.shop_name || ' (' || l.source || ')', '/leads/' || l.id
      from public.leads l where public.admin_can('leads') and l.created_at > v_since and l.source <> 'app_signup'
    union all
    select coalesce(t.last_shop_message_at, t.created_at),
           case when t.kind = 'complaint' then 'complaint' else 'ticket' end,
           case when t.kind = 'complaint' then 'Complaint: ' else 'Support: ' end || b.name || ' — ' || t.subject, '/support'
      from public.support_tickets t join public.businesses b on b.id = t.business_id
      where public.admin_can('support') and public.ticket_needs_reply(t)
        and coalesce(t.last_shop_message_at, t.created_at) > v_since
    union all
    select c.created_at, 'payment', 'Payment to verify: ' || b.name || ' ₹' || c.amount, '/'
      from public.renewal_claims c join public.businesses b on b.id = c.business_id
      where public.admin_can('payments') and c.status = 'pending' and c.created_at > v_since
    union all
    select r.created_at, 'payment', 'Payout requested: ' || p.name || ' ₹' || r.amount, '/marketing'
      from public.partner_payout_requests r join public.partners p on p.id = r.partner_id
      where (public.admin_can('marketing') or public.admin_can('payments')) and r.status = 'open' and r.created_at > v_since
    union all
    select r.created_at, 'unhappy', 'Would not recommend (' || r.score || '/10): ' || b.name, '/success'
      from public.nps_responses r join public.businesses b on b.id = r.business_id
      where r.score <= 6 and r.created_at > v_since
    union all
    select t.created_at, 'task', 'Task for you: ' || t.title, '/tasks'
      from public.admin_tasks t
      where t.assigned_to = auth.uid() and t.created_by is distinct from auth.uid() and not t.done and t.created_at > v_since
  ) a), '[]'::jsonb));
end $$;

revoke execute on function public.partner_stats_of(uuid) from public, anon, authenticated;
grant execute on function public.partner_stats_of(uuid) to service_role;
revoke execute on function public.my_partner_request_payout() from public, anon;
grant execute on function public.my_partner_request_payout() to authenticated;
revoke execute on function public.my_partner() from public, anon;
grant execute on function public.my_partner() to authenticated;
revoke execute on function public.admin_partners() from public, anon;
grant execute on function public.admin_partners() to authenticated;
revoke execute on function public.admin_set_partner_defaults(jsonb) from public, anon;
grant execute on function public.admin_set_partner_defaults(jsonb) to authenticated;
revoke execute on function public.admin_alerts() from public, anon;
grant execute on function public.admin_alerts() to authenticated;
