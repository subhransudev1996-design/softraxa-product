-- ============================================================
-- Dukania, not Softraxa, in what the server says (migration 0095).
--
-- HOW TO RUN — on a STAGING copy, after 0095:
--   Supabase Dashboard → SQL Editor → paste this file → Run.
-- Read-only. Success: the last line shows "dukania_name tests passed".
-- ============================================================

do $$
declare
  v_left text;
begin
  -- No function shows SOFTRAXA any more (database names like
  -- from_softraxa are lower case and stay).
  select string_agg(p.proname, ', ') into v_left
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prosrc like '%SOFTRAXA%';
  if v_left is not null then
    raise exception 'FAIL 1: still says SOFTRAXA: %', v_left;
  end if;

  if (select column_default from information_schema.columns
      where table_schema = 'public' and table_name = 'platform_settings'
        and column_name = 'payment_payee_name') not like '%Dukania%' then
    raise exception 'FAIL 2: payee name default';
  end if;
  if exists (select 1 from public.platform_settings
             where payment_payee_name = 'SOFTRAXA' or business_name = 'SOFTRAXA') then
    raise exception 'FAIL 3: settings still say SOFTRAXA';
  end if;

  -- The website's copy is Dukania's.
  if exists (select 1 from public.website_seo
             where (title || description || keywords::text || og_title || og_description || twitter_title
                    || twitter_description || structured_data::text) ilike '%softraxa%') then
    raise exception 'FAIL 4: website titles still say Softraxa';
  end if;
  if exists (select 1 from public.website_content where value::text ilike '%softraxa%') then
    raise exception 'FAIL 5: website copy still says Softraxa';
  end if;
  if (select title from public.website_seo where path = '/') not like 'Dukania%' then
    raise exception 'FAIL 6: home page title';
  end if;
end $$;

select 'dukania_name tests passed' as result;
