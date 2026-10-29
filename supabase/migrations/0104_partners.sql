-- ============================================================
-- 0104 — Influencer partners.
--
--   * partners: an influencer with a code (RAHUL10), a link
--     (dukania.in/r/RAHUL10), what a shop gets off with the code and the
--     partner's commission (default 20% of the shop's first payment, before
--     GST), paid after a hold (default 15 days) so refunds come first;
--   * the code is also a promo code (0101) for the shop's discount, so
--     Record a sale checks and uses it as before;
--   * a shop is linked to its partner when the owner enters the code in
--     the app (the same box as a shop's referral code), when the team sets
--     it, or when the code is used on its first payment;
--   * the first paid payment of a linked shop earns a commission; a refund
--     cuts it (or, once paid out, takes it back from the next payout);
--   * payouts: everything payable is paid in one go and recorded as a
--     "commission" expense in Accounts;
--   * the website counts link clicks (partner_click), shows the offer
--     (public_partner) and each partner's private stats page
--     (partner_stats, by a secret token — no shop names or phones).
-- ============================================================

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

-- Marketing runs partners; payments records sales and pays them out.
create or replace function pg_temp.partner_table(p_table text) returns void language plpgsql as $$
begin
  perform pg_temp.team_table(p_table, 'marketing');
  execute format('drop policy if exists "team area" on public.%I', p_table);
  execute format('create policy "team area" on public.%I as restrictive for all '
                 'using (not public.is_admin() or public.admin_can(''marketing'') or public.admin_can(''payments'')) '
                 'with check (not public.is_admin() or public.admin_can(''marketing'') or public.admin_can(''payments''))', p_table);
end $$;

-- ============================================================
-- A. Partners and defaults
-- ============================================================
alter table public.platform_settings
  add column if not exists partner_buyer_off_pct numeric(5,2) not null default 10
    check (partner_buyer_off_pct between 0 and 50),
  add column if not exists partner_commission_pct numeric(5,2) not null default 20
    check (partner_commission_pct between 0 and 100),
  add column if not exists partner_hold_days integer not null default 15
    check (partner_hold_days between 0 and 90);

create table if not exists public.partners (
  id                uuid primary key default gen_random_uuid(),
  name              text not null check (btrim(name) <> ''),
  handle            text not null default '',            -- @instagram
  phone             text not null default '',
  upi_id            text not null default '',
  code              text not null unique check (code ~ '^[A-Z0-9_-]{3,20}$'),
  buyer_off_pct     numeric(5,2) not null default 10 check (buyer_off_pct between 0 and 50),
  commission_kind   text not null default 'percent' check (commission_kind in ('percent', 'amount')),
  commission_value  numeric(12,2) not null default 20 check (commission_value >= 0),
  hold_days         integer not null default 15 check (hold_days between 0 and 90),
  promo_id          uuid references public.promo_codes(id) on delete set null,
  stats_token       text not null unique default replace(gen_random_uuid()::text, '-', ''),
  active            boolean not null default true,
  note              text not null default '',
  created_by        uuid references public.profiles(id) on delete set null,
  created_at        timestamptz not null default now(),
  check (commission_kind <> 'percent' or commission_value <= 100)
);
select pg_temp.partner_table('partners');

-- Link clicks per day (counted by the website, once per browser a day).
create table if not exists public.partner_clicks (
  partner_id  uuid not null references public.partners(id) on delete cascade,
  day         date not null,
  clicks      integer not null default 0,
  primary key (partner_id, day)
);
select pg_temp.partner_table('partner_clicks');

alter table public.businesses
  add column if not exists partner_id uuid references public.partners(id) on delete set null,
  add column if not exists partner_at timestamptz;
create index if not exists idx_businesses_partner on public.businesses(partner_id) where partner_id is not null;

-- A shop can't change its referrer or partner by writing to businesses.
create or replace function public.guard_business_referral()
returns trigger language plpgsql as $$
begin
  if public.is_direct_api_write() and not public.is_admin()
     and (new.referral_code is distinct from old.referral_code
          or new.referred_by is distinct from old.referred_by
          or new.referred_at is distinct from old.referred_at
          or new.partner_id is distinct from old.partner_id
          or new.partner_at is distinct from old.partner_at) then
    raise exception 'The referral code is set by Dukania' using errcode = '42501';
  end if;
  return new;
end $$;

-- Add or change a partner. The code can't change once made (it is in
-- their posts); the shop's discount is kept as its promo code.
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
    note = btrim(coalesce(p ->> 'note', note))
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

