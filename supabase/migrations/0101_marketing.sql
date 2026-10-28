-- ============================================================
-- 0101 — Marketing.
--
--   * a new team area, "marketing" (0098);
--   * admin_marketing_shops(): every shop with what a group is picked by
--     (plan, type, trial/paid, expiry, bills in the last 30 days…);
--   * announcements to a group of shops: an in-app banner (with an
--     optional button) and/or a phone notification (edge function
--     announce-push). Shops read theirs with my_announcements() and can
--     dismiss a banner;
--   * promo codes for plans (amount or % off the website price, uses,
--     end date), checked when a sale is recorded and redeemed on its
--     payment. The app still shows no prices;
--   * referrals: every shop has a code; a new shop enters a friend's code
--     (app, within 30 days) or the team sets it; the referred shop's first
--     payment earns the referrer free months (pending until the team
--     gives them on renewal);
--   * campaign costs, and a report of spend → leads → won → money.
-- ============================================================

-- ============================================================
-- A. The marketing area
-- ============================================================
create or replace function public.admin_all_areas()
returns text[] language sql immutable as $$
  select array['clients', 'payments', 'support', 'leads', 'marketing', 'catalog', 'plans', 'settings', 'website', 'system']
$$;

-- RLS for the tables below: the team, and only with the given area.
create or replace function pg_temp.team_table(p_table text, p_area text) returns void language plpgsql as $$
begin
  execute format('alter table public.%I enable row level security', p_table);
  execute format('drop policy if exists "admin all" on public.%I', p_table);
  execute format('create policy "admin all" on public.%I for all using (public.is_admin()) with check (public.is_admin())', p_table);
  execute format('drop policy if exists "team area" on public.%I', p_table);
  execute format('create policy "team area" on public.%I as restrictive for all '
                 'using (not public.is_admin() or public.admin_can(%L)) '
                 'with check (not public.is_admin() or public.admin_can(%L))', p_table, p_area, p_area);
end $$;

-- ============================================================
-- B. Shops for picking a group
-- ============================================================
create or replace function public.admin_marketing_shops()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.assert_admin_area('marketing');
  return coalesce((
    select jsonb_agg(jsonb_build_object(
        'id', b.id, 'name', b.name, 'owner_name', b.owner_name, 'phone', b.phone,
        'business_type', b.business_type, 'address', b.address, 'created_at', b.created_at,
        'onboarding_done', b.onboarding_done,
        'status', ls.status, 'expiry_date', ls.expiry_date, 'plan_id', ls.plan_id,
        'plan_name', p.name, 'billing', p.billing,
        'has_ai', public.business_has_ai(b.id),
        'last_bill_at', (select max(i.created_at) from public.invoices i where i.business_id = b.id),
        'bills_30d', (select count(*) from public.invoices i
                      where i.business_id = b.id and i.created_at > now() - interval '30 days'),
        'referral_code', b.referral_code)
      order by b.created_at desc)
    from public.businesses b
    left join public.latest_subscriptions ls on ls.business_id = b.id
    left join public.plans p on p.id = ls.plan_id
    where b.is_active), '[]'::jsonb);
end $$;

-- ============================================================
-- C. Announcements
-- ============================================================
create table if not exists public.announcements (
  id            uuid primary key default gen_random_uuid(),
  title         text not null check (btrim(title) <> '' and char_length(title) <= 120),
  body          text not null default '' check (char_length(body) <= 1000),
  button_label  text not null default '',
  button_url    text not null default '',
  business_ids  uuid[] not null,
  audience      text not null default '',
  banner        boolean not null default true,
  push          boolean not null default false,
  starts_at     timestamptz not null default now(),
  ends_at       timestamptz,
  push_sent_at  timestamptz,
  push_count    integer not null default 0,
  created_by    uuid references public.profiles(id) on delete set null,
  created_at    timestamptz not null default now()
);
create table if not exists public.announcement_dismissals (
  announcement_id uuid not null references public.announcements(id) on delete cascade,
  business_id     uuid not null references public.businesses(id) on delete cascade,
  dismissed_at    timestamptz not null default now(),
  primary key (announcement_id, business_id)
);
select pg_temp.team_table('announcements', 'marketing');
alter table public.announcement_dismissals enable row level security;  -- through the functions only

