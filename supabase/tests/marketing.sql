-- ============================================================
-- Marketing (0101): shop list, announcements, promo codes,
-- referrals and their reward, campaign report.
--
-- HOW TO RUN — on a STAGING copy, after 0101:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; no test data is left behind.
-- Success: the last line shows "marketing tests passed".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('10110110-0000-0000-0000-0000000000ad', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'mkt-owner@test.invalid'),
  ('10110110-0000-0000-0000-0000000000ac', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'mkt-accounts@test.invalid'),
  ('10110110-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'mkt-shop-a@test.invalid'),
  ('10110110-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'mkt-shop-b@test.invalid');
update public.profiles set role = 'admin'
  where id in ('10110110-0000-0000-0000-0000000000ad', '10110110-0000-0000-0000-0000000000ac');
insert into public.admin_team (user_id, team_role, areas) values
  ('10110110-0000-0000-0000-0000000000ad', 'owner', '{}'),
  ('10110110-0000-0000-0000-0000000000ac', 'accounts', '{payments}');
update public.platform_settings set referral_reward_months = 1 where id = 1;

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

do $$
declare
  owner constant uuid := '10110110-0000-0000-0000-0000000000ad';
  accounts constant uuid := '10110110-0000-0000-0000-0000000000ac';
  shop_a constant uuid := '10110110-0000-0000-0000-00000000000a';
  shop_b constant uuid := '10110110-0000-0000-0000-00000000000b';
  biz_a uuid; biz_b uuid; code_a text; ann uuid; std uuid; v jsonb; sale jsonb; reward uuid;
  exp_before date; n int;
begin
  perform pg_temp.act(shop_a);
  biz_a := public.create_business(jsonb_build_object('name', 'Mkt Shop A', 'phone', '9000101001'));
  perform pg_temp.act(shop_b);
  biz_b := public.create_business(jsonb_build_object('name', 'Mkt Shop B', 'phone', '9000101002'));

  -- 1. Every shop gets a referral code; the marketing list is for marketing only.
  perform pg_temp.act(owner);
  select referral_code into code_a from public.businesses where id = biz_a;
  if code_a !~ '^DK[A-Z2-9]{5}$' then raise exception 'FAIL 1a: referral code %', code_a; end if;
  v := public.admin_marketing_shops();
  if not exists (select 1 from jsonb_array_elements(v) e where (e ->> 'id')::uuid = biz_a) then
    raise exception 'FAIL 1b: shop missing from the marketing list';
  end if;
  perform pg_temp.act(accounts);
  begin
    perform public.admin_marketing_shops();
    raise exception 'FAIL 1c: accounts read the marketing list';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 1 (shops)';

  -- 2. A banner reaches only its shops and goes when dismissed; a push is handed over once.
  perform pg_temp.act(owner);
  ann := public.admin_create_announcement(jsonb_build_object('title', 'Diwali offer', 'body', 'Renew now',
    'business_ids', jsonb_build_array(biz_a), 'banner', true, 'push', true,
    'button_label', 'Read more', 'button_url', 'https://www.dukania.in'));
  if public.claim_announcement_push(ann) is null then raise exception 'FAIL 2a: push not handed over'; end if;
  if public.claim_announcement_push(ann) is not null then raise exception 'FAIL 2b: push handed over twice'; end if;
  perform pg_temp.act(shop_a);
  if jsonb_array_length(public.my_announcements()) <> 1 then raise exception 'FAIL 2c: shop A has no banner'; end if;
  perform public.dismiss_announcement(ann);
  if jsonb_array_length(public.my_announcements()) <> 0 then raise exception 'FAIL 2d: banner not dismissed'; end if;
  perform pg_temp.act(shop_b);
  if jsonb_array_length(public.my_announcements()) <> 0 then raise exception 'FAIL 2e: shop B sees A''s banner'; end if;
  raise notice 'PASS 2 (announcements)';

  -- 3. Shop B enters A's referral code (once, not its own, not by writing to businesses).
  begin
    perform public.apply_referral_code((select referral_code from public.businesses where id = biz_b));
    raise exception 'FAIL 3a: own code accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  if public.apply_referral_code(lower(code_a)) <> 'Mkt Shop A' then raise exception 'FAIL 3b: code not applied'; end if;
  begin
    perform public.apply_referral_code(code_a);
    raise exception 'FAIL 3c: a second code accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  begin
    update public.businesses set referred_by = null where id = biz_b;
    raise exception 'FAIL 3d: the shop changed its referrer';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  if (public.my_referral() ->> 'referred_by') <> 'Mkt Shop A' then raise exception 'FAIL 3e: my_referral'; end if;
  raise notice 'PASS 3 (referral code)';

  -- 4. A promo code on a sale; its limit; the referral reward from that payment.
  perform pg_temp.act(owner);
  insert into public.promo_codes (code, kind, value, max_uses) values ('MKTTEST500', 'amount', 500, 1);
  select id into std from public.plans where name = 'Standard';
  v := public.admin_check_promo('mkttest500', std);
  if not (v ->> 'ok')::boolean or (v ->> 'discount')::numeric <> 500 then raise exception 'FAIL 4a: check %', v; end if;
  perform pg_temp.act(accounts);
  sale := public.admin_record_sale(biz_b, jsonb_build_object('plan_id', std, 'amount', (v ->> 'price')::numeric,
    'mode', 'upi', 'reference', 'UTR101'));
  perform public.admin_redeem_promo('MKTTEST500', (sale ->> 'payment_id')::uuid);
  v := public.admin_check_promo('MKTTEST500', std);
  if (v ->> 'ok')::boolean then raise exception 'FAIL 4b: code used past its limit'; end if;
  select id into reward from public.referral_rewards where referred_id = biz_b and referrer_id = biz_a and status = 'pending';
  if reward is null then raise exception 'FAIL 4c: no referral reward'; end if;
  select expiry_date into exp_before from public.subscriptions where business_id = biz_a order by created_at desc limit 1;
  perform public.admin_give_referral_reward(reward, true);
  if (select expiry_date from public.subscriptions where business_id = biz_a order by created_at desc limit 1)
     <> (greatest(exp_before, public.ist_date(now())) + interval '1 month')::date then
    raise exception 'FAIL 4d: reward did not extend the plan';
  end if;
  begin
    perform public.admin_create_announcement(jsonb_build_object('title', 'x', 'business_ids', jsonb_build_array(biz_a)));
    raise exception 'FAIL 4e: accounts made an announcement';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 4 (promo and reward)';

  -- 5. What a campaign cost and brought.
  perform pg_temp.act(owner);
  insert into public.campaign_costs (campaign, channel, amount) values ('Mkt Test FB', 'facebook', 1000);
  update public.leads set campaign = 'mkt test fb' where converted_business_id = biz_b;
  v := public.admin_campaign_report();
  select count(*) into n from jsonb_array_elements(v) e
   where lower(e ->> 'campaign') = 'mkt test fb' and (e ->> 'spend')::numeric = 1000
     and (e ->> 'leads')::int = 1 and (e ->> 'won')::int = 1 and (e ->> 'money')::numeric > 0;
  if n <> 1 then raise exception 'FAIL 5: campaign report %', v; end if;
  raise notice 'PASS 5 (campaigns)';
end $$;

reset role;
select 'marketing tests passed' as result;
rollback;