create or replace function public.admin_set_partner_defaults(p jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_admin_area('marketing');
  update public.platform_settings set
    partner_buyer_off_pct = coalesce((p ->> 'buyer_off_pct')::numeric, partner_buyer_off_pct),
    partner_commission_pct = coalesce((p ->> 'commission_pct')::numeric, partner_commission_pct),
    partner_hold_days = coalesce((p ->> 'hold_days')::int, partner_hold_days)
  where id = 1;
  perform public.admin_log(null, 'partner.defaults', 'platform_settings', '1', p);
end $$;

-- A fresh secret for the stats page (the old link stops working).
create or replace function public.admin_new_partner_link(p_partner uuid)
returns text language plpgsql security definer set search_path = public as $$
declare v text := replace(gen_random_uuid()::text, '-', '');
begin
  perform public.assert_admin_area('marketing');
  update public.partners set stats_token = v where id = p_partner;
  if not found then raise exception 'Partner not found'; end if;
  perform public.admin_log(null, 'partner.new_link', 'partner', p_partner::text, '{}'::jsonb);
  return v;
end $$;

-- ============================================================
-- B. Commissions
-- ============================================================
create table if not exists public.partner_payouts (
  id          uuid primary key default gen_random_uuid(),
  partner_id  uuid not null references public.partners(id) on delete cascade,
  amount      numeric(12,2) not null check (amount > 0),
  paid_on     date not null,
  mode        public.payment_mode not null default 'upi',
  reference   text not null default '',
  note        text not null default '',
  expense_id  uuid references public.business_expenses(id) on delete set null,
  created_by  uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now()
);
select pg_temp.partner_table('partner_payouts');

-- A sale row per shop (its first paid payment); a refund row when a refund
-- takes back commission that was already paid out.
create table if not exists public.partner_commissions (
  id           uuid primary key default gen_random_uuid(),
  partner_id   uuid not null references public.partners(id) on delete cascade,
  business_id  uuid not null references public.businesses(id) on delete cascade,
  payment_id   uuid references public.subscription_payments(id) on delete set null,
  refund_id    uuid unique references public.subscription_refunds(id) on delete set null,
  kind         text not null default 'sale' check (kind in ('sale', 'refund')),
  paid_amount  numeric(12,2) not null default 0,     -- what the shop paid
  base         numeric(12,2) not null default 0,     -- before GST
  rule         text not null default '',             -- "20%" or "₹500"
  amount       numeric(12,2) not null,               -- the commission (negative for a refund row)
  full_amount  numeric(12,2) not null default 0,     -- before any refund
  payable_on   date not null,
  status       text not null default 'pending' check (status in ('pending', 'paid', 'cancelled')),
  payout_id    uuid references public.partner_payouts(id) on delete set null,
  created_at   timestamptz not null default now()
);
create unique index if not exists idx_partner_commissions_sale on public.partner_commissions(business_id) where kind = 'sale';
create index if not exists idx_partner_commissions_partner on public.partner_commissions(partner_id, status);
select pg_temp.partner_table('partner_commissions');

-- The commission for a shop's first paid payment, if its partner is
-- active. Safe to call again (one sale row per shop).
create or replace function public.partner_commission_for(p_payment uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_pay public.subscription_payments;
  v_p public.partners;
  v_base numeric;
  v_amount numeric;
begin
  select * into v_pay from public.subscription_payments where id = p_payment;
  if v_pay.id is null or v_pay.amount <= 0 then return; end if;
  select p.* into v_p from public.partners p join public.businesses b on b.partner_id = p.id
   where b.id = v_pay.business_id;
  if v_p.id is null or not v_p.active then return; end if;
  -- Only the shop's first paid payment counts.
  if p_payment <> (select x.id from public.subscription_payments x
                    where x.business_id = v_pay.business_id and x.amount > 0
                    order by x.payment_date, x.created_at, x.id limit 1) then
    return;
  end if;
  v_base := coalesce((v_pay.tax ->> 'taxable')::numeric, v_pay.amount);
  v_amount := case when v_p.commission_kind = 'amount' then least(v_p.commission_value, v_base)
                   else round(v_base * v_p.commission_value / 100) end;
  if v_amount <= 0 then return; end if;
  insert into public.partner_commissions (partner_id, business_id, payment_id, kind, paid_amount, base, rule,
                                          amount, full_amount, payable_on)
  values (v_p.id, v_pay.business_id, v_pay.id, 'sale', v_pay.amount, v_base,
          case when v_p.commission_kind = 'amount' then '₹' || trim(to_char(v_p.commission_value, 'FM99999990'))
               else rtrim(rtrim(v_p.commission_value::text, '0'), '.') || '%' end,
          v_amount, v_amount, v_pay.payment_date + v_p.hold_days)
  on conflict (business_id) where kind = 'sale' do nothing;
end $$;
revoke execute on function public.partner_commission_for(uuid) from public, anon, authenticated;

create or replace function public.partner_commission_on_payment()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.partner_commission_for(new.id);
  return new;
end $$;
drop trigger if exists trg_partner_commission on public.subscription_payments;
create trigger trg_partner_commission after insert on public.subscription_payments
  for each row execute function public.partner_commission_on_payment();

-- A refund cuts the commission by the same share. Not yet paid out: the
-- row shrinks (cancelled at 0). Already paid: a refund row takes it back
-- from the next payout.
create or replace function public.partner_commission_on_refund()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  c public.partner_commissions;
  v_paid numeric;
  v_refunded numeric;
  v_target numeric;
  v_now numeric;
begin
  select * into c from public.partner_commissions
   where payment_id = new.payment_id and kind = 'sale' for update;
  if c.id is null or c.status = 'cancelled' then return new; end if;
  select amount into v_paid from public.subscription_payments where id = new.payment_id;
  v_refunded := (select coalesce(sum(amount), 0) from public.subscription_refunds where payment_id = new.payment_id);
  v_target := greatest(0, round(c.full_amount * (1 - v_refunded / nullif(v_paid, 0))));
  if c.status = 'pending' then
    update public.partner_commissions
       set amount = v_target, status = case when v_target = 0 then 'cancelled' else 'pending' end
     where id = c.id;
  else
    v_now := c.amount + coalesce((select sum(amount) from public.partner_commissions
                                   where kind = 'refund' and payment_id = new.payment_id and status <> 'cancelled'), 0);
    if v_target < v_now then
      insert into public.partner_commissions (partner_id, business_id, payment_id, refund_id, kind, paid_amount, base,
                                              rule, amount, full_amount, payable_on)
      values (c.partner_id, c.business_id, c.payment_id, new.id, 'refund', -new.amount, 0, c.rule,
              v_target - v_now, v_target - v_now, new.refund_date);
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_partner_commission_refund on public.subscription_refunds;
create trigger trg_partner_commission_refund after insert on public.subscription_refunds
  for each row execute function public.partner_commission_on_refund();

-- ============================================================
-- C. Linking a shop to its partner
-- ============================================================
-- The owner, in the app: a shop's referral code or a partner's code, in
-- the first 30 days and only once.
create or replace function public.apply_referral_code(p_code text)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_b public.businesses;
  v_p public.partners;
begin
  if (select role from public.profiles where id = auth.uid()) <> 'owner' then
    raise exception 'Only the owner can enter a referral code';
  end if;
  select * into v_b from public.businesses where id = public.current_business_id() for update;
  if v_b.id is null then raise exception 'No shop'; end if;
  if v_b.referred_by is not null or v_b.partner_id is not null then
    raise exception 'A referral code is already entered';
  end if;
  if v_b.created_at < now() - interval '30 days' then
    raise exception 'A referral code can be entered in the first 30 days only';
  end if;
  select * into v_p from public.partners where code = upper(btrim(coalesce(p_code, ''))) and active;
  if v_p.id is not null then
    update public.businesses set partner_id = v_p.id, partner_at = now() where id = v_b.id;
    return v_p.name;
  end if;
  return public.set_referrer(v_b.id, p_code);
end $$;

-- The team sets it (empty code = remove). A shop that has already paid
-- earns the partner its commission on that first payment.
create or replace function public.admin_set_partner(p_business uuid, p_code text)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_p public.partners;
  v_first uuid;
begin
  if not (public.admin_can('marketing') or public.admin_can('clients')) then
    raise exception 'Admin only' using errcode = '42501';
  end if;
  if btrim(coalesce(p_code, '')) = '' then
    if exists (select 1 from public.partner_commissions where business_id = p_business and status = 'paid') then
      raise exception 'Its partner was already paid for this shop';
    end if;
    delete from public.partner_commissions where business_id = p_business and status <> 'paid';
    update public.businesses set partner_id = null, partner_at = null where id = p_business;
    perform public.admin_log(p_business, 'partner.unlinked', 'business', p_business::text, '{}'::jsonb);
    return null;
  end if;
  select * into v_p from public.partners where code = upper(btrim(p_code));
  if v_p.id is null then raise exception 'No partner has the code %', upper(btrim(p_code)); end if;
  if exists (select 1 from public.partner_commissions where business_id = p_business and partner_id <> v_p.id) then
    raise exception 'This shop already earned another partner a commission — remove it first';
  end if;
  update public.businesses set partner_id = v_p.id, partner_at = coalesce(partner_at, now()) where id = p_business;
  select id into v_first from public.subscription_payments
   where business_id = p_business and amount > 0 order by payment_date, created_at, id limit 1;
  if v_first is not null then perform public.partner_commission_for(v_first); end if;
  perform public.admin_log(p_business, 'partner.linked', 'business', p_business::text, jsonb_build_object('code', v_p.code));
  return v_p.name;
end $$;

-- Using a partner's code on a payment links the shop (if not linked yet).
create or replace function public.admin_redeem_promo(p_code text, p_payment uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_pay public.subscription_payments;
  v_check jsonb;
  v_promo uuid;
  v_partner uuid;
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

  select id into v_partner from public.partners where promo_id = v_promo;
  if v_partner is not null then
    update public.businesses set partner_id = v_partner, partner_at = now()
     where id = v_pay.business_id and partner_id is null and referred_by is null;
    perform public.partner_commission_for(p_payment);
  end if;
  return v_check;
end $$;

-- The shop's own code and who it joined with (no prices).
create or replace function public.my_referral()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'code', b.referral_code,
    'referred_by', coalesce((select r.name from public.businesses r where r.id = b.referred_by),
                            (select p.name from public.partners p where p.id = b.partner_id)),
    'can_enter', b.referred_by is null and b.partner_id is null and b.created_at > now() - interval '30 days',
    'joined', (select count(*) from public.businesses x where x.referred_by = b.id),
    'paid', (select count(*) from public.referral_rewards w where w.referrer_id = b.id),
    'months_earned', (select coalesce(sum(w.months), 0) from public.referral_rewards w
                      where w.referrer_id = b.id and w.status = 'given'),
    'reward_months', (select referral_reward_months from public.platform_settings where id = 1))
  from public.businesses b where b.id = public.current_business_id()
$$;

-- ============================================================
-- D. Paying partners
-- ============================================================
-- Pay everything payable today (refund rows included) in one payout,
-- recorded as a commission expense.
create or replace function public.admin_pay_partner(p_partner uuid, p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_p public.partners;
  v_date date := coalesce(nullif(p ->> 'paid_on', '')::date, public.ist_date(now()));
  v_total numeric;
  v_expense uuid;
  v_payout uuid;
begin
  perform public.assert_admin_area('payments');
  select * into v_p from public.partners where id = p_partner for update;
  if v_p.id is null then raise exception 'Partner not found'; end if;
  select coalesce(sum(amount), 0) into v_total from public.partner_commissions
   where partner_id = p_partner and status = 'pending' and payable_on <= v_date;
  if v_total <= 0 then raise exception 'Nothing to pay yet'; end if;
  if coalesce(p ->> 'mode', 'upi') <> 'cash' and btrim(coalesce(p ->> 'reference', '')) = '' then
    raise exception 'Enter the UPI/bank reference number';
  end if;
  insert into public.business_expenses (spent_on, category, amount, vendor, note, created_by)
  values (v_date, 'commission', v_total, v_p.name,
          btrim('Partner ' || v_p.code || ' ' || coalesce(p ->> 'reference', '')), auth.uid())
  returning id into v_expense;
  insert into public.partner_payouts (partner_id, amount, paid_on, mode, reference, note, expense_id, created_by)
  values (p_partner, v_total, v_date, coalesce(nullif(p ->> 'mode', ''), 'upi')::public.payment_mode,
          btrim(coalesce(p ->> 'reference', '')), btrim(coalesce(p ->> 'note', '')), v_expense, auth.uid())
  returning id into v_payout;
  update public.partner_commissions set status = 'paid', payout_id = v_payout
   where partner_id = p_partner and status = 'pending' and payable_on <= v_date;
  perform public.admin_log(null, 'partner.paid', 'partner', p_partner::text,
    jsonb_build_object('amount', v_total, 'reference', p ->> 'reference'));
  return jsonb_build_object('payout_id', v_payout, 'amount', v_total);
end $$;

-- Every partner with what they brought and what is owed.
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
      'last_paid_on', (select max(o.paid_on) from public.partner_payouts o where o.partner_id = p.id)
    ) order by p.active desc, p.created_at desc)
    from public.partners p), '[]'::jsonb);