create or replace function public.admin_create_announcement(p jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_ids uuid[];
  v_url text := btrim(coalesce(p ->> 'button_url', ''));
  v_id uuid;
begin
  perform public.assert_admin_area('marketing');
  select array_agg(distinct x::uuid) into v_ids from jsonb_array_elements_text(coalesce(p -> 'business_ids', '[]')) x;
  if v_ids is null then raise exception 'Pick at least one shop'; end if;
  if cardinality(v_ids) > 10000 then raise exception 'Up to 10,000 shops at a time'; end if;
  if v_url <> '' and v_url !~ '^https://' then raise exception 'The button link must start with https://'; end if;
  if v_url <> '' and btrim(coalesce(p ->> 'button_label', '')) = '' then raise exception 'Name the button'; end if;
  if not coalesce((p ->> 'banner')::boolean, true) and not coalesce((p ->> 'push')::boolean, false) then
    raise exception 'Choose a banner, a notification or both';
  end if;
  insert into public.announcements (title, body, button_label, button_url, business_ids, audience,
                                    banner, push, ends_at, created_by)
  values (btrim(p ->> 'title'), btrim(coalesce(p ->> 'body', '')), btrim(coalesce(p ->> 'button_label', '')), v_url,
          v_ids, left(coalesce(p ->> 'audience', ''), 300),
          coalesce((p ->> 'banner')::boolean, true), coalesce((p ->> 'push')::boolean, false),
          nullif(p ->> 'ends_at', '')::timestamptz, auth.uid())
  returning id into v_id;
  perform public.admin_log(null, 'announcement.created', 'announcement', v_id::text,
    jsonb_build_object('shops', cardinality(v_ids), 'title', p ->> 'title'));
  return v_id;
end $$;

create or replace function public.admin_end_announcement(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_admin_area('marketing');
  update public.announcements set ends_at = now() where id = p_id and (ends_at is null or ends_at > now());
end $$;

-- The panel calls this through announce-push: hands over the notification once.
create or replace function public.claim_announcement_push(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v public.announcements;
begin
  perform public.assert_admin_area('marketing');
  update public.announcements set push_sent_at = now()
   where id = p_id and push and push_sent_at is null
  returning * into v;
  if v.id is null then return null; end if;
  return jsonb_build_object('title', v.title, 'body', v.body, 'business_ids', to_jsonb(v.business_ids));
end $$;

-- How many shops closed each banner: { announcement id: count }.
create or replace function public.admin_announcement_dismissals()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.assert_admin_area('marketing');
  return coalesce((select jsonb_object_agg(announcement_id, n)
                   from (select announcement_id, count(*) n from public.announcement_dismissals group by 1) x),
                  '{}'::jsonb);
end $$;

-- The shop's banners: running, for this shop, not dismissed.
create or replace function public.my_announcements()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'title', a.title, 'body', a.body,
            'button_label', a.button_label, 'button_url', a.button_url) order by a.starts_at desc), '[]'::jsonb)
  from public.announcements a
  where a.banner
    and public.current_business_id() = any(a.business_ids)
    and a.starts_at <= now() and (a.ends_at is null or a.ends_at > now())
    and not exists (select 1 from public.announcement_dismissals d
                    where d.announcement_id = a.id and d.business_id = public.current_business_id())
$$;

