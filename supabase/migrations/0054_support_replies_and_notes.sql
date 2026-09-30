-- ============================================================
-- 0054_support_replies_and_notes.sql — admin panel, phases 2 and 3
--
--   * Two-way support. A ticket is now a thread: SOFTRAXA replies in the
--     admin panel (admin_reply_ticket) and the shop sees the answer in the
--     app and can write back (reply_to_ticket). The shop's first message
--     stays on the ticket; every later message is a support_messages row.
--     "Needs reply" = the shop wrote last; the Today page lists exactly
--     those (it used to list every unresolved ticket older than a day,
--     including ones waiting on the shop).
--   * Unread: a shop sees how many tickets have an answer it hasn't
--     opened (support_unread_count, mark_ticket_seen); the support-push
--     Edge Function announces each reply once (claim_ticket_notification).
--   * Private notes. support_tickets.internal_note was readable by the
--     shop (the app loads whole ticket rows). Notes move to admin_notes,
--     readable only by SOFTRAXA, and the old column is emptied. The same
--     table holds SOFTRAXA's own notes about a client.
--
-- Run AFTER 0053.
-- ============================================================

-- ============================================================
-- A. Private notes (SOFTRAXA only)
-- ============================================================
create table if not exists public.admin_notes (
  id           uuid primary key default gen_random_uuid(),
  business_id  uuid not null references public.businesses(id) on delete cascade,
  ticket_id    uuid references public.support_tickets(id) on delete cascade,
  note         text not null check (btrim(note) <> ''),
  created_by   uuid references public.profiles(id),
  created_at   timestamptz not null default now()
);
create index if not exists idx_admin_notes_business on public.admin_notes(business_id, created_at desc);

alter table public.admin_notes enable row level security;
drop policy if exists "admin all" on public.admin_notes;
create policy "admin all" on public.admin_notes for all
  using (public.is_admin()) with check (public.is_admin());

-- Move the notes shops could read out of the ticket rows.
insert into public.admin_notes (business_id, ticket_id, note, created_at)
select t.business_id, t.id, t.internal_note, t.updated_at
from public.support_tickets t
where btrim(t.internal_note) <> ''
  and not exists (select 1 from public.admin_notes n where n.ticket_id = t.id and n.note = t.internal_note);
update public.support_tickets set internal_note = '' where internal_note <> '';

-- ============================================================
-- B. Ticket threads
-- ============================================================
alter table public.support_tickets add column if not exists last_reply_at timestamptz;
alter table public.support_tickets add column if not exists last_shop_message_at timestamptz;
alter table public.support_tickets add column if not exists shop_seen_at timestamptz;
alter table public.support_tickets add column if not exists reply_notified_at timestamptz;

create table if not exists public.support_messages (
  id            uuid primary key default gen_random_uuid(),
  ticket_id     uuid not null references public.support_tickets(id) on delete cascade,
  business_id   uuid not null references public.businesses(id) on delete cascade,
  from_softraxa boolean not null,
  body          text not null check (btrim(body) <> ''),
  created_by    uuid references public.profiles(id),
  created_at    timestamptz not null default now()
);
create index if not exists idx_support_messages_ticket on public.support_messages(ticket_id, created_at);

-- Read: the shop its own, SOFTRAXA all. Written only by the functions below.
alter table public.support_messages enable row level security;
drop policy if exists "own read" on public.support_messages;
create policy "own read" on public.support_messages for select
  using (business_id = public.current_business_id() or public.is_admin());

-- The shop wrote last (or nobody has answered yet) and it isn't resolved.
create or replace function public.ticket_needs_reply(t public.support_tickets)
returns boolean language sql immutable as $$
  select t.status <> 'resolved'
     and (t.last_reply_at is null or coalesce(t.last_shop_message_at, t.created_at) > t.last_reply_at);
$$;

-- SOFTRAXA answers a ticket. p_status: in_progress (default) or resolved.
create or replace function public.admin_reply_ticket(
  p_ticket uuid, p_body text, p_status text default 'in_progress')
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_ticket record;
  v_id     uuid;
