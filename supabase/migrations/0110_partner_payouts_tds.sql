-- ============================================================
-- 0110 — Paying influencers: requests, PAN and TDS.
--
--   * partner_tax_details: the partner's PAN, in its own table so only the
--     payments area can read it (marketing can read partners). The partner
--     can enter it; they only ever see the last 4 characters;
--   * a request can be declined with a reason. The partner sees the reason
--     and can ask again;
--   * partner_payouts.tds: TDS held on a payout. "amount" stays the full
--     commission (the expense in Accounts too); the partner receives amount
--     less tds. The team notes when it was deposited, and the challan;
--   * admin_partner_payouts: the board behind the Payouts tab.
-- ============================================================

create table if not exists public.partner_tax_details (
  partner_id  uuid primary key references public.partners(id) on delete cascade,
  pan         text not null check (pan ~ '^[A-Z]{5}[0-9]{4}[A-Z]$'),
  updated_at  timestamptz not null default now(),
  updated_by  uuid references public.profiles(id) on delete set null
);
alter table public.partner_tax_details enable row level security;
drop policy if exists "payments reads" on public.partner_tax_details;
create policy "payments reads" on public.partner_tax_details for select
  using (public.is_admin() and public.admin_can('payments'));

alter table public.partner_payout_requests
  add column if not exists decline_reason text not null default '',
  add column if not exists closed_by uuid references public.profiles(id) on delete set null,
  add column if not exists superseded boolean not null default false;
alter table public.partner_payout_requests drop constraint if exists partner_payout_requests_status_check;
alter table public.partner_payout_requests add constraint partner_payout_requests_status_check
  check (status in ('open', 'paid', 'declined'));

alter table public.partner_payouts
  add column if not exists tds numeric(12,2) not null default 0,
  add column if not exists tds_deposited_on date,
  add column if not exists tds_challan text not null default '';
alter table public.partner_payouts drop constraint if exists partner_payouts_tds_check;
alter table public.partner_payouts add constraint partner_payouts_tds_check check (tds >= 0 and tds < amount);

-- Asking again or being paid clears an earlier decline from the partner's page.
create or replace function public.partner_request_clears_declines()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.partner_payout_requests set superseded = true
   where partner_id = new.partner_id and status = 'declined' and not superseded;
  return new;
end $$;
drop trigger if exists trg_partner_request_clears_declines on public.partner_payout_requests;
create trigger trg_partner_request_clears_declines before insert on public.partner_payout_requests
  for each row execute function public.partner_request_clears_declines();
drop trigger if exists trg_partner_payout_clears_declines on public.partner_payouts;
create trigger trg_partner_payout_clears_declines after insert on public.partner_payouts
  for each row execute function public.partner_request_clears_declines();

-- ============================================================
-- A. PAN
-- ============================================================
create or replace function public.partner_clean_pan(p_pan text)
returns text language plpgsql immutable as $$
declare v text := upper(regexp_replace(coalesce(p_pan, ''), '\s', '', 'g'));
begin
  if v !~ '^[A-Z]{5}[0-9]{4}[A-Z]$' then raise exception 'That PAN doesn''t look right — it is like ABCDE1234F'; end if;
  return v;
end $$;

-- The PAN value is never written to the audit log.
create or replace function public.my_partner_set_pan(p_pan text)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_id uuid := (select id from public.partners where user_id = auth.uid());
  v_pan text := public.partner_clean_pan(p_pan);
begin
  if auth.uid() is null or v_id is null then raise exception 'Partners only' using errcode = '42501'; end if;
  insert into public.partner_tax_details (partner_id, pan, updated_by) values (v_id, v_pan, auth.uid())
  on conflict (partner_id) do update set pan = excluded.pan, updated_at = now(), updated_by = excluded.updated_by;
  perform public.admin_log(null, 'partner.pan_set_by_partner', 'partner', v_id::text, '{}'::jsonb);
  return right(v_pan, 4);
end $$;