end $$;

-- ============================================================
-- E. For the website (anyone)
-- ============================================================
-- The offer behind a partner's link; null when the code isn't live.
create or replace function public.public_partner(p_code text)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('name', p.name, 'handle', p.handle, 'code', p.code, 'buyer_off_pct', p.buyer_off_pct)
  from public.partners p where p.code = upper(btrim(coalesce(p_code, ''))) and p.active
$$;

create or replace function public.partner_click(p_code text)
returns void language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  select id into v_id from public.partners where code = upper(btrim(coalesce(p_code, ''))) and active;
  if v_id is null then return; end if;
  insert into public.partner_clicks (partner_id, day, clicks) values (v_id, public.ist_date(now()), 1)
  on conflict (partner_id, day) do update set clicks = public.partner_clicks.clicks + 1;
end $$;

-- A partner's own numbers, by the secret in their stats link. Counts and
-- money only — no shop names or phone numbers.
create or replace function public.partner_stats(p_token text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v public.partners;
  v_today date := public.ist_date(now());
begin
  if coalesce(length(p_token), 0) <> 32 then return null; end if;
  select * into v from public.partners where stats_token = p_token;
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

-- ============================================================
-- Grants
-- ============================================================
revoke execute on function public.admin_save_partner(jsonb) from public, anon;
revoke execute on function public.admin_set_partner_defaults(jsonb) from public, anon;
revoke execute on function public.admin_new_partner_link(uuid) from public, anon;
revoke execute on function public.admin_set_partner(uuid, text) from public, anon;
revoke execute on function public.admin_pay_partner(uuid, jsonb) from public, anon;
revoke execute on function public.admin_partners() from public, anon;
revoke execute on function public.apply_referral_code(text) from public, anon;
revoke execute on function public.admin_redeem_promo(text, uuid) from public, anon;
revoke execute on function public.my_referral() from public, anon;
grant execute on function public.admin_save_partner(jsonb) to authenticated;
grant execute on function public.admin_set_partner_defaults(jsonb) to authenticated;
grant execute on function public.admin_new_partner_link(uuid) to authenticated;
grant execute on function public.admin_set_partner(uuid, text) to authenticated;
grant execute on function public.admin_pay_partner(uuid, jsonb) to authenticated;
grant execute on function public.admin_partners() to authenticated;
grant execute on function public.apply_referral_code(text) to authenticated;
grant execute on function public.admin_redeem_promo(text, uuid) to authenticated;
grant execute on function public.my_referral() to authenticated;
grant execute on function public.public_partner(text) to anon, authenticated;
grant execute on function public.partner_click(text) to anon, authenticated;
grant execute on function public.partner_stats(text) to anon, authenticated;