create or replace function public.dismiss_announcement(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_business uuid := public.current_business_id();
begin
  if v_business is null then raise exception 'No shop'; end if;
  if not exists (select 1 from public.announcements where id = p_id and v_business = any(business_ids)) then
    raise exception 'Not found';
  end if;
  insert into public.announcement_dismissals (announcement_id, business_id) values (p_id, v_business)
  on conflict do nothing;
end $$;

-- ============================================================
-- D. Promo codes
-- ============================================================
create table if not exists public.promo_codes (
  id           uuid primary key default gen_random_uuid(),
  code         text not null unique check (code ~ '^[A-Z0-9_-]{3,20}$'),
  kind         text not null check (kind in ('amount', 'percent')),
  value        numeric(12,2) not null check (value > 0),
  plan_ids     uuid[],                      -- null = every plan
  max_uses     integer check (max_uses is null or max_uses > 0),
  used_count   integer not null default 0,
  valid_until  date,
  active       boolean not null default true,
  note         text not null default '',
  created_by   uuid references public.profiles(id) on delete set null,
  created_at   timestamptz not null default now(),
  check (kind <> 'percent' or value <= 100)
);
create table if not exists public.promo_redemptions (
  id          uuid primary key default gen_random_uuid(),
  promo_id    uuid not null references public.promo_codes(id) on delete cascade,
  business_id uuid not null references public.businesses(id) on delete cascade,
  payment_id  uuid unique references public.subscription_payments(id) on delete set null,
  discount    numeric(12,2) not null default 0,
  created_by  uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now()
);
select pg_temp.team_table('promo_codes', 'marketing');
select pg_temp.team_table('promo_redemptions', 'marketing');

-- Is the code good for this plan, and how much off the website price?
-- Recording a sale (payments) or managing codes (marketing) may check.
create or replace function public.admin_check_promo(p_code text, p_plan uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v public.promo_codes;
  v_plan public.plans;
  v_web numeric;
  v_off numeric;
begin
  if not (public.admin_can('payments') or public.admin_can('marketing')) then
    raise exception 'Admin only' using errcode = '42501';
  end if;
  select * into v from public.promo_codes where code = upper(btrim(coalesce(p_code, '')));
  if v.id is null then return jsonb_build_object('ok', false, 'reason', 'No such code'); end if;
  if not v.active then return jsonb_build_object('ok', false, 'reason', 'This code is switched off'); end if;
  if v.valid_until is not null and v.valid_until < public.ist_date(now()) then
    return jsonb_build_object('ok', false, 'reason', 'This code ended on ' || to_char(v.valid_until, 'DD Mon YYYY'));
  end if;
  if v.max_uses is not null and v.used_count >= v.max_uses then
    return jsonb_build_object('ok', false, 'reason', 'This code has been used ' || v.used_count || ' times — its limit');
  end if;
  select * into v_plan from public.plans where id = p_plan;
  if v_plan.id is null then return jsonb_build_object('ok', false, 'reason', 'Choose the plan'); end if;
  if v.plan_ids is not null and not (p_plan = any(v.plan_ids)) then
    return jsonb_build_object('ok', false, 'reason', 'Not for the ' || v_plan.name || ' plan');
  end if;
  v_web := round(v_plan.list_price * (1 - (select website_discount_pct from public.platform_settings where id = 1) / 100));
  v_off := least(v_web, case when v.kind = 'amount' then v.value else round(v_web * v.value / 100) end);
  return jsonb_build_object('ok', true, 'code', v.code, 'kind', v.kind, 'value', v.value,
                            'website_price', v_web, 'discount', v_off, 'price', v_web - v_off);
end $$;

-- After the sale is recorded: the code is used on that payment (once).
create or replace function public.admin_redeem_promo(p_code text, p_payment uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_pay public.subscription_payments;
  v_check jsonb;
  v_promo uuid;
begin
  perform public.assert_admin_area('payments');
  select * into v_pay from public.subscription_payments where id = p_payment;
  if v_pay.id is null then raise exception 'Payment not found'; end if;
  if exists (select 1 from public.promo_redemptions where payment_id = p_payment) then
    raise exception 'A code is already used on this payment';
  end if;
  v_check := public.admin_check_promo(p_code, v_pay.plan_id);
  if not (v_check ->> 'ok')::boolean then raise exception '%', v_check ->> 'reason'; end if;
  update public.promo_codes set used_count = used_count + 1 where code = v_check ->> 'code'
  returning id into v_promo;
  insert into public.promo_redemptions (promo_id, business_id, payment_id, discount, created_by)
  values (v_promo, v_pay.business_id, p_payment, (v_check ->> 'discount')::numeric, auth.uid());
  update public.subscription_payments
     set breakdown = coalesce(breakdown, '{}'::jsonb) || jsonb_build_object('promo_code', v_check ->> 'code',
                                                                           'promo_discount', v_check -> 'discount')
   where id = p_payment;
  perform public.admin_log(v_pay.business_id, 'promo.redeemed', 'promo_code', v_promo::text, v_check);
  return v_check;
end $$;

-- ============================================================
-- E. Referrals
-- ============================================================
alter table public.businesses
  add column if not exists referral_code text,
  add column if not exists referred_by uuid references public.businesses(id) on delete set null,
  add column if not exists referred_at timestamptz;
alter table public.platform_settings
  add column if not exists referral_reward_months integer not null default 1
    check (referral_reward_months between 0 and 12);

create or replace function public.new_referral_code()
returns text language plpgsql volatile as $$
declare v text;
begin
  loop
    -- No 0/O or 1/I, so it reads well over the phone.
    v := 'DK' || (select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1 + floor(random() * 32)::int, 1), '')
                  from generate_series(1, 5));
    exit when not exists (select 1 from public.businesses where referral_code = v);
  end loop;
  return v;
end $$;

update public.businesses set referral_code = public.new_referral_code() where referral_code is null;
alter table public.businesses alter column referral_code set default public.new_referral_code();
create unique index if not exists idx_businesses_referral_code on public.businesses(referral_code);

-- A shop can't change its code or who referred it by writing to businesses.
create or replace function public.guard_business_referral()
returns trigger language plpgsql as $$
begin
  if public.is_direct_api_write() and not public.is_admin()
     and (new.referral_code is distinct from old.referral_code
          or new.referred_by is distinct from old.referred_by
          or new.referred_at is distinct from old.referred_at) then
    raise exception 'The referral code is set by Dukania' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists trg_business_referral_guard on public.businesses;
create trigger trg_business_referral_guard before update on public.businesses
  for each row execute function public.guard_business_referral();

create table if not exists public.referral_rewards (
  id           uuid primary key default gen_random_uuid(),
  referrer_id  uuid not null references public.businesses(id) on delete cascade,
  referred_id  uuid not null unique references public.businesses(id) on delete cascade,
  months       integer not null,
  status       text not null default 'pending' check (status in ('pending', 'given', 'skipped')),
  payment_id   uuid references public.subscription_payments(id) on delete set null,
  given_at     timestamptz,
  given_by     uuid references public.profiles(id) on delete set null,
  note         text not null default '',
  created_at   timestamptz not null default now()
);
select pg_temp.team_table('referral_rewards', 'marketing');
-- Giving a reward extends a subscription: payments may read them too.
drop policy if exists "team area" on public.referral_rewards;
create policy "team area" on public.referral_rewards as restrictive for all
  using (not public.is_admin() or public.admin_can('marketing') or public.admin_can('payments'))
  with check (not public.is_admin() or public.admin_can('marketing') or public.admin_can('payments'));

-- Link a shop to the one that referred it.
create or replace function public.set_referrer(p_business uuid, p_code text)
returns text language plpgsql security definer set search_path = public as $$
declare v_ref public.businesses;
begin
  select * into v_ref from public.businesses where referral_code = upper(btrim(coalesce(p_code, '')));
  if v_ref.id is null then raise exception 'No shop has the code %', upper(btrim(coalesce(p_code, ''))); end if;
  if v_ref.id = p_business then raise exception 'That is your own code'; end if;
  if v_ref.referred_by = p_business then raise exception 'That shop joined with your code'; end if;
  update public.businesses set referred_by = v_ref.id, referred_at = now() where id = p_business;
  return v_ref.name;
end $$;
revoke execute on function public.set_referrer(uuid, text) from public, anon, authenticated;

-- The owner, in the app, within 30 days of joining and only once.
create or replace function public.apply_referral_code(p_code text)
returns text language plpgsql security definer set search_path = public as $$
declare v_b public.businesses;
begin
  if (select role from public.profiles where id = auth.uid()) <> 'owner' then
    raise exception 'Only the owner can enter a referral code';
  end if;
  select * into v_b from public.businesses where id = public.current_business_id() for update;
  if v_b.id is null then raise exception 'No shop'; end if;
  if v_b.referred_by is not null then raise exception 'A referral code is already entered'; end if;
  if v_b.created_at < now() - interval '30 days' then
    raise exception 'A referral code can be entered in the first 30 days only';
  end if;
  return public.set_referrer(v_b.id, p_code);
end $$;

-- The team sets it (a shop told us on the phone).
create or replace function public.admin_set_referrer(p_business uuid, p_code text)
returns text language plpgsql security definer set search_path = public as $$
declare v_name text;
begin
  if not (public.admin_can('marketing') or public.admin_can('clients')) then
    raise exception 'Admin only' using errcode = '42501';
  end if;
  if btrim(coalesce(p_code, '')) = '' then
    update public.businesses set referred_by = null, referred_at = null where id = p_business;
    return null;
  end if;
  v_name := public.set_referrer(p_business, p_code);
  perform public.admin_log(p_business, 'referral.set', 'business', p_business::text, jsonb_build_object('code', upper(p_code)));
  return v_name;
end $$;

-- The shop's own code and what it has earned (no prices).
create or replace function public.my_referral()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'code', b.referral_code,
    'referred_by', (select r.name from public.businesses r where r.id = b.referred_by),
    'can_enter', b.referred_by is null and b.created_at > now() - interval '30 days',
    'joined', (select count(*) from public.businesses x where x.referred_by = b.id),
    'paid', (select count(*) from public.referral_rewards w where w.referrer_id = b.id),
    'months_earned', (select coalesce(sum(w.months), 0) from public.referral_rewards w
                      where w.referrer_id = b.id and w.status = 'given'),
    'reward_months', (select referral_reward_months from public.platform_settings where id = 1))
  from public.businesses b where b.id = public.current_business_id()