-- An empty PAN removes it.
create or replace function public.admin_set_partner_pan(p_partner uuid, p_pan text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_admin_area('payments');
  if not exists (select 1 from public.partners where id = p_partner) then raise exception 'Partner not found'; end if;
  if btrim(coalesce(p_pan, '')) = '' then
    delete from public.partner_tax_details where partner_id = p_partner;
  else
    insert into public.partner_tax_details (partner_id, pan, updated_by)
    values (p_partner, public.partner_clean_pan(p_pan), auth.uid())
    on conflict (partner_id) do update set pan = excluded.pan, updated_at = now(), updated_by = excluded.updated_by;
  end if;
  perform public.admin_log(null, 'partner.pan_set', 'partner', p_partner::text, '{}'::jsonb);
end $$;

-- ============================================================
-- B. Declining a request, and paying with TDS
-- ============================================================
create or replace function public.admin_decline_payout_request(p_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v public.partner_payout_requests;
begin
  perform public.assert_admin_area('payments');
  if btrim(coalesce(p_reason, '')) = '' then raise exception 'Enter the reason — the partner will see it'; end if;
  update public.partner_payout_requests
     set status = 'declined', decline_reason = btrim(p_reason), closed_at = now(), closed_by = auth.uid()
   where id = p_id and status = 'open'
  returning * into v;
  if v.id is null then raise exception 'That request is already closed'; end if;
  perform public.admin_log(null, 'partner.payout_declined', 'partner', v.partner_id::text,
    jsonb_build_object('amount', v.amount, 'reason', v.decline_reason));
end $$;

create or replace function public.admin_pay_partner(p_partner uuid, p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_p public.partners;
  v_date date := coalesce(nullif(p ->> 'paid_on', '')::date, public.ist_date(now()));
  v_total numeric;
  v_tds numeric := round(coalesce(nullif(p ->> 'tds', '')::numeric, 0), 2);
  v_expense uuid;
  v_payout uuid;
begin
  perform public.assert_admin_area('payments');
  select * into v_p from public.partners where id = p_partner for update;
  if v_p.id is null then raise exception 'Partner not found'; end if;
  select coalesce(sum(amount), 0) into v_total from public.partner_commissions
   where partner_id = p_partner and status = 'pending' and payable_on <= v_date;
  if v_total <= 0 then raise exception 'Nothing to pay yet'; end if;
  if v_tds < 0 or v_tds >= v_total then raise exception 'TDS must be less than the payout'; end if;
  if coalesce(p ->> 'mode', 'upi') <> 'cash' and btrim(coalesce(p ->> 'reference', '')) = '' then
    raise exception 'Enter the UPI/bank reference number';
  end if;
  insert into public.business_expenses (spent_on, category, amount, vendor, note, created_by)
  values (v_date, 'commission', v_total, v_p.name,
          btrim('Partner ' || v_p.code || ' ' || coalesce(p ->> 'reference', '')), auth.uid())
  returning id into v_expense;
  insert into public.partner_payouts (partner_id, amount, tds, paid_on, mode, reference, note, expense_id, created_by)
  values (p_partner, v_total, v_tds, v_date, coalesce(nullif(p ->> 'mode', ''), 'upi')::public.payment_mode,
          btrim(coalesce(p ->> 'reference', '')), btrim(coalesce(p ->> 'note', '')), v_expense, auth.uid())
  returning id into v_payout;
  update public.partner_commissions set status = 'paid', payout_id = v_payout
   where partner_id = p_partner and status = 'pending' and payable_on <= v_date;
  perform public.admin_log(null, 'partner.paid', 'partner', p_partner::text,
    jsonb_build_object('amount', v_total, 'tds', v_tds, 'reference', p ->> 'reference'));
  return jsonb_build_object('payout_id', v_payout, 'amount', v_total, 'tds', v_tds, 'net', v_total - v_tds);
end $$;

-- Note the deposit to the government (empty date clears it).
create or replace function public.admin_set_tds_deposit(p_payout uuid, p jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v public.partner_payouts;
begin
  perform public.assert_admin_area('payments');
  select * into v from public.partner_payouts where id = p_payout for update;
  if v.id is null then raise exception 'Payout not found'; end if;
  if v.tds <= 0 then raise exception 'No TDS was held on this payout'; end if;
  update public.partner_payouts
     set tds_deposited_on = nullif(p ->> 'deposited_on', '')::date,
         tds_challan = case when nullif(p ->> 'deposited_on', '') is null then '' else btrim(coalesce(p ->> 'challan', '')) end
   where id = p_payout;
  perform public.admin_log(null, 'partner.tds_deposit', 'partner', v.partner_id::text, p || jsonb_build_object('payout', p_payout));
end $$;

-- ============================================================
-- C. What the partner sees
-- ============================================================
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
    'tds', (select coalesce(sum(tds), 0) from public.partner_payouts where partner_id = v.id),
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
      select jsonb_agg(jsonb_build_object('paid_on', paid_on, 'amount', amount, 'tds', tds, 'reference', right(reference, 4))
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
                         from public.partner_payout_requests r where r.partner_id = v.id and r.status = 'open'),
    'last_declined', (select jsonb_build_object('amount', r.amount, 'reason', r.decline_reason, 'at', r.closed_at)
                        from public.partner_payout_requests r
                       where r.partner_id = v.id and r.status = 'declined' and not r.superseded
                       order by r.closed_at desc limit 1),
    'has_pan', exists (select 1 from public.partner_tax_details t where t.partner_id = v.id),
    'pan_last4', (select right(t.pan, 4) from public.partner_tax_details t where t.partner_id = v.id));
end $$;

-- ============================================================
-- D. The Payouts tab: requests, others ready to pay, recent declines and
--    the payouts in a date range. Payments only: it has the PAN.
-- ============================================================
create or replace function public.admin_partner_payouts(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_today date := public.ist_date(now());
  v_fy date := make_date(extract(year from v_today)::int - case when extract(month from v_today) < 4 then 1 else 0 end, 4, 1);
begin
  if not public.admin_can('payments') then raise exception 'Admin only' using errcode = '42501'; end if;
  return jsonb_build_object(
    'partners', coalesce((
      select jsonb_agg(x order by x.requested_at nulls last, x.name) from (
        select p.id, p.name, p.code, p.phone, p.upi_id, p.stats_token, t.pan,
          r.id as request_id, r.amount as requested, r.upi_id as requested_upi, r.created_at as requested_at,
          (select coalesce(sum(m.amount), 0) from public.partner_commissions m
            where m.partner_id = p.id and m.status = 'pending' and m.payable_on <= v_today) as payable,
          (select coalesce(sum(o.amount), 0) from public.partner_payouts o
            where o.partner_id = p.id and o.paid_on >= v_fy) as paid_this_fy
        from public.partners p
        left join public.partner_tax_details t on t.partner_id = p.id
        left join public.partner_payout_requests r on r.partner_id = p.id and r.status = 'open'
      ) x where x.request_id is not null or x.payable > 0), '[]'::jsonb),
    'declined', coalesce((
      select jsonb_agg(x order by x.closed_at desc) from (
        select r.id, r.amount, r.decline_reason, r.closed_at, p.name
        from public.partner_payout_requests r join public.partners p on p.id = r.partner_id
        where r.status = 'declined' order by r.closed_at desc limit 10) x), '[]'::jsonb),
    'payouts', coalesce((
      select jsonb_agg(x order by x.paid_on desc, x.created_at desc) from (
        select o.id, o.partner_id, p.name, p.code, t.pan, o.amount, o.tds, o.amount - o.tds as net, o.paid_on, o.mode,
               o.reference, o.tds_deposited_on, o.tds_challan, o.created_at
        from public.partner_payouts o
        join public.partners p on p.id = o.partner_id
        left join public.partner_tax_details t on t.partner_id = o.partner_id
        where o.paid_on between p_from and p_to) x), '[]'::jsonb));
end $$;

-- For the Pay window.
create or replace function public.admin_partner_pan(p_partner uuid)
returns text language plpgsql stable security definer set search_path = public as $$
begin
  if not public.admin_can('payments') then raise exception 'Admin only' using errcode = '42501'; end if;
  return (select pan from public.partner_tax_details where partner_id = p_partner);
end $$;

-- Payout alerts now open the Payouts tab.
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
    select r.created_at, 'payment', 'Payout requested: ' || p.name || ' ₹' || r.amount, '/influencers?tab=payouts'
      from public.partner_payout_requests r join public.partners p on p.id = r.partner_id
      where (public.admin_can('marketing') or public.admin_can('payments')) and r.status = 'open' and r.created_at > v_since
    union all
    select x.next_follow_up::timestamp at time zone 'Asia/Kolkata', 'task', 'Follow up influencer: ' || x.name, '/influencers'
      from public.partner_prospects x
      where public.admin_can('marketing') and x.stage not in ('joined', 'dropped')
        and x.next_follow_up <= public.ist_date(now())
        and x.next_follow_up::timestamp at time zone 'Asia/Kolkata' > v_since
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

revoke execute on function public.partner_request_clears_declines() from public, anon, authenticated;
revoke execute on function public.partner_clean_pan(text) from public, anon, authenticated;
revoke execute on function public.partner_stats_of(uuid) from public, anon, authenticated;
grant execute on function public.partner_stats_of(uuid) to service_role;
revoke execute on function public.my_partner_set_pan(text) from public, anon;
grant execute on function public.my_partner_set_pan(text) to authenticated;
revoke execute on function public.admin_set_partner_pan(uuid, text) from public, anon;
grant execute on function public.admin_set_partner_pan(uuid, text) to authenticated;
revoke execute on function public.admin_decline_payout_request(uuid, text) from public, anon;
grant execute on function public.admin_decline_payout_request(uuid, text) to authenticated;
revoke execute on function public.admin_pay_partner(uuid, jsonb) from public, anon;
grant execute on function public.admin_pay_partner(uuid, jsonb) to authenticated;
revoke execute on function public.admin_set_tds_deposit(uuid, jsonb) from public, anon;
grant execute on function public.admin_set_tds_deposit(uuid, jsonb) to authenticated;
revoke execute on function public.my_partner() from public, anon;
grant execute on function public.my_partner() to authenticated;
revoke execute on function public.admin_partner_payouts(date, date) from public, anon;
grant execute on function public.admin_partner_payouts(date, date) to authenticated;
revoke execute on function public.admin_partner_pan(uuid) from public, anon;
grant execute on function public.admin_partner_pan(uuid) to authenticated;
revoke execute on function public.admin_alerts() from public, anon;
grant execute on function public.admin_alerts() to authenticated;