begin
  perform public.assert_platform_admin();
  if btrim(coalesce(p_body, '')) = '' then raise exception 'Write a reply'; end if;
  if p_status not in ('open', 'in_progress', 'resolved') then raise exception 'Unknown status'; end if;
  select * into v_ticket from public.support_tickets where id = p_ticket for update;
  if v_ticket.id is null then raise exception 'Ticket not found'; end if;

  insert into public.support_messages (ticket_id, business_id, from_softraxa, body, created_by)
    values (v_ticket.id, v_ticket.business_id, true, btrim(p_body), auth.uid())
    returning id into v_id;
  update public.support_tickets
     set last_reply_at = clock_timestamp(), status = p_status::public.ticket_status, reply_notified_at = null
   where id = v_ticket.id;
  perform public.admin_log(v_ticket.business_id, 'support.replied', 'support_ticket', v_ticket.id::text,
    jsonb_build_object('status', p_status));
  return v_id;
end $$;

-- Change a ticket's status without replying (e.g. solved on WhatsApp).
create or replace function public.admin_set_ticket_status(p_ticket uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_business uuid;
begin
  perform public.assert_platform_admin();
  if p_status not in ('open', 'in_progress', 'resolved') then raise exception 'Unknown status'; end if;
  update public.support_tickets set status = p_status::public.ticket_status
    where id = p_ticket returning business_id into v_business;
  if v_business is null then raise exception 'Ticket not found'; end if;
  perform public.admin_log(v_business, 'support.status', 'support_ticket', p_ticket::text,
    jsonb_build_object('status', p_status));
end $$;

-- The shop writes back on its own ticket; a resolved ticket reopens.
create or replace function public.reply_to_ticket(p_ticket uuid, p_body text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_ticket record;
  v_id     uuid;
begin
  if btrim(coalesce(p_body, '')) = '' then raise exception 'Write a message'; end if;
  select * into v_ticket from public.support_tickets
    where id = p_ticket and business_id = public.current_business_id() for update;
  if v_ticket.id is null then raise exception 'Support request not found'; end if;
  if (select count(*) from public.support_messages
      where ticket_id = p_ticket and not from_softraxa and created_at > now() - interval '1 hour') >= 20 then
    raise exception 'Too many messages — please wait for a reply or use WhatsApp';
  end if;

  insert into public.support_messages (ticket_id, business_id, from_softraxa, body, created_by)
    values (v_ticket.id, v_ticket.business_id, false, btrim(p_body), auth.uid())
    returning id into v_id;
  update public.support_tickets
     set last_shop_message_at = clock_timestamp(), shop_seen_at = clock_timestamp(),
         status = case when status = 'resolved' then 'open'::public.ticket_status else status end
   where id = v_ticket.id;
  return v_id;
end $$;

-- The shop opened the ticket: its answer is no longer unread.
create or replace function public.mark_ticket_seen(p_ticket uuid)
returns void language sql security definer set search_path = public as $$
  update public.support_tickets set shop_seen_at = clock_timestamp()
   where id = p_ticket and business_id = public.current_business_id();
$$;

-- Tickets with an answer the shop hasn't opened yet (app badge).
create or replace function public.support_unread_count()
returns integer language sql stable security definer set search_path = public as $$
  select count(*)::integer from public.support_tickets
  where business_id = public.current_business_id()
    and last_reply_at is not null
    and last_reply_at > coalesce(shop_seen_at, '-infinity'::timestamptz);
$$;

-- For the support-push Edge Function, called with the admin's login right
-- after a reply: what to announce, once per reply (null otherwise).
create or replace function public.claim_ticket_notification(p_ticket uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v record;
begin
  perform public.assert_platform_admin();
  update public.support_tickets t set reply_notified_at = clock_timestamp()
   where t.id = p_ticket and t.last_reply_at is not null and t.reply_notified_at is null
     and t.last_reply_at > now() - interval '10 minutes'
  returning t.* into v;
  if v.id is null then return null; end if;
  return jsonb_build_object('ticket_id', v.id, 'business_id', v.business_id, 'subject', v.subject);
end $$;

-- ============================================================
-- C. Today: tickets that are waiting for SOFTRAXA
-- ============================================================
-- 0053's get_admin_today with the tickets list changed.
create or replace function public.get_admin_today()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_today date := public.ist_date(now());
begin
  perform public.assert_platform_admin();
  return jsonb_build_object(
    'today', v_today,
    -- Shops that say they have paid: check your UPI app, then renew.
    'claims', coalesce((select jsonb_agg(t order by t.created_at) from (
        select c.id, c.business_id, b.name, b.phone, c.amount, c.reference, c.note, c.created_at,
               ls.plan_id, ls.expiry_date
        from public.renewal_claims c
        join public.businesses b on b.id = c.business_id
        left join public.latest_subscriptions ls on ls.business_id = c.business_id
        where c.status = 'pending') t), '[]'),
    -- Active or trial, expiring within 7 days.
    'expiring', coalesce((select jsonb_agg(t order by t.expiry_date) from (
        select b.id as business_id, b.name, b.phone, b.owner_name, ls.status, ls.expiry_date,
               ls.plan_id, p.name as plan_name, p.monthly_price, p.yearly_price
        from public.latest_subscriptions ls
        join public.businesses b on b.id = ls.business_id
        left join public.plans p on p.id = ls.plan_id
        where b.is_active and ls.status in ('active', 'trial')
          and ls.expiry_date between v_today and v_today + 7) t), '[]'),
    -- Expired in the last 60 days and not renewed (older ones are churned).
    'expired', coalesce((select jsonb_agg(t order by t.expiry_date desc) from (
        select b.id as business_id, b.name, b.phone, b.owner_name, ls.status, ls.expiry_date,
               ls.plan_id, p.name as plan_name, p.monthly_price, p.yearly_price
        from public.latest_subscriptions ls
        join public.businesses b on b.id = ls.business_id
        left join public.plans p on p.id = ls.plan_id
        where b.is_active and ls.status <> 'suspended'
          and ls.expiry_date + ls.grace_days < v_today
          and ls.expiry_date >= v_today - 60) t), '[]'),
    -- Support tickets waiting for SOFTRAXA: the shop wrote last (0054).
    'tickets', coalesce((select jsonb_agg(t order by t.waiting_since) from (
        select tk.id, tk.business_id, b.name, tk.subject, tk.status, tk.created_at,
               coalesce(tk.last_shop_message_at, tk.created_at) as waiting_since
        from public.support_tickets tk join public.businesses b on b.id = tk.business_id
        where public.ticket_needs_reply(tk)) t), '[]'),
    'open_tickets', (select count(*) from public.support_tickets where status <> 'resolved'),
    -- Signed up 2+ days ago and never finished the setup wizard.
    'setup', coalesce((select jsonb_agg(t order by t.created_at) from (
        select b.id as business_id, b.name, b.phone, b.owner_name, b.created_at
        from public.businesses b
        where b.is_active and not b.onboarding_done and b.created_at < now() - interval '2 days') t), '[]'),
    -- Paying/trial shops (7+ days old) with no bill in the last 7 days.
    'inactive', coalesce((select jsonb_agg(t order by t.last_bill nulls first) from (
        select b.id as business_id, b.name, b.phone, b.owner_name,
               (select max(i.created_at) from public.invoices i where i.business_id = b.id) as last_bill
        from public.businesses b
        join public.latest_subscriptions ls on ls.business_id = b.id
        where b.is_active and b.onboarding_done and b.created_at < now() - interval '7 days'
          and ls.status in ('active', 'trial') and ls.expiry_date >= v_today
          and not exists (select 1 from public.invoices i where i.business_id = b.id
                          and i.created_at > now() - interval '7 days')) t), '[]'),
    -- The latest nightly reconciliation.
    'reconciliation', (select jsonb_build_object('run_id', r.id, 'finished_at', r.finished_at,
                                                 'issues', r.issues, 'unexplained', r.unexplained)
                       from public.reconciliation_runs r order by r.started_at desc limit 1),
    -- Lead follow-ups due.
    'followups', coalesce((select jsonb_agg(t order by t.follow_up_date) from (
        select l.id, l.shop_name, l.contact_name, l.phone, l.status, l.follow_up_date
        from public.leads l
        where l.status in ('new', 'contacted', 'demo') and l.follow_up_date <= v_today) t), '[]')
  );
end $$;

-- ============================================================
-- Grants
-- ============================================================
revoke execute on function public.admin_reply_ticket(uuid, text, text) from public, anon;
revoke execute on function public.admin_set_ticket_status(uuid, text) from public, anon;
revoke execute on function public.reply_to_ticket(uuid, text) from public, anon;
revoke execute on function public.mark_ticket_seen(uuid) from public, anon;
revoke execute on function public.support_unread_count() from public, anon;
revoke execute on function public.claim_ticket_notification(uuid) from public, anon;
grant execute on function public.admin_reply_ticket(uuid, text, text) to authenticated;
grant execute on function public.admin_set_ticket_status(uuid, text) to authenticated;
grant execute on function public.reply_to_ticket(uuid, text) to authenticated;
grant execute on function public.mark_ticket_seen(uuid) to authenticated;
grant execute on function public.support_unread_count() to authenticated;
grant execute on function public.claim_ticket_notification(uuid) to authenticated;
