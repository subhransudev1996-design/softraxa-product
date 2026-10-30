-- ============================================================
-- Managing influencers (0109): the pipeline, making a partner, posts, fixed
-- fees in Accounts, what a partner really made, who can do what.
--
-- HOW TO RUN — on a STAGING copy, after 0109:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the last line shows "influencer management tests passed".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('10910910-0000-0000-0000-0000000000ad', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'inf-owner@test.invalid'),
  ('10910910-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'inf-marketing@test.invalid'),
  ('10910910-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'inf-accounts@test.invalid'),
  ('10910910-0000-0000-0000-00000000000f', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'inf-partner@test.invalid'),
  ('10910910-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'inf-shop@test.invalid');
update public.profiles set role = 'admin' where id in
  ('10910910-0000-0000-0000-0000000000ad', '10910910-0000-0000-0000-0000000000a1', '10910910-0000-0000-0000-0000000000a2');
insert into public.admin_team (user_id, team_role, areas) values
  ('10910910-0000-0000-0000-0000000000ad', 'owner', '{}'),
  ('10910910-0000-0000-0000-0000000000a1', 'custom', '{marketing}'),
  ('10910910-0000-0000-0000-0000000000a2', 'custom', '{payments}');

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
create or replace function pg_temp.server() returns void language sql as $$
  select set_config('role', 'service_role', true),
         set_config('request.jwt.claims', '{"role":"service_role"}', true);
$$;

set local role authenticated;

do $$
declare
  owner constant uuid := '10910910-0000-0000-0000-0000000000ad';
  mkt constant uuid := '10910910-0000-0000-0000-0000000000a1';
  acc constant uuid := '10910910-0000-0000-0000-0000000000a2';
  partner constant uuid := '10910910-0000-0000-0000-00000000000f';
  shop constant uuid := '10910910-0000-0000-0000-00000000000a';
  today date := public.ist_date(now());
  x jsonb; x2 jsonb; ptn jsonb; v jsonb; sale jsonb; pid uuid; pxid uuid; post jsonb; fee jsonb;
  biz uuid; std uuid; exp_id uuid; base numeric; comm numeric; n int;
begin
  -- 1. The pipeline: saved, handle not twice, Joined only through Make partner.
  perform pg_temp.act(mkt);
  x := public.admin_save_prospect(jsonb_build_object('name', 'Inf Neha', 'handle', '@Inf.Neha', 'followers', '45000',
    'niche', 'Kirana tips', 'language', 'Hindi', 'city', 'Indore', 'phone', '9000109001',
    'deal_note', 'Asked ₹5,000 a reel', 'next_follow_up', today));
  pxid := (x ->> 'id')::uuid;
  if x ->> 'stage' <> 'found' or (x ->> 'followers')::int <> 45000 then raise exception 'FAIL 1a: %', x; end if;
  begin
    perform public.admin_save_prospect(jsonb_build_object('name', 'Copy', 'handle', 'inf.neha'));
    raise exception 'FAIL 1b: the same handle twice';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    perform public.admin_save_prospect(jsonb_build_object('id', pxid, 'name', 'Inf Neha', 'stage', 'joined'));
    raise exception 'FAIL 1c: joined without a code';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  x := public.admin_save_prospect(jsonb_build_object('id', pxid, 'name', 'Inf Neha', 'handle', '@Inf.Neha', 'stage', 'contacted'));
  if x ->> 'stage' <> 'contacted' or (x ->> 'last_contact_on')::date <> today or (x ->> 'followers')::int <> 45000 then
    raise exception 'FAIL 1d: %', x;
  end if;
  x2 := public.admin_save_prospect(jsonb_build_object('name', 'Inf Dropped', 'next_follow_up', today));
  x2 := public.admin_save_prospect(jsonb_build_object('id', x2 ->> 'id', 'name', 'Inf Dropped', 'stage', 'dropped', 'drop_reason', 'Too costly'));
  if x2 ->> 'next_follow_up' is not null or x2 ->> 'drop_reason' <> 'Too costly' then raise exception 'FAIL 1e: %', x2; end if;
  perform public.admin_delete_prospect((x2 ->> 'id')::uuid);
  raise notice 'PASS 1 (pipeline)';

  -- 2. A follow-up due is an alert for marketing, not for a payments-only login.
  if not exists (select 1 from jsonb_array_elements(public.admin_alerts() -> 'items') i
                  where i ->> 'title' = 'Follow up influencer: Inf Neha' and i ->> 'href' = '/influencers') then
    raise exception 'FAIL 2a: no follow-up alert';
  end if;
  perform pg_temp.act(acc);
  if exists (select 1 from jsonb_array_elements(public.admin_alerts() -> 'items') i where i ->> 'title' like 'Follow up influencer%') then
    raise exception 'FAIL 2b: payments login sees the follow-up';
  end if;
  raise notice 'PASS 2 (follow-up alert)';

  -- 3. Who can do what.
  begin
    perform public.admin_save_prospect(jsonb_build_object('name', 'Nope'));
    raise exception 'FAIL 3a: payments login added a prospect';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  if (select count(*) from public.partner_prospects where name = 'Inf Neha') <> 0 then
    raise exception 'FAIL 3b: payments login reads the pipeline';
  end if;
  perform pg_temp.act(shop);
  if (select count(*) from public.partner_prospects) <> 0 then raise exception 'FAIL 3c: a shop reads the pipeline'; end if;
  perform pg_temp.act(owner);
  begin
    insert into public.partner_prospects (name) values ('Direct');
    raise exception 'FAIL 3d: direct write worked';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 3 (access)';

  -- 4. Make partner: the code and deal, details kept; a bad code changes nothing.
  perform pg_temp.act(mkt);
  begin
    perform public.admin_prospect_to_partner(pxid, jsonb_build_object('code', 'x'));
    raise exception 'FAIL 4a: bad code accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  if (select stage from public.partner_prospects where id = pxid) <> 'contacted' then raise exception 'FAIL 4b: moved on a bad code'; end if;
  ptn := public.admin_prospect_to_partner(pxid, jsonb_build_object('code', 'INFNEHA', 'commission_value', 25, 'buyer_off_pct', 15));
  pid := (ptn ->> 'id')::uuid;
  if ptn ->> 'code' <> 'INFNEHA' or (ptn ->> 'commission_value')::numeric <> 25 or (ptn ->> 'followers')::int <> 45000
     or ptn ->> 'niche' <> 'Kirana tips' or ptn ->> 'phone' <> '9000109001' or ptn ->> 'note' not like '%₹5,000%' then
    raise exception 'FAIL 4c: %', ptn;
  end if;
  select to_jsonb(p) into x from public.partner_prospects p where id = pxid;
  if x ->> 'stage' <> 'joined' or (x ->> 'partner_id')::uuid <> pid or x ->> 'next_follow_up' is not null then raise exception 'FAIL 4d: %', x; end if;
  begin
    perform public.admin_prospect_to_partner(pxid, jsonb_build_object('code', 'INFNEHA2'));
    raise exception 'FAIL 4e: made a partner twice';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    perform public.admin_delete_prospect(pxid);
    raise exception 'FAIL 4f: deleted a joined record';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    perform public.admin_save_prospect(jsonb_build_object('id', pxid, 'name', 'Inf Neha', 'stage', 'found'));
    raise exception 'FAIL 4g: moved out of joined';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 4 (make partner)';

  -- 5. Posts: clicks only in the 3 days from the post; marketing only.
  post := public.admin_save_partner_post(jsonb_build_object('partner_id', pid, 'posted_on', today - 1, 'kind', 'reel',
    'url', 'https://instagram.com/reel/x', 'views', 1200));
  post := public.admin_save_partner_post(jsonb_build_object('id', post ->> 'id', 'views', '5000'));
  if (post ->> 'views')::int <> 5000 or post ->> 'url' = '' then raise exception 'FAIL 5a: %', post; end if;
  perform pg_temp.server();
  insert into public.partner_clicks (partner_id, day, clicks) values (pid, today, 5), (pid, today - 10, 7);
  perform pg_temp.act(mkt);
  v := public.admin_partner_posts(pid);
  if jsonb_array_length(v) <> 1 or (v -> 0 ->> 'clicks_3d')::int <> 5 or v -> 0 ->> 'partner_code' <> 'INFNEHA' then raise exception 'FAIL 5b: %', v; end if;
  perform pg_temp.act(acc);
  begin
    perform public.admin_save_partner_post(jsonb_build_object('partner_id', pid));
    raise exception 'FAIL 5c: payments login added a post';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 5 (posts)';

  -- 6. Fees: in Accounts as ads; a reference needed; payments only.
  begin
    perform public.admin_add_partner_fee(pid, jsonb_build_object('amount', 3000, 'mode', 'upi'));
    raise exception 'FAIL 6a: no reference';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  fee := public.admin_add_partner_fee(pid, jsonb_build_object('amount', 3000, 'mode', 'upi', 'reference', 'UTR109F', 'note', 'Secret fee note'));
  exp_id := (fee ->> 'expense_id')::uuid;
  if (select category from public.business_expenses where id = exp_id) <> 'ads'
     or (select amount from public.business_expenses where id = exp_id) <> 3000 then
    raise exception 'FAIL 6b: no expense';
  end if;
  perform pg_temp.act(mkt);
  begin
    perform public.admin_add_partner_fee(pid, jsonb_build_object('amount', 1, 'mode', 'cash'));
    raise exception 'FAIL 6c: marketing login paid a fee';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    insert into public.partner_fees (partner_id, amount, paid_on) values (pid, 1, today);
    raise exception 'FAIL 6d: direct write worked';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 6 (fees)';

  -- 7. What the partner made: revenue less commission less fees, before and after a part refund.
  perform pg_temp.act(shop);
  biz := public.create_business(jsonb_build_object('name', 'Inf Shop', 'phone', '9000109002'));
  perform public.apply_referral_code('INFNEHA');
  perform pg_temp.act(owner);
  select id into std from public.plans where name = 'Standard';
  sale := public.admin_record_sale(biz, jsonb_build_object('plan_id', std, 'amount', 2519, 'mode', 'upi', 'reference', 'UTR109S'));
  select m.base, m.amount into base, comm from public.partner_commissions m where m.partner_id = pid and m.kind = 'sale';
  select e into v from jsonb_array_elements(public.admin_partners()) e where (e ->> 'id')::uuid = pid;
  if (v ->> 'revenue')::numeric <> base or (v ->> 'fees')::numeric <> 3000 or (v ->> 'posts')::int <> 1
     or (v ->> 'net')::numeric <> base - comm - 3000 or (v ->> 'last_click_on')::date <> today then
    raise exception 'FAIL 7a: %', v;
  end if;
  perform public.admin_record_refund((sale ->> 'payment_id')::uuid, jsonb_build_object('amount', 1259.50, 'reason', 'Test', 'reference', 'R109'));
  select e into v from jsonb_array_elements(public.admin_partners()) e where (e ->> 'id')::uuid = pid;
  if abs((v ->> 'revenue')::numeric - base / 2) > 1 or (v ->> 'earned')::numeric >= comm then raise exception 'FAIL 7b: %', v; end if;
  x := public.admin_partner_funnel(pid);
  if (x ->> 'on_trial')::int <> 0 or jsonb_array_length(x -> 'months') <> 6 then raise exception 'FAIL 7c: %', x; end if;
  raise notice 'PASS 7 (net)';

  -- 8. A partner sees none of it.
  perform pg_temp.server();
  perform public.admin_link_partner_login(pid, partner, 'inf-partner@test.invalid');
  perform pg_temp.act(partner);
  v := public.my_partner();
  if v::text like '%Secret fee%' or v::text like '%instagram.com/reel%' or v::text like '%followers%' or v::text like '%UTR109F%' then
    raise exception 'FAIL 8a: %', v;
  end if;
  select count(*) into n from public.partner_fees;
  if n <> 0 or (select count(*) from public.partner_posts) <> 0 or (select count(*) from public.partner_prospects) <> 0 then
    raise exception 'FAIL 8b: a partner reads the tables';
  end if;
  begin
    perform public.admin_partner_posts(pid);
    raise exception 'FAIL 8c: a partner read the posts';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    perform public.partner_revenue(pid);
    raise exception 'FAIL 8d: partner_revenue is open';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 8 (partner sees none)';

  -- 9. Deleting: the fee takes the expense; an expense deleted in Accounts takes the fee.
  perform pg_temp.act(acc);
  perform public.admin_delete_partner_fee((fee ->> 'id')::uuid);
  if exists (select 1 from public.business_expenses where id = exp_id) then raise exception 'FAIL 9a: expense left'; end if;
  fee := public.admin_add_partner_fee(pid, jsonb_build_object('amount', 500, 'mode', 'cash'));
  delete from public.business_expenses where id = (fee ->> 'expense_id')::uuid;
  if exists (select 1 from public.partner_fees where id = (fee ->> 'id')::uuid) then raise exception 'FAIL 9b: fee left'; end if;
  perform pg_temp.act(mkt);
  perform public.admin_delete_partner_post((post ->> 'id')::uuid);
  if jsonb_array_length(public.admin_partner_posts(pid)) <> 0 then raise exception 'FAIL 9c: post left'; end if;
  raise notice 'PASS 9 (deleting)';
end $$;

reset role;
select 'influencer management tests passed' as result;
rollback;
