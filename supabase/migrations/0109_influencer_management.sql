-- ============================================================
-- 0109 — Managing influencers, before and after they join.
--
--   * partner_prospects: the outreach pipeline (found, contacted, talking,
--     joined, dropped) with followers, niche, deal talk and a follow-up
--     date. "Make partner" creates the code and moves them to joined;
--   * partners get followers, niche, language, city and platform;
--   * partner_posts: each reel or story with its link and views, and the
--     clicks and shops in the 3 days from the post (a guide: posts close
--     together share the same clicks);
--   * partner_fees: fixed fees, also an "ads" expense in Accounts. Deleting
--     that expense removes the fee;
--   * admin_partners adds what each partner really made: first payments
--     before GST and after refunds, less commission, less fees.
--   All three are read by the team and written only through functions; a
--   partner sees none of them.
-- ============================================================

alter table public.partners
  add column if not exists platform  text not null default 'instagram'
    check (platform in ('instagram', 'youtube', 'facebook', 'other')),
  add column if not exists followers integer check (followers >= 0),
  add column if not exists niche     text not null default '',
  add column if not exists language  text not null default '',
  add column if not exists city      text not null default '';

create or replace function pg_temp.read_only(p_table text, p_can text) returns void language plpgsql as $$
begin
  execute format('alter table public.%I enable row level security', p_table);
  execute format('drop policy if exists "team reads" on public.%I', p_table);
  execute format('create policy "team reads" on public.%I for select using (public.is_admin() and (%s))', p_table, p_can);
end $$;

