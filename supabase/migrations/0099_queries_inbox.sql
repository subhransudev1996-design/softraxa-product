-- ============================================================
-- 0099 — Queries inbox.
--
-- Every support request says what it is about: question, complaint,
-- problem in the app (bug), suggestion, billing or other. The shop
-- picks it in the app; the team can change it.
--
--   * priority (low / normal / high / urgent): complaints start high;
--   * first_reply_at and resolved_at, for the reply clock and reports;
--   * the shop rates a resolved request 1–5 (rate_ticket);
--   * suggestions: the same idea from many shops is one suggestion
--     (support_tickets.suggestion_id); its votes are the shops asking.
--     Marking it done tells every one of those shops in their request;
--   * saved replies the team reuses ({shop} and {owner} are filled in
--     by the panel).
-- Team access as in 0098: everything here is in the "support" area.
-- ============================================================

-- ============================================================
-- A. Suggestions and saved replies
-- ============================================================
create table if not exists public.suggestions (
  id          uuid primary key default gen_random_uuid(),
  title       text not null check (btrim(title) <> ''),
  details     text not null default '',
  status      text not null default 'new'
              check (status in ('new', 'planned', 'in_progress', 'done', 'declined')),
  done_note   text not null default '',
  done_at     timestamptz,
  created_by  uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
drop trigger if exists trg_suggestions_updated on public.suggestions;
create trigger trg_suggestions_updated before update on public.suggestions
  for each row execute function public.set_updated_at();

create table if not exists public.saved_replies (
  id          uuid primary key default gen_random_uuid(),
  title       text not null check (btrim(title) <> ''),
  body        text not null check (btrim(body) <> ''),
  created_by  uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
drop trigger if exists trg_saved_replies_updated on public.saved_replies;
create trigger trg_saved_replies_updated before update on public.saved_replies
  for each row execute function public.set_updated_at();

alter table public.suggestions enable row level security;
alter table public.saved_replies enable row level security;
do $$
declare t text;
begin
  foreach t in array array['suggestions', 'saved_replies'] loop
    execute format('drop policy if exists "admin all" on public.%I', t);
    execute format('create policy "admin all" on public.%I for all '
                   'using (public.is_admin()) with check (public.is_admin())', t);
    execute format('drop policy if exists "team area" on public.%I', t);
    execute format('create policy "team area" on public.%I as restrictive for all '
                   'using (not public.is_admin() or public.admin_can(''support'')) '
                   'with check (not public.is_admin() or public.admin_can(''support''))', t);
  end loop;
end $$;

-- ============================================================
-- B. What a request is about, priority, clock, rating
-- ============================================================
alter table public.support_tickets
  add column if not exists kind text not null default 'question',
  add column if not exists priority text not null default 'normal',
  add column if not exists first_reply_at timestamptz,
  add column if not exists resolved_at timestamptz,
  add column if not exists rating smallint,
  add column if not exists rating_note text not null default '',
  add column if not exists rated_at timestamptz,
  add column if not exists suggestion_id uuid references public.suggestions(id) on delete set null;

alter table public.support_tickets drop constraint if exists support_tickets_kind_check;
alter table public.support_tickets add constraint support_tickets_kind_check
  check (kind in ('question', 'complaint', 'bug', 'suggestion', 'billing', 'other'));
alter table public.support_tickets drop constraint if exists support_tickets_priority_check;
alter table public.support_tickets add constraint support_tickets_priority_check
  check (priority in ('low', 'normal', 'high', 'urgent'));
alter table public.support_tickets drop constraint if exists support_tickets_rating_check;
alter table public.support_tickets add constraint support_tickets_rating_check
  check (rating is null or rating between 1 and 5);
create index if not exists idx_tickets_kind on public.support_tickets(kind, status);
create index if not exists idx_tickets_suggestion on public.support_tickets(suggestion_id);

-- Requests from before: when resolved (first, while updated_at is still
-- the last change), the clock from the messages, and plan and
-- staff-login requests are billing.
update public.support_tickets set resolved_at = updated_at where status = 'resolved' and resolved_at is null;
update public.support_tickets t set first_reply_at = (
    select min(m.created_at) from public.support_messages m where m.ticket_id = t.id and m.from_softraxa)
 where first_reply_at is null
   and exists (select 1 from public.support_messages m where m.ticket_id = t.id and m.from_softraxa);
update public.support_tickets set kind = 'billing'
 where kind = 'question' and (requested_plan_id is not null or requested_staff is not null);

-- A shop only says what it is about; the team sets the rest.
create or replace function public.support_ticket_defaults()
returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    if public.is_direct_api_write() and not public.is_admin() then
      new.priority := 'normal';
      new.assigned_to := null;
      new.suggestion_id := null;
      new.rating := null;
      new.rating_note := '';
      new.rated_at := null;
      new.first_reply_at := null;
      new.resolved_at := null;
    end if;
    if new.requested_plan_id is not null or new.requested_staff is not null then
      new.kind := 'billing';
    end if;
    if new.kind = 'complaint' and new.priority = 'normal' then
      new.priority := 'high';
    end if;
  else
    if new.first_reply_at is null and new.last_reply_at is not null then
      new.first_reply_at := new.last_reply_at;
    end if;
    if new.status = 'resolved' and old.status is distinct from 'resolved' then
      new.resolved_at := now();
    elsif new.status <> 'resolved' then
      new.resolved_at := null;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_support_ticket_defaults on public.support_tickets;
create trigger trg_support_ticket_defaults before insert or update on public.support_tickets
  for each row execute function public.support_ticket_defaults();

-- ============================================================
-- C. The team: kind and priority
-- ============================================================
create or replace function public.admin_set_ticket_meta(p_ticket uuid, p_kind text, p_priority text)
returns void language plpgsql security definer set search_path = public as $$
declare v_business uuid;
begin
  perform public.assert_admin_area('support');
  update public.support_tickets
     set kind = coalesce(p_kind, kind), priority = coalesce(p_priority, priority)
   where id = p_ticket
  returning business_id into v_business;
  if v_business is null then raise exception 'Ticket not found'; end if;
  perform public.admin_log(v_business, 'support.meta', 'support_ticket', p_ticket::text,
    jsonb_build_object('kind', p_kind, 'priority', p_priority));
end $$;

-- ============================================================
-- D. Suggestions
-- ============================================================

-- Put a request under a suggestion: an existing one (p_suggestion), a new
-- one named p_title, or none (both null).
create or replace function public.admin_link_suggestion(p_ticket uuid, p_suggestion uuid, p_title text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_ticket public.support_tickets;
  v_id uuid := p_suggestion;
begin
  perform public.assert_admin_area('support');
  select * into v_ticket from public.support_tickets where id = p_ticket for update;
  if v_ticket.id is null then raise exception 'Ticket not found'; end if;
  if v_id is null and btrim(coalesce(p_title, '')) <> '' then
    insert into public.suggestions (title, details, created_by)
    values (btrim(p_title), coalesce(nullif(btrim(v_ticket.message), ''), v_ticket.subject), auth.uid())
    returning id into v_id;
  elsif v_id is not null and not exists (select 1 from public.suggestions where id = v_id) then
    raise exception 'Suggestion not found';
  end if;
  update public.support_tickets
     set suggestion_id = v_id, kind = case when v_id is null then kind else 'suggestion' end
   where id = p_ticket;
  perform public.admin_log(v_ticket.business_id, 'support.suggestion', 'support_ticket', p_ticket::text,
    jsonb_build_object('suggestion', v_id));
  return v_id;
end $$;

-- Save a suggestion. Marking it done tells every shop that asked, in its
-- request (and resolves those requests). Returns the requests told, so the
-- panel can send their phones a notification.
create or replace function public.admin_save_suggestion(
  p_id uuid, p_title text, p_details text, p_status text, p_note text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_old public.suggestions;
  v_id uuid;
  v_told uuid[] := '{}';
  v_body text;
  r record;
begin
  perform public.assert_admin_area('support');
  if btrim(coalesce(p_title, '')) = '' then raise exception 'Give the suggestion a title'; end if;
  if p_status not in ('new', 'planned', 'in_progress', 'done', 'declined') then raise exception 'Unknown status'; end if;

  if p_id is null then
    insert into public.suggestions (title, details, status, done_note, done_at, created_by)
    values (btrim(p_title), coalesce(p_details, ''), p_status, coalesce(p_note, ''),
            case when p_status = 'done' then now() end, auth.uid())
    returning id into v_id;
  else
    select * into v_old from public.suggestions where id = p_id for update;
    if v_old.id is null then raise exception 'Suggestion not found'; end if;
    update public.suggestions
       set title = btrim(p_title), details = coalesce(p_details, ''), status = p_status,
           done_note = coalesce(p_note, ''),
           done_at = case when p_status = 'done' then coalesce(done_at, now()) else null end
     where id = p_id;
    v_id := p_id;

    if p_status = 'done' and v_old.status <> 'done' then
      v_body := 'Good news: your suggestion "' || btrim(p_title) || '" is now in Dukania.'
        || case when btrim(coalesce(p_note, '')) <> '' then ' ' || btrim(p_note) else '' end
        || ' Update the app to get it. Thank you for telling us!';
      for r in select id, business_id from public.support_tickets where suggestion_id = v_id loop
        insert into public.support_messages (ticket_id, business_id, from_softraxa, body, created_by)
        values (r.id, r.business_id, true, v_body, auth.uid());
        update public.support_tickets
           set last_reply_at = clock_timestamp(), status = 'resolved', reply_notified_at = null
         where id = r.id;
        v_told := v_told || r.id;
      end loop;
    end if;
  end if;

  perform public.admin_log(null, 'suggestion.saved', 'suggestion', v_id::text,
    jsonb_build_object('status', p_status, 'told', cardinality(v_told)));
  return jsonb_build_object('id', v_id, 'told', to_jsonb(v_told));
end $$;

-- ============================================================
-- E. The shop rates a resolved request
-- ============================================================
create or replace function public.rate_ticket(p_ticket uuid, p_rating int, p_note text default '')
returns void language plpgsql security definer set search_path = public as $$
declare v_ticket public.support_tickets;
begin
  if p_rating is null or p_rating not between 1 and 5 then raise exception 'Choose 1 to 5 stars'; end if;
  select * into v_ticket from public.support_tickets
   where id = p_ticket and business_id = public.current_business_id() for update;
  if v_ticket.id is null then raise exception 'Support request not found'; end if;
  if v_ticket.status <> 'resolved' then raise exception 'You can rate a request once it is resolved'; end if;
  update public.support_tickets
     set rating = p_rating, rating_note = left(btrim(coalesce(p_note, '')), 500), rated_at = now()
   where id = p_ticket;
end $$;

-- ============================================================
-- Grants
-- ============================================================
revoke execute on function public.admin_set_ticket_meta(uuid, text, text) from public, anon;
revoke execute on function public.admin_link_suggestion(uuid, uuid, text) from public, anon;
revoke execute on function public.admin_save_suggestion(uuid, text, text, text, text) from public, anon;
revoke execute on function public.rate_ticket(uuid, int, text) from public, anon;
grant execute on function public.admin_set_ticket_meta(uuid, text, text) to authenticated;
grant execute on function public.admin_link_suggestion(uuid, uuid, text) to authenticated;
grant execute on function public.admin_save_suggestion(uuid, text, text, text, text) to authenticated;
grant execute on function public.rate_ticket(uuid, int, text) to authenticated;
