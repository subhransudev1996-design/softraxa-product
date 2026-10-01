-- ============================================================
-- Website facts from Settings (migration 0059): the public website can
-- read contact details, download links, the starting price and trial
-- length — and nothing private; download links are saved safely.
--
-- HOW TO RUN — on a STAGING copy, after 0059:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- One transaction ending in ROLLBACK; your real settings are untouched.
-- Success: the run finishes without an error. The first failed check
-- stops the run with "FAIL …".
-- ============================================================

begin;

select set_config('request.jwt.claims', '', true);

insert into auth.users (id, instance_id, aud, role, email) values
  ('e7e7e7e7-0000-0000-0000-0000000000ad', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'web-admin@test.invalid');
update public.profiles set role = 'admin' where id = 'e7e7e7e7-0000-0000-0000-0000000000ad';

create or replace function pg_temp.act(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    case when p_user is null then ''
         else json_build_object('sub', p_user, 'role', 'authenticated')::text end, true);
$$;

do $$
declare
  admin constant uuid := 'e7e7e7e7-0000-0000-0000-0000000000ad';
  base  jsonb;
  v     jsonb;
  s     public.platform_settings;
begin
  select to_jsonb(ps) into base from public.platform_settings ps where id = 1;

  -- 1. An admin saves the download links (https only).
  perform pg_temp.act(admin);
  perform public.admin_save_settings(base || jsonb_build_object(
    'support_whatsapp', '9876543210', 'business_email', 'Hello@Example.com',
    'android_download_url', 'https://example.com/dukania.apk',
    'windows_download_url', 'https://example.com/Dukania-Setup.exe'));
  select * into s from public.platform_settings where id = 1;
  if s.android_download_url <> 'https://example.com/dukania.apk'
     or s.windows_download_url <> 'https://example.com/Dukania-Setup.exe' then
    raise exception 'FAIL 1a: download links not saved';
  end if;
  begin
    perform public.admin_save_settings(base || jsonb_build_object(
      'android_download_url', 'http://example.com/x.apk'));
    raise exception 'FAIL 1b: a non-https link was accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  raise notice 'PASS 1 (download links saved, https only)';

  -- 2. A save from the old Settings form (no link keys) keeps the links.
  perform public.admin_save_settings(base - 'android_download_url' - 'windows_download_url'
    || jsonb_build_object('support_whatsapp', '9876543210', 'business_email', 'Hello@Example.com'));
  select * into s from public.platform_settings where id = 1;
  if s.android_download_url = '' or s.windows_download_url = '' then
    raise exception 'FAIL 2: a save without the links erased them';
  end if;
  raise notice 'PASS 2 (links survive other saves)';
end $$;

-- 3. The public website (not logged in) reads the facts — and only those.
select pg_temp.act(null);
set local role anon;
do $$
declare v jsonb;
begin
  v := public.public_site_info();
  if v ->> 'whatsapp' <> '919876543210' then
    raise exception 'FAIL 3a: whatsapp is %', v ->> 'whatsapp';
  end if;
  if v ->> 'email' <> 'hello@example.com' then
    raise exception 'FAIL 3b: email is %', v ->> 'email';
  end if;
  if v ->> 'android_download_url' <> 'https://example.com/dukania.apk' then
    raise exception 'FAIL 3c: android link missing';
  end if;
  if (v ->> 'trial_days') is null then
    raise exception 'FAIL 3d: trial length missing';
  end if;
  if v ? 'payment_upi_id' or v ? 'business_gstin' or v ? 'confirmed_checks'
     or v::text like '%@okaxis%' then
    raise exception 'FAIL 3e: private settings leaked: %', v;
  end if;
  begin
    if exists (select 1 from public.platform_settings) then
      raise exception 'FAIL 3f: the public can read the settings table';
    end if;
  exception when insufficient_privilege then null;  -- no access at all: fine
  end;
  raise notice 'PASS 3 (public facts only: %)', v;
end $$;
reset role;

-- 4. The starting price is the cheapest active paid Dukania plan.
do $$
declare v jsonb; want numeric;
begin
  select min(p.yearly_price) into want from public.plans p
    join public.software_products sp on sp.id = p.software_id
    where sp.slug = 'dukania' and p.is_active and not p.is_trial
      and not coalesce(p.is_custom, false) and p.yearly_price > 0;
  v := public.public_site_info();
  if (v ->> 'from_yearly')::numeric is distinct from want then
    raise exception 'FAIL 4: from_yearly % but cheapest plan is %', v ->> 'from_yearly', want;
  end if;
  raise notice 'PASS 4 (starting price %)', want;
end $$;

-- 5. The Dukania FAQ in the website CMS was updated.
do $$
begin
  if not exists (select 1 from public.website_content
                 where page = 'dukania' and section = 'faqs' and key = 'items'
                   and value::text like '%Is there a free trial?%') then
    raise exception 'FAIL 5: Dukania FAQ not updated';
  end if;
  if not exists (select 1 from public.website_content
                 where page = 'home' and section = 'hero' and key = 'content'
                   and value ->> 'title' like '%your shop%') then
    raise exception 'FAIL 5b: home headline not updated';
  end if;
  raise notice 'PASS 5 (FAQ and home headline updated)';
end $$;

rollback;
select set_config('request.jwt.claims', '', false);
