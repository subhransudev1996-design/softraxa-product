-- ============================================================
-- Two-way support and private notes (migration 0054).
--
-- HOW TO RUN — on a STAGING copy, after 0054:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('eaeaeaea-0000-0000-0000-0000000000ad', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'sup-admin@test.invalid'),
  ('eaeaeaea-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'sup-owner@test.invalid'),
  ('eaeaeaea-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'sup-other@test.invalid');

insert into public.businesses (id, name, state_code) values
  ('eaeaeaea-1111-0000-0000-00000000000a', 'SUP Shop', '27'),
  ('eaeaeaea-1111-0000-0000-00000000000b', 'SUP Other Shop', '27');
update public.profiles set role = 'admin' where id = 'eaeaeaea-0000-0000-0000-0000000000ad';
update public.profiles set business_id = 'eaeaeaea-1111-0000-0000-00000000000a', role = 'owner'
  where id = 'eaeaeaea-0000-0000-0000-00000000000a';
update public.profiles set business_id = 'eaeaeaea-1111-0000-0000-00000000000b', role = 'owner'
  where id = 'eaeaeaea-0000-0000-0000-00000000000b';
insert into public.subscriptions (business_id, status, expiry_date) values
  ('eaeaeaea-1111-0000-0000-00000000000a', 'active', current_date + 30),
  ('eaeaeaea-1111-0000-0000-00000000000b', 'active', current_date + 30);

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

do $$
declare
  admin  constant uuid := 'eaeaeaea-0000-0000-0000-0000000000ad';
  owner  constant uuid := 'eaeaeaea-0000-0000-0000-00000000000a';
  other  constant uuid := 'eaeaeaea-0000-0000-0000-00000000000b';
  shop   constant uuid := 'eaeaeaea-1111-0000-0000-00000000000a';
  tk uuid; v jsonb;
begin
  -- 1. A new ticket is waiting for SOFTRAXA and shows on Today.
  perform pg_temp.act(owner);
  insert into public.support_tickets (business_id, subject, message)
    values (shop, 'Printer not printing', 'Bluetooth printer stopped today') returning id into tk;
  perform pg_temp.act(admin);
  if not exists (select 1 from jsonb_array_elements(public.get_admin_today() -> 'tickets') t
                 where (t ->> 'id')::uuid = tk) then
    raise exception 'FAIL 1: new ticket not on Today';
  end if;
  raise notice 'PASS 1 (new ticket waits for SOFTRAXA)';

  -- 2. Private notes stay private.
  insert into public.admin_notes (business_id, ticket_id, note, created_by)
    values (shop, tk, 'Customer was rude on the phone', admin);
  perform pg_temp.act(owner);
  if exists (select 1 from public.admin_notes)
     or (select internal_note from public.support_tickets where id = tk) <> '' then
    raise exception 'FAIL 2: the shop can read a private note';
  end if;
  raise notice 'PASS 2 (the shop can''t read SOFTRAXA''s notes)';

  -- 3. Only SOFTRAXA replies as SOFTRAXA; an empty reply is refused.
  begin
    perform public.admin_reply_ticket(tk, 'fake answer');
    raise exception 'FAIL 3a: a shop replied as SOFTRAXA';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform pg_temp.act(admin);
  begin
    perform public.admin_reply_ticket(tk, '   ');
    raise exception 'FAIL 3b: empty reply';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 3 (reply is admin only and needs text)';

  -- 4. The reply reaches the shop: off Today, one unread, message visible.
  perform public.admin_reply_ticket(tk, 'Please unpair and pair the printer again.');
  if exists (select 1 from jsonb_array_elements(public.get_admin_today() -> 'tickets') t
             where (t ->> 'id')::uuid = tk) then
    raise exception 'FAIL 4a: answered ticket still on Today';
  end if;
  perform pg_temp.act(owner);
  if public.support_unread_count() <> 1
     or (select body from public.support_messages where ticket_id = tk and from_softraxa)
        <> 'Please unpair and pair the printer again.'
     or (select status from public.support_tickets where id = tk) <> 'in_progress' then
    raise exception 'FAIL 4b: reply not delivered';
  end if;
  perform public.mark_ticket_seen(tk);
  if public.support_unread_count() <> 0 then raise exception 'FAIL 4c: still unread'; end if;
  raise notice 'PASS 4 (reply delivered; unread 1 → 0 once opened)';

  -- 5. The announcement goes out once, and only SOFTRAXA can trigger it.
  begin
    perform public.claim_ticket_notification(tk);
    raise exception 'FAIL 5a: a shop claimed a notification';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform pg_temp.act(admin);
  v := public.claim_ticket_notification(tk);
  if v is null or (v ->> 'business_id')::uuid <> shop or public.claim_ticket_notification(tk) is not null then
    raise exception 'FAIL 5b: %', v;
  end if;
  raise notice 'PASS 5 (reply announced once)';

  -- 6. Another shop can't read or write on this ticket.
  perform pg_temp.act(other);
  if exists (select 1 from public.support_messages where ticket_id = tk) then
    raise exception 'FAIL 6a: another shop reads the thread';
  end if;
  begin
    perform public.reply_to_ticket(tk, 'hello');
    raise exception 'FAIL 6b: another shop wrote on the ticket';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 6 (threads are private to the shop)';

  -- 7. Resolved, then the shop writes back: reopened and waiting again.
  perform pg_temp.act(admin);
  perform public.admin_reply_ticket(tk, 'Glad it works. Closing this.', 'resolved');
  perform pg_temp.act(owner);
  perform public.reply_to_ticket(tk, 'It stopped again');
  if (select status from public.support_tickets where id = tk) <> 'open' then
    raise exception 'FAIL 7a: ticket not reopened';
  end if;
  perform pg_temp.act(admin);
  if not exists (select 1 from jsonb_array_elements(public.get_admin_today() -> 'tickets') t
                 where (t ->> 'id')::uuid = tk) then
    raise exception 'FAIL 7b: reopened ticket not on Today';
  end if;
  raise notice 'PASS 7 (shop''s reply reopens the ticket and puts it back on Today)';
end $$;

reset role;
do $$ begin raise notice 'ALL SUPPORT CHECKS PASSED — rolling back test data'; end $$;
rollback;