create table if not exists public.partner_prospects (
  id              uuid primary key default gen_random_uuid(),
  name            text not null check (btrim(name) <> ''),
  handle          text not null default '',
  platform        text not null default 'instagram' check (platform in ('instagram', 'youtube', 'facebook', 'other')),
  followers       integer check (followers >= 0),
  niche           text not null default '',
  language        text not null default '',
  city            text not null default '',
  phone           text not null default '',
  stage           text not null default 'found' check (stage in ('found', 'contacted', 'talking', 'joined', 'dropped')),
  deal_note       text not null default '',              -- what was asked or offered
  next_follow_up  date,
  last_contact_on date,
  note            text not null default '',
  drop_reason     text not null default '',
  partner_id      uuid references public.partners(id) on delete set null,
  created_by      uuid references public.profiles(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists idx_partner_prospects_follow_up on public.partner_prospects(next_follow_up)
  where next_follow_up is not null and stage not in ('joined', 'dropped');
select pg_temp.read_only('partner_prospects', 'public.admin_can(''marketing'')');

create table if not exists public.partner_posts (
  id          uuid primary key default gen_random_uuid(),
  partner_id  uuid not null references public.partners(id) on delete cascade,
  posted_on   date not null,
  kind        text not null default 'reel' check (kind in ('reel', 'story', 'video', 'post')),
  url         text not null default '',
  views       integer check (views >= 0),
  note        text not null default '',
  created_by  uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now()
);
create index if not exists idx_partner_posts_partner on public.partner_posts(partner_id, posted_on desc);
select pg_temp.read_only('partner_posts', 'public.admin_can(''marketing'') or public.admin_can(''payments'')');

create table if not exists public.partner_fees (
  id          uuid primary key default gen_random_uuid(),
  partner_id  uuid not null references public.partners(id) on delete cascade,
  amount      numeric(12,2) not null check (amount > 0),
  paid_on     date not null,
  mode        public.payment_mode not null default 'upi',
  reference   text not null default '',
  note        text not null default '',
  expense_id  uuid references public.business_expenses(id) on delete cascade,
  created_by  uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now()
);
create index if not exists idx_partner_fees_partner on public.partner_fees(partner_id, paid_on desc);
select pg_temp.read_only('partner_fees', 'public.admin_can(''marketing'') or public.admin_can(''payments'')');

-- ============================================================
-- A. The pipeline
-- ============================================================
create or replace function public.admin_save_prospect(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v public.partner_prospects;
  v_id uuid := nullif(p ->> 'id', '')::uuid;
  v_handle text := btrim(coalesce(p ->> 'handle', ''));
  v_key text := lower(ltrim(v_handle, '@'));
  v_stage text := nullif(p ->> 'stage', '');
  v_today date := public.ist_date(now());
begin
  perform public.assert_admin_area('marketing');
  if btrim(coalesce(p ->> 'name', '')) = '' then raise exception 'Enter the name'; end if;
  if v_stage = 'joined' then raise exception 'Use Make partner to move them to Joined'; end if;
  if v_id is not null then
    select * into v from public.partner_prospects where id = v_id for update;
    if v.id is null then raise exception 'Not found'; end if;
    if v.stage = 'joined' and v_stage is distinct from 'joined' and v_stage is not null then
      raise exception 'They have already joined — switch the partner off on their page instead';
    end if;
  end if;
  if v_key <> '' then
    if exists (select 1 from public.partner_prospects x
                where lower(ltrim(x.handle, '@')) = v_key and x.id is distinct from v_id) then
      raise exception '% is already in the pipeline', v_handle;
    end if;
    if exists (select 1 from public.partners x where lower(ltrim(x.handle, '@')) = v_key)
       and (v_id is null or v.partner_id is null) then
      raise exception '% is already a partner', v_handle;
    end if;
  end if;
  if v_id is null then
    insert into public.partner_prospects (name, created_by) values (btrim(p ->> 'name'), auth.uid()) returning * into v;
  end if;
  update public.partner_prospects set
    name = btrim(p ->> 'name'),
    handle = v_handle,
    platform = coalesce(nullif(p ->> 'platform', ''), platform),
    followers = case when p ? 'followers' then nullif(p ->> 'followers', '')::int else followers end,
    niche = btrim(coalesce(p ->> 'niche', niche)),
    language = btrim(coalesce(p ->> 'language', language)),
    city = btrim(coalesce(p ->> 'city', city)),
    phone = btrim(coalesce(p ->> 'phone', phone)),
    stage = coalesce(v_stage, stage),
    deal_note = btrim(coalesce(p ->> 'deal_note', deal_note)),
    -- Nothing to follow up once they have dropped out.
    next_follow_up = case when coalesce(v_stage, stage) = 'dropped' then null
                          when p ? 'next_follow_up' then nullif(p ->> 'next_follow_up', '')::date
                          else next_follow_up end,
    -- Reaching out counts as contact.
    last_contact_on = case when v_stage in ('contacted', 'talking') and v_stage is distinct from stage then v_today
                           else last_contact_on end,
    note = btrim(coalesce(p ->> 'note', note)),
    drop_reason = case when coalesce(v_stage, stage) = 'dropped' then btrim(coalesce(p ->> 'drop_reason', drop_reason)) else '' end,
    updated_at = now()
  where id = v.id
  returning * into v;
  perform public.admin_log(null, case when v_id is null then 'prospect.created' else 'prospect.updated' end,
    'partner_prospect', v.id::text, p - 'id');
  return to_jsonb(v);
end $$;

create or replace function public.admin_delete_prospect(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v public.partner_prospects;
begin
  perform public.assert_admin_area('marketing');
  select * into v from public.partner_prospects where id = p_id for update;
  if v.id is null then raise exception 'Not found'; end if;
  if v.stage = 'joined' then raise exception 'They have joined as a partner — this record stays'; end if;
  delete from public.partner_prospects where id = p_id;
  perform public.admin_log(null, 'prospect.deleted', 'partner_prospect', p_id::text, jsonb_build_object('name', v.name));
end $$;

-- Add or change a partner (0104), with their followers, niche, language,
-- city and platform.
create or replace function public.admin_save_partner(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v public.partners;
  v_id uuid := nullif(p ->> 'id', '')::uuid;
  v_code text := upper(btrim(coalesce(p ->> 'code', '')));
  s public.platform_settings := (select x from public.platform_settings x where id = 1);
begin
  perform public.assert_admin_area('marketing');
  if btrim(coalesce(p ->> 'name', '')) = '' then raise exception 'Enter the name'; end if;
  if v_id is null then
    if v_code !~ '^[A-Z0-9_-]{3,20}$' then raise exception 'The code is 3–20 letters, numbers, - or _'; end if;
    if exists (select 1 from public.partners where code = v_code)
       or exists (select 1 from public.promo_codes where code = v_code)
       or exists (select 1 from public.businesses where referral_code = v_code) then
      raise exception 'The code % is already used — choose another', v_code;
    end if;
    insert into public.partners (name, code, buyer_off_pct, commission_kind, commission_value, hold_days, created_by)
    values (btrim(p ->> 'name'), v_code, s.partner_buyer_off_pct, 'percent', s.partner_commission_pct,
            s.partner_hold_days, auth.uid())
    returning * into v;
  else
    select * into v from public.partners where id = v_id for update;
    if v.id is null then raise exception 'Partner not found'; end if;
  end if;

  update public.partners set
    name = btrim(p ->> 'name'),
    handle = btrim(coalesce(p ->> 'handle', handle)),
    phone = btrim(coalesce(p ->> 'phone', phone)),
    upi_id = btrim(coalesce(p ->> 'upi_id', upi_id)),
    buyer_off_pct = coalesce((p ->> 'buyer_off_pct')::numeric, buyer_off_pct),
    commission_kind = coalesce(nullif(p ->> 'commission_kind', ''), commission_kind),
    commission_value = coalesce((p ->> 'commission_value')::numeric, commission_value),
    hold_days = coalesce((p ->> 'hold_days')::int, hold_days),
    active = coalesce((p ->> 'active')::boolean, active),
    note = btrim(coalesce(p ->> 'note', note)),
    platform = coalesce(nullif(p ->> 'platform', ''), platform),
    followers = case when p ? 'followers' then nullif(p ->> 'followers', '')::int else followers end,
    niche = btrim(coalesce(p ->> 'niche', niche)),
    language = btrim(coalesce(p ->> 'language', language)),
    city = btrim(coalesce(p ->> 'city', city))
  where id = v.id
  returning * into v;

  -- The shop's discount as a promo code (none when it is 0%).
  if v.promo_id is null and v.buyer_off_pct > 0 then
    insert into public.promo_codes (code, kind, value, active, note, created_by)
    values (v.code, 'percent', v.buyer_off_pct, v.active, 'Partner: ' || v.name, auth.uid())
    returning id into v.promo_id;
    update public.partners set promo_id = v.promo_id where id = v.id;
  elsif v.promo_id is not null then
    update public.promo_codes
       set value = greatest(v.buyer_off_pct, 0.01), active = v.active and v.buyer_off_pct > 0, note = 'Partner: ' || v.name
     where id = v.promo_id;
  end if;

  perform public.admin_log(null, case when v_id is null then 'partner.created' else 'partner.updated' end,
    'partner', v.id::text, p - 'id');
  return to_jsonb(v);
end $$;

-- From the pipeline to a partner: creates the code and deal, and keeps
-- what is known about them.
create or replace function public.admin_prospect_to_partner(p_prospect uuid, p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v public.partner_prospects;
  v_partner jsonb;
begin
  perform public.assert_admin_area('marketing');
  select * into v from public.partner_prospects where id = p_prospect for update;
  if v.id is null then raise exception 'Not found'; end if;
  if v.stage = 'joined' then raise exception 'They are already a partner'; end if;
  v_partner := public.admin_save_partner(
    jsonb_build_object('name', v.name, 'handle', v.handle, 'phone', v.phone, 'platform', v.platform,
      'followers', v.followers, 'niche', v.niche, 'language', v.language, 'city', v.city,
      'note', btrim(v.note || case when v.deal_note <> '' and v.note <> '' then ' · ' else '' end || v.deal_note))
    || (p - 'id' - 'name' - 'handle' - 'phone'));
  update public.partner_prospects
     set stage = 'joined', partner_id = (v_partner ->> 'id')::uuid, next_follow_up = null, drop_reason = '', updated_at = now()
   where id = v.id;
  perform public.admin_log(null, 'prospect.joined', 'partner_prospect', v.id::text, jsonb_build_object('partner', v_partner ->> 'id'));
  return v_partner;
end $$;

-- ============================================================
-- B. Posts
-- ============================================================
create or replace function public.admin_save_partner_post(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v public.partner_posts;
  v_id uuid := nullif(p ->> 'id', '')::uuid;
begin
  perform public.assert_admin_area('marketing');
  if v_id is null then
    if not exists (select 1 from public.partners where id = nullif(p ->> 'partner_id', '')::uuid) then
      raise exception 'Choose the partner';
    end if;
    insert into public.partner_posts (partner_id, posted_on, kind, url, views, note, created_by)
    values ((p ->> 'partner_id')::uuid, coalesce(nullif(p ->> 'posted_on', '')::date, public.ist_date(now())),
            coalesce(nullif(p ->> 'kind', ''), 'reel'), btrim(coalesce(p ->> 'url', '')),
            nullif(p ->> 'views', '')::int, btrim(coalesce(p ->> 'note', '')), auth.uid())
    returning * into v;
  else
    update public.partner_posts set
      posted_on = coalesce(nullif(p ->> 'posted_on', '')::date, posted_on),
      kind = coalesce(nullif(p ->> 'kind', ''), kind),
      url = btrim(coalesce(p ->> 'url', url)),
      views = case when p ? 'views' then nullif(p ->> 'views', '')::int else views end,
      note = btrim(coalesce(p ->> 'note', note))
    where id = v_id
    returning * into v;
    if v.id is null then raise exception 'Post not found'; end if;
  end if;
  perform public.admin_log(null, case when v_id is null then 'partner.post_added' else 'partner.post_updated' end,
    'partner', v.partner_id::text, p - 'id');
  return to_jsonb(v);
end $$;

create or replace function public.admin_delete_partner_post(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_partner uuid;
begin
  perform public.assert_admin_area('marketing');
  delete from public.partner_posts where id = p_id returning partner_id into v_partner;
  if v_partner is null then raise exception 'Post not found'; end if;
  perform public.admin_log(null, 'partner.post_deleted', 'partner', v_partner::text, jsonb_build_object('post', p_id));
end $$;

-- Posts, newest first, for one partner or all, with what came in the 3 days
-- from each post.
create or replace function public.admin_partner_posts(p_partner uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.admin_can('marketing') or public.admin_can('payments')) then
    raise exception 'Admin only' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(x order by x.posted_on desc, x.created_at desc) from (
      select o.*, p.name as partner_name, p.code as partner_code,
        (select coalesce(sum(c.clicks), 0) from public.partner_clicks c
          where c.partner_id = o.partner_id and c.day between o.posted_on and o.posted_on + 2) as clicks_3d,
        (select count(*) from public.businesses b
          where b.partner_id = o.partner_id and public.ist_date(b.partner_at) between o.posted_on and o.posted_on + 2) as signups_3d
      from public.partner_posts o join public.partners p on p.id = o.partner_id
      where p_partner is null or o.partner_id = p_partner) x), '[]'::jsonb);
end $$;

-- ============================================================
-- C. Fixed fees
-- ============================================================
create or replace function public.admin_add_partner_fee(p_partner uuid, p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_p public.partners;
  v public.partner_fees;
  v_amount numeric := nullif(p ->> 'amount', '')::numeric;
  v_date date := coalesce(nullif(p ->> 'paid_on', '')::date, public.ist_date(now()));
  v_expense uuid;
begin
  perform public.assert_admin_area('payments');
  select * into v_p from public.partners where id = p_partner;
  if v_p.id is null then raise exception 'Choose the partner'; end if;
  if coalesce(v_amount, 0) <= 0 then raise exception 'Enter the amount'; end if;
  if coalesce(p ->> 'mode', 'upi') <> 'cash' and btrim(coalesce(p ->> 'reference', '')) = '' then
    raise exception 'Enter the UPI/bank reference number';
  end if;
  insert into public.business_expenses (spent_on, category, amount, vendor, note, created_by)
  values (v_date, 'ads', v_amount, v_p.name,
          btrim('Influencer fee ' || v_p.code || ' ' || coalesce(p ->> 'reference', '')), auth.uid())
  returning id into v_expense;
  insert into public.partner_fees (partner_id, amount, paid_on, mode, reference, note, expense_id, created_by)
  values (p_partner, v_amount, v_date, coalesce(nullif(p ->> 'mode', ''), 'upi')::public.payment_mode,
          btrim(coalesce(p ->> 'reference', '')), btrim(coalesce(p ->> 'note', '')), v_expense, auth.uid())
  returning * into v;
  perform public.admin_log(null, 'partner.fee_added', 'partner', p_partner::text,
    jsonb_build_object('amount', v_amount, 'reference', p ->> 'reference'));
  return to_jsonb(v);
end $$;

-- Takes the expense with it, or the fee alone if the expense has no link.
create or replace function public.admin_delete_partner_fee(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v public.partner_fees;
begin
  perform public.assert_admin_area('payments');
  select * into v from public.partner_fees where id = p_id;
  if v.id is null then raise exception 'Fee not found'; end if;
  delete from public.partner_fees where id = p_id;
  delete from public.business_expenses where id = v.expense_id;
  perform public.admin_log(null, 'partner.fee_deleted', 'partner', v.partner_id::text, jsonb_build_object('amount', v.amount));
end $$;

-- ============================================================
-- D. What each partner brought
-- ============================================================
-- First payments before GST, less the refunded share.
create or replace function public.partner_revenue(p_partner uuid)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(round(sum(m.base * greatest(0, 1 - coalesce(
      (select sum(r.amount) from public.subscription_refunds r where r.payment_id = m.payment_id), 0)
      / nullif(m.paid_amount, 0))), 2), 0)
  from public.partner_commissions m
  where m.partner_id = p_partner and m.kind = 'sale' and m.status <> 'cancelled';
$$;

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
    select jsonb_agg(x.j || jsonb_build_object('net', (x.j ->> 'revenue')::numeric - (x.j ->> 'earned')::numeric - (x.j ->> 'fees')::numeric)
                     order by (x.j ->> 'active')::boolean desc, x.j ->> 'created_at' desc)
    from (select to_jsonb(p) || jsonb_build_object(
      'clicks', (select coalesce(sum(c.clicks), 0) from public.partner_clicks c where c.partner_id = p.id),
      'clicks_30', (select coalesce(sum(c.clicks), 0) from public.partner_clicks c
                     where c.partner_id = p.id and c.day > v_today - 30),
      'last_click_on', (select max(c.day) from public.partner_clicks c where c.partner_id = p.id and c.clicks > 0),
      'signups', (select count(*) from public.businesses b where b.partner_id = p.id),
      'paid_shops', (select count(*) from public.partner_commissions m
                      where m.partner_id = p.id and m.kind = 'sale' and m.status <> 'cancelled'),
      'sales', (select coalesce(sum(m.paid_amount), 0) from public.partner_commissions m
                 where m.partner_id = p.id and m.status <> 'cancelled'),
      'revenue', public.partner_revenue(p.id),
      'earned', (select coalesce(sum(m.amount), 0) from public.partner_commissions m
                  where m.partner_id = p.id and m.status <> 'cancelled'),
      'fees', (select coalesce(sum(f.amount), 0) from public.partner_fees f where f.partner_id = p.id),
      'posts', (select count(*) from public.partner_posts o where o.partner_id = p.id),
      'last_post_on', (select max(o.posted_on) from public.partner_posts o where o.partner_id = p.id),
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
    ) as j from public.partners p) x), '[]'::jsonb);
end $$;

-- One partner's funnel and last six months, for their page.
create or replace function public.admin_partner_funnel(p_partner uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  if not (public.admin_can('marketing') or public.admin_can('payments')) then
    raise exception 'Admin only' using errcode = '42501';
  end if;
  v := public.partner_stats_of(p_partner);
  if v is null then return null; end if;
  return jsonb_build_object('on_trial', v -> 'on_trial', 'trial_ended', v -> 'trial_ended',
    'code_uses', v -> 'code_uses', 'months', v -> 'months');
end $$;

-- Alerts now open the Influencers page, and a pipeline follow-up that is due shows.
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
    select r.created_at, 'payment', 'Payout requested: ' || p.name || ' ₹' || r.amount, '/influencers?tab=partners'
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

revoke execute on function public.partner_revenue(uuid) from public, anon, authenticated;
revoke execute on function public.admin_save_prospect(jsonb) from public, anon;
grant execute on function public.admin_save_prospect(jsonb) to authenticated;
revoke execute on function public.admin_delete_prospect(uuid) from public, anon;
grant execute on function public.admin_delete_prospect(uuid) to authenticated;
revoke execute on function public.admin_save_partner(jsonb) from public, anon;
grant execute on function public.admin_save_partner(jsonb) to authenticated;
revoke execute on function public.admin_prospect_to_partner(uuid, jsonb) from public, anon;
grant execute on function public.admin_prospect_to_partner(uuid, jsonb) to authenticated;
revoke execute on function public.admin_save_partner_post(jsonb) from public, anon;
grant execute on function public.admin_save_partner_post(jsonb) to authenticated;
revoke execute on function public.admin_delete_partner_post(uuid) from public, anon;
grant execute on function public.admin_delete_partner_post(uuid) to authenticated;
revoke execute on function public.admin_partner_posts(uuid) from public, anon;
grant execute on function public.admin_partner_posts(uuid) to authenticated;
revoke execute on function public.admin_add_partner_fee(uuid, jsonb) from public, anon;
grant execute on function public.admin_add_partner_fee(uuid, jsonb) to authenticated;
revoke execute on function public.admin_delete_partner_fee(uuid) from public, anon;
grant execute on function public.admin_delete_partner_fee(uuid) to authenticated;
revoke execute on function public.admin_partners() from public, anon;
grant execute on function public.admin_partners() to authenticated;
revoke execute on function public.admin_partner_funnel(uuid) from public, anon;
grant execute on function public.admin_partner_funnel(uuid) to authenticated;
revoke execute on function public.admin_alerts() from public, anon;
grant execute on function public.admin_alerts() to authenticated;