$$;

-- The referred shop's first payment earns the referrer its months.
create or replace function public.referral_reward_on_payment()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_ref uuid;
  v_months int := (select referral_reward_months from public.platform_settings where id = 1);
begin
  if new.amount <= 0 or coalesce(v_months, 0) <= 0 then return new; end if;
  select referred_by into v_ref from public.businesses where id = new.business_id;
  if v_ref is null then return new; end if;
  insert into public.referral_rewards (referrer_id, referred_id, months, payment_id)
  values (v_ref, new.business_id, v_months, new.id)
  on conflict (referred_id) do nothing;
  return new;
end $$;
drop trigger if exists trg_referral_reward on public.subscription_payments;
create trigger trg_referral_reward after insert on public.subscription_payments
  for each row execute function public.referral_reward_on_payment();

-- Give the free months (extends the referrer's plan) or skip the reward.
create or replace function public.admin_give_referral_reward(p_id uuid, p_give boolean, p_note text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v public.referral_rewards;
  v_sub public.subscriptions;
  v_billing text;
  v_to date;
  v_today date := public.ist_date(now());
begin
  perform public.assert_admin_area('payments');
  select * into v from public.referral_rewards where id = p_id for update;
  if v.id is null then raise exception 'Reward not found'; end if;
  if v.status <> 'pending' then raise exception 'This reward is already %', v.status; end if;
  if p_give then
    select s.* into v_sub from public.subscriptions s where s.business_id = v.referrer_id
      order by s.created_at desc limit 1 for update;
    if v_sub.id is null then raise exception 'The referring shop has no subscription'; end if;
    select billing into v_billing from public.plans where id = v_sub.plan_id;
    if v_billing = 'lifetime' then
      raise exception 'The referring shop is on Lifetime — give it something else, then Skip this reward';
    end if;
    v_to := (greatest(v_sub.expiry_date, v_today) + make_interval(months => v.months))::date;
    update public.subscriptions
       set expiry_date = v_to, status = case when status in ('expired') then 'active' else status end
     where id = v_sub.id;
  end if;
  update public.referral_rewards
     set status = case when p_give then 'given' else 'skipped' end, given_at = now(), given_by = auth.uid(),
         note = coalesce(p_note, '')
   where id = p_id;
  perform public.admin_log(v.referrer_id, case when p_give then 'referral.given' else 'referral.skipped' end,
    'referral_reward', p_id::text, jsonb_build_object('months', v.months, 'until', v_to));
  return jsonb_build_object('until', v_to);
end $$;

create or replace function public.admin_set_referral_months(p_months integer)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_admin_area('marketing');
  if p_months is null or p_months not between 0 and 12 then raise exception 'Between 0 and 12 months'; end if;
  update public.platform_settings set referral_reward_months = p_months where id = 1;
  perform public.admin_log(null, 'referral.months', 'platform_settings', '1', jsonb_build_object('months', p_months));
end $$;

-- ============================================================
-- F. Campaign costs and what campaigns brought
-- ============================================================
create table if not exists public.campaign_costs (
  id          uuid primary key default gen_random_uuid(),
  campaign    text not null check (btrim(campaign) <> ''),
  channel     text not null default '',
  amount      numeric(12,2) not null check (amount >= 0),
  spent_on    date not null default current_date,
  note        text not null default '',
  created_by  uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now()
);
select pg_temp.team_table('campaign_costs', 'marketing');

-- Per campaign (matched without case): spend, leads, won, money from the
-- won shops, cost per lead and per sale.
create or replace function public.admin_campaign_report()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.assert_admin_area('marketing');
  return coalesce((
    with names as (
      select lower(btrim(campaign)) k, min(btrim(campaign)) label from public.leads where btrim(campaign) <> '' group by 1
      union
      select lower(btrim(campaign)), min(btrim(campaign)) from public.campaign_costs group by 1
    ), keys as (select k, min(label) label from names group by k)
    select jsonb_agg(x order by x.spend desc, x.leads desc) from (
      select k.label as campaign,
        coalesce((select sum(c.amount) from public.campaign_costs c where lower(btrim(c.campaign)) = k.k), 0) as spend,
        (select min(c.spent_on) from public.campaign_costs c where lower(btrim(c.campaign)) = k.k) as first_spend,
        (select count(*) from public.leads l where lower(btrim(l.campaign)) = k.k) as leads,
        (select count(*) from public.leads l where lower(btrim(l.campaign)) = k.k and l.status = 'converted') as won,
        coalesce((select sum(sp.amount) from public.subscription_payments sp
                  where sp.business_id in (select l.converted_business_id from public.leads l
                                           where lower(btrim(l.campaign)) = k.k and l.converted_business_id is not null)), 0) as money
      from keys k) x), '[]'::jsonb);
end $$;

-- ============================================================
-- Grants
-- ============================================================
revoke execute on function public.admin_marketing_shops() from public, anon;
revoke execute on function public.admin_create_announcement(jsonb) from public, anon;
revoke execute on function public.admin_end_announcement(uuid) from public, anon;
revoke execute on function public.admin_announcement_dismissals() from public, anon;
revoke execute on function public.claim_announcement_push(uuid) from public, anon;
revoke execute on function public.my_announcements() from public, anon;
revoke execute on function public.dismiss_announcement(uuid) from public, anon;
revoke execute on function public.admin_check_promo(text, uuid) from public, anon;
revoke execute on function public.admin_redeem_promo(text, uuid) from public, anon;
revoke execute on function public.apply_referral_code(text) from public, anon;
revoke execute on function public.admin_set_referrer(uuid, text) from public, anon;
revoke execute on function public.my_referral() from public, anon;
revoke execute on function public.admin_give_referral_reward(uuid, boolean, text) from public, anon;
revoke execute on function public.admin_set_referral_months(integer) from public, anon;
revoke execute on function public.admin_campaign_report() from public, anon;
grant execute on function public.admin_marketing_shops() to authenticated;
grant execute on function public.admin_create_announcement(jsonb) to authenticated;
grant execute on function public.admin_end_announcement(uuid) to authenticated;
grant execute on function public.admin_announcement_dismissals() to authenticated;
grant execute on function public.claim_announcement_push(uuid) to authenticated;
grant execute on function public.my_announcements() to authenticated;
grant execute on function public.dismiss_announcement(uuid) to authenticated;
grant execute on function public.admin_check_promo(text, uuid) to authenticated;
grant execute on function public.admin_redeem_promo(text, uuid) to authenticated;
grant execute on function public.apply_referral_code(text) to authenticated;
grant execute on function public.admin_set_referrer(uuid, text) to authenticated;
grant execute on function public.my_referral() to authenticated;
grant execute on function public.admin_give_referral_reward(uuid, boolean, text) to authenticated;
grant execute on function public.admin_set_referral_months(integer) to authenticated;
grant execute on function public.admin_campaign_report() to authenticated;
