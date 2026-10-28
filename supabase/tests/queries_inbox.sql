-- ============================================================
-- Queries inbox (0099): kinds, priority, reply clock, rating,
-- suggestions with votes, saved replies.
--
-- HOW TO RUN — on a STAGING copy, after 0099:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the last line shows "queries_inbox tests passed".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('99999999-0000-0000-0000-0000000000ad', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'inbox-owner@test.invalid'),
  ('99999999-0000-0000-0000-00000000005a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'inbox-sales@test.invalid'),
  ('99999999-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'inbox-shop-a@test.invalid'),
  ('99999999-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'inbox-shop-b@test.invalid');
insert into public.businesses (id, name, state_code, phone) values
  ('99999999-1111-0000-0000-00000000000a', 'Inbox Shop A', '21', '9000099001'),
  ('99999999-1111-0000-0000-00000000000b', 'Inbox Shop B', '21', '9000099002');
update public.profiles set role = 'admin'
  where id in ('99999999-0000-0000-0000-0000000000ad', '99999999-0000-0000-0000-00000000005a');
insert into public.admin_team (user_id, team_role, areas) values
  ('99999999-0000-0000-0000-0000000000ad', 'owner', '{}'),
  ('99999999-0000-0000-0000-00000000005a', 'sales', '{clients,leads}');
update public.profiles set business_id = '99999999-1111-0000-0000-00000000000a', role = 'owner'
  where id = '99999999-0000-0000-0000-00000000000a';
update public.profiles set business_id = '99999999-1111-0000-0000-00000000000b', role = 'owner'
  where id = '99999999-0000-0000-0000-00000000000b';

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

do $$
declare
  owner constant uuid := '99999999-0000-0000-0000-0000000000ad';
  sales constant uuid := '99999999-0000-0000-0000-00000000005a';
  shop_a constant uuid := '99999999-0000-0000-0000-00000000000a';
  shop_b constant uuid := '99999999-0000-0000-0000-00000000000b';
  biz_a constant uuid := '99999999-1111-0000-0000-00000000000a';
  biz_b constant uuid := '99999999-1111-0000-0000-00000000000b';
  complaint uuid; idea_a uuid; idea_b uuid; sug uuid; v jsonb; n int;
begin
  -- 1. A shop says what it is about; it can't set the team's fields.
  perform pg_temp.act(shop_a);
  insert into public.support_tickets (business_id, subject, message, kind, priority, assigned_to)
  values (biz_a, 'Wrong total', 'The bill total is wrong', 'complaint', 'low', owner)
  returning id into complaint;
  insert into public.support_tickets (business_id, subject, message, kind)
  values (biz_a, 'Dark mode please', 'Night shop', 'suggestion') returning id into idea_a;
  perform pg_temp.act(owner);
  if (select priority from public.support_tickets where id = complaint) <> 'high' then
    raise exception 'FAIL 1a: a complaint did not start high';
  end if;
  if (select assigned_to from public.support_tickets where id = complaint) is not null then
    raise exception 'FAIL 1b: the shop assigned its own request';
  end if;
  raise notice 'PASS 1 (kind and priority)';

  -- 2. Reply clock, resolve, rating.
  perform pg_temp.act(shop_a);
  begin
    perform public.rate_ticket(complaint, 5);
    raise exception 'FAIL 2a: rated before it was resolved';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  perform pg_temp.act(owner);
  perform public.admin_reply_ticket(complaint, 'Fixed, sorry!', 'resolved');
  if (select first_reply_at is null or resolved_at is null from public.support_tickets where id = complaint) then
    raise exception 'FAIL 2b: reply clock or resolved time missing';
  end if;
  perform public.admin_set_ticket_meta(complaint, 'bug', 'urgent');
  perform pg_temp.act(shop_a);
  perform public.rate_ticket(complaint, 4, 'Quick');
  perform pg_temp.act(owner);
  if (select rating from public.support_tickets where id = complaint) <> 4
     or (select kind from public.support_tickets where id = complaint) <> 'bug' then
    raise exception 'FAIL 2c: rating or kind not saved';
  end if;
  perform pg_temp.act(shop_b);
  begin
    perform public.rate_ticket(complaint, 1);
    raise exception 'FAIL 2d: another shop rated the request';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 2 (clock and rating)';

  -- 3. The same idea from two shops is one suggestion; done tells both.
  insert into public.support_tickets (business_id, subject, message)
  values (biz_b, 'Black screen at night', 'Too bright') returning id into idea_b;
  perform pg_temp.act(owner);
  sug := public.admin_link_suggestion(idea_a, null, 'Dark mode');
  perform public.admin_link_suggestion(idea_b, sug);
  if (select kind from public.support_tickets where id = idea_b) <> 'suggestion' then
    raise exception 'FAIL 3a: linked request is not a suggestion';
  end if;
  select count(distinct business_id) into n from public.support_tickets where suggestion_id = sug;
  if n <> 2 then raise exception 'FAIL 3b: votes %', n; end if;
  v := public.admin_save_suggestion(sug, 'Dark mode', 'For night shops', 'done', 'Turn it on in Settings.');
  if jsonb_array_length(v -> 'told') <> 2 then raise exception 'FAIL 3c: told %', v; end if;
  perform pg_temp.act(shop_b);
  if not exists (select 1 from public.support_messages where ticket_id = idea_b and from_softraxa
                 and body like '%Dark mode%') then
    raise exception 'FAIL 3d: the shop was not told';
  end if;
  if (select status::text from public.support_tickets where id = idea_b) <> 'resolved' then
    raise exception 'FAIL 3e: request not resolved';
  end if;
  select count(*) into n from public.suggestions;
  if n <> 0 then raise exception 'FAIL 3f: a shop sees the suggestions board'; end if;
  raise notice 'PASS 3 (suggestions)';

  -- 4. Saved replies; Sales (no support area) sees none of it.
  perform pg_temp.act(owner);
  insert into public.saved_replies (title, body) values ('Thanks', 'Thank you {owner}!');
  perform pg_temp.act(sales);
  select count(*) into n from public.saved_replies;
  if n <> 0 then raise exception 'FAIL 4a: sales sees saved replies'; end if;
  begin
    perform public.admin_set_ticket_meta(complaint, 'question', 'low');
    raise exception 'FAIL 4b: sales changed a request';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 4 (support area only)';
end $$;

reset role;
select 'queries_inbox tests passed' as result;
rollback;
