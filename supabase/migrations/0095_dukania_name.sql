-- ============================================================
-- 0095: Dukania, not Softraxa, in what the server says.
--
-- The product is Dukania on its own now (dukania.in). These functions
-- are re-created from their latest versions with only their messages
-- changed ("contact Dukania support", "Only the Dukania admin can …"),
-- and the renewal payee / business name default to "Dukania".
-- Names inside the database (from_softraxa, source 'softraxa') stay:
-- nobody sees them.
--
-- Run AFTER 0094.
-- ============================================================

alter table public.platform_settings alter column payment_payee_name set default 'Dukania';
alter table public.platform_settings alter column business_name set default 'Dukania';
update public.platform_settings set payment_payee_name = 'Dukania' where payment_payee_name = 'SOFTRAXA';
update public.platform_settings set business_name = 'Dukania' where business_name = 'SOFTRAXA';

-- e-invoicing message (as 0048)
create or replace function public.complete_onboarding(payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_old      record;
  v_category text;
  v_tax      text;
  v_gstin    text;
  v_state    text;
  v_band     text;
  v_upi      text;
  v_prefix   text;
begin
  if v_business is null then raise exception 'Create your shop first'; end if;
  perform public.assert_can('owner');
  select * into v_old from public.businesses where id = v_business for update;

  v_category := coalesce(nullif(payload ->> 'business_type', ''), v_old.business_type::text);
  if v_category not in (select unnest(enum_range(null::public.business_type))::text) then
    raise exception 'Choose your type of shop';
  end if;

  v_tax := coalesce(nullif(payload ->> 'tax_preference', ''), v_old.tax_preference::text);
  if v_tax not in ('gst', 'composition', 'non_gst') then
    raise exception 'Choose regular GST, composition or not registered';
  end if;
  v_gstin := upper(btrim(coalesce(payload ->> 'gst_number', v_old.gst_number, '')));
  v_state := coalesce(nullif(payload ->> 'state_code', ''), v_old.state_code);
  v_band := coalesce(nullif(payload ->> 'turnover_band', ''), v_old.turnover_band);

  if v_tax in ('gst', 'composition') then
    if not public.is_valid_gstin(v_gstin) then
      raise exception 'Enter a valid 15-character GSTIN';
    end if;
    v_state := left(v_gstin, 2);
    if v_band is null then
      raise exception 'Choose your annual turnover';
    end if;
    if v_band = 'above_5cr' then
      raise exception 'Businesses with turnover above ₹5 crore need e-invoicing, which Dukania doesn''t support yet. Please contact Dukania support.';
    end if;
  else
    v_gstin := '';
  end if;

  v_upi := btrim(coalesce(payload ->> 'upi_id', v_old.upi_id, ''));
  if v_upi <> '' and v_upi !~ '^[A-Za-z0-9._-]{2,255}@[A-Za-z][A-Za-z0-9]{1,63}$' then
    raise exception 'Enter a valid UPI ID, for example shopname@okaxis';
  end if;

  -- 'INV/26-27/0001' must fit in 16 characters.
  v_prefix := upper(btrim(coalesce(nullif(payload ->> 'invoice_prefix', ''), v_old.invoice_prefix, 'INV')));
  if v_prefix !~ '^[A-Z0-9]{1,4}$' then
    raise exception 'Invoice prefix: 1–4 letters or digits, for example INV';
  end if;

  update public.businesses set
    business_type  = v_category::public.business_type,
    tax_preference = v_tax::public.tax_preference,
    gst_number     = v_gstin,
    state_code     = v_state,
    turnover_band  = v_band,
    upi_id         = v_upi,
    invoice_prefix = v_prefix,
    name           = coalesce(nullif(btrim(payload ->> 'name'), ''), name),
    owner_name     = coalesce(payload ->> 'owner_name', owner_name),
    phone          = coalesce(payload ->> 'phone', phone),
    address        = coalesce(payload ->> 'address', address),
    onboarding_done = true
  where id = v_business;

  if not v_old.onboarding_done or v_category <> v_old.business_type::text then
    perform public.apply_category_defaults(v_business, v_category);
  end if;

  perform public.log_audit('business.onboarded', 'business', v_business::text,
    jsonb_build_object('category', v_category, 'tax', v_tax, 'turnover_band', v_band));
  return (select to_jsonb(b) from public.businesses b where b.id = v_business);
end $$;

-- renewal still being checked (as 0053)
create or replace function public.submit_renewal_claim(
  p_amount numeric, p_reference text, p_note text default '')
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_id       uuid;
begin
  if v_business is null then raise exception 'No shop selected'; end if;
  if not public.has_permission('owner') then
    raise exception 'Only the owner can report a subscription payment' using errcode = '42501';
  end if;
  if coalesce(p_amount, 0) <= 0 then raise exception 'Enter the amount you paid'; end if;
  if btrim(coalesce(p_reference, '')) = '' then
    raise exception 'Enter the UPI reference (UTR) number from your payment app';
  end if;
  if (select count(*) from public.renewal_claims
      where business_id = v_business and status = 'pending') >= 3 then
    raise exception 'Your earlier payments are still being checked — Dukania will confirm soon';
  end if;
  insert into public.renewal_claims (business_id, amount, reference, note, created_by)
    values (v_business, p_amount, btrim(p_reference), coalesce(p_note, ''), auth.uid())
    returning id into v_id;
  insert into public.audit_logs (business_id, user_id, action, entity, entity_id, details)
    values (v_business, auth.uid(), 'subscription.payment_claimed', 'renewal_claim', v_id::text,
            jsonb_build_object('amount', p_amount, 'reference', btrim(p_reference)));
  return v_id;
end $$;

-- ChatGPT / Claude refusals (as 0086)
create or replace function public.ai_context()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_profile  public.profiles;
  v_business public.businesses;
  v_id       uuid := public.current_business_id();
  v_reason   text;
  v_perms    jsonb := '{}'::jsonb;
  v_key      text;
  v_sub      jsonb;
begin
  select * into v_profile from public.profiles where id = auth.uid();
  select * into v_business from public.businesses where id = v_id;

  if v_profile.id is null then
    v_reason := 'Sign in with your Dukania account.';
  elsif v_profile.role::text = 'admin' then
    v_reason := 'This is a Dukania admin account. Use the Dukania Admin connector instead.';
  elsif v_profile.business_id is null then
    v_reason := 'This account isn''t part of a shop yet. Finish setting up your shop in the Dukania app first.';
  elsif v_id is null then
    v_reason := 'Your shop''s plan has more staff than it allows, so this login is paused. Ask the shop owner.';
  elsif not coalesce(v_business.is_active, false) then
    v_reason := 'This shop is suspended. Contact Dukania support.';
  elsif not coalesce((select f.ai_assistant from public.feature_flags f where f.business_id = v_id), false) then
    v_reason := 'The AI assistant isn''t included in your shop''s plan. Contact Dukania to add it.';
  elsif not public.has_permission('can_use_ai') then
    v_reason := 'The shop owner hasn''t allowed you to use the AI assistant. Ask them to turn it on for you in Staff.';
  end if;

  if v_reason is not null then
    return jsonb_build_object('allowed', false, 'reason', v_reason);
  end if;

  for v_key in select jsonb_object_keys(public.staff_permission_defaults()) loop
    v_perms := v_perms || jsonb_build_object(v_key, public.has_permission(v_key));
  end loop;
  v_perms := v_perms || jsonb_build_object('owner', public.has_permission('owner'));

  select jsonb_build_object(
           'plan', pl.name, 'status', s.status, 'expiry_date', s.expiry_date,
           'can_make_changes', public.business_is_writable(v_id))
    into v_sub
    from public.subscriptions s left join public.plans pl on pl.id = s.plan_id
    where s.business_id = v_id
    order by s.created_at desc limit 1;

  return jsonb_build_object(
    'allowed', true,
    'shop', jsonb_strip_nulls(jsonb_build_object(
      'name', v_business.name,
      'type', v_business.business_type,
      'gstin', nullif(v_business.gst_number, ''),
      'state_code', nullif(v_business.state_code, ''),
      'tax', v_business.tax_preference,
      'phone', nullif(v_business.phone, ''))),
    'user', jsonb_build_object('name', v_profile.full_name, 'role', v_profile.role),
    'permissions', v_perms,
    'features', (select to_jsonb(f) - 'business_id' - 'updated_at'
                 from public.feature_flags f where f.business_id = v_id),
    'subscription', v_sub,
    'today', public.ist_date(now()));
end $$;

-- default payee and business name (as 0059)
create or replace function public.admin_save_settings(p jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_old     public.platform_settings;
  v_new     public.platform_settings;
  v_upi     text := btrim(coalesce(p ->> 'payment_upi_id', ''));
  v_wa      text := regexp_replace(coalesce(p ->> 'support_whatsapp', ''), '[^0-9]', '', 'g');
  v_gstin   text := upper(btrim(coalesce(p ->> 'business_gstin', '')));
  v_email   text := lower(btrim(coalesce(p ->> 'business_email', '')));
  v_android text := btrim(coalesce(p ->> 'android_download_url', ''));
  v_windows text := btrim(coalesce(p ->> 'windows_download_url', ''));
begin
  perform public.assert_platform_admin();
  if v_upi <> '' and v_upi !~ '^[A-Za-z0-9._-]{2,255}@[A-Za-z][A-Za-z0-9]{1,63}$' then
    raise exception 'That doesn''t look like a UPI ID — it should be like dukania@okaxis';
  end if;
  if length(v_wa) = 10 then v_wa := '91' || v_wa; end if;
  if v_wa <> '' and length(v_wa) not between 11 and 15 then
    raise exception 'The WhatsApp number should be 10 digits, or the country code and the number';
  end if;
  if v_gstin <> '' and v_gstin !~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][0-9A-Z]Z[0-9A-Z]$' then
    raise exception 'That doesn''t look like a GSTIN (15 characters, like 27ABCDE1234F1Z5)';
  end if;
  if v_email <> '' and v_email !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' then
    raise exception 'That doesn''t look like an email address';
  end if;
  if char_length(coalesce(p ->> 'receipt_footer', '')) > 200 then
    raise exception 'Keep the receipt footer under 200 characters';
  end if;
  if (v_android <> '' and v_android !~ '^https://[^[:space:]]+$')
     or (v_windows <> '' and v_windows !~ '^https://[^[:space:]]+$') then
    raise exception 'Download links must start with https://';
  end if;

  select * into v_old from public.platform_settings where id = 1 for update;
  update public.platform_settings set
    payment_upi_id       = v_upi,
    payment_payee_name   = coalesce(nullif(btrim(p ->> 'payment_payee_name'), ''), 'Dukania'),
    support_whatsapp     = v_wa,
    business_name        = coalesce(nullif(btrim(p ->> 'business_name'), ''), 'Dukania'),
    business_address     = btrim(coalesce(p ->> 'business_address', '')),
    business_phone       = btrim(coalesce(p ->> 'business_phone', '')),
    business_email       = v_email,
    business_gstin       = v_gstin,
    receipt_footer       = btrim(coalesce(p ->> 'receipt_footer', '')),
    android_download_url = case when p ? 'android_download_url' then v_android else android_download_url end,
    windows_download_url = case when p ? 'windows_download_url' then v_windows else windows_download_url end,
    updated_at           = now(),
    updated_by           = auth.uid()
  where id = 1
  returning * into v_new;

  perform public.admin_log(null, 'settings.updated', 'platform_settings', '1',
    jsonb_build_object(
      'before', to_jsonb(v_old) - 'confirmed_checks' - 'updated_at' - 'updated_by',
      'after',  to_jsonb(v_new) - 'confirmed_checks' - 'updated_at' - 'updated_by'));
end $$;

-- activating a shop (as 0037)
create or replace function public.guard_business_columns()
returns trigger language plpgsql as $$
begin
  if public.is_direct_api_write() and not public.is_admin() then
    if new.id is distinct from old.id or new.is_active is distinct from old.is_active then
      raise exception 'Only the Dukania admin can activate or deactivate a business'
        using errcode = '42501';
    end if;
  end if;
  return new;
end $$;

-- reconciliation, admin only (as 0050)
create or replace function public.run_reconciliation(p_business uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_run   uuid;
  v_b     record;
  v_count integer := 0;
  v_total integer;
  v_open  integer;
begin
  -- Nightly job (no user) or a Dukania admin from the panel.
  if auth.uid() is not null and not public.is_admin() then
    raise exception 'Only the Dukania admin can run the reconciliation' using errcode = '42501';
  end if;

  insert into public.reconciliation_runs default values returning id into v_run;
  for v_b in select id from public.businesses
             where is_active and (p_business is null or id = p_business) loop
    v_count := v_count + 1;
    insert into public.reconciliation_issues
      (run_id, business_id, check_name, entity_id, entity_label, expected, actual, detail,
       explained_note, explained_by)
    select v_run, v_b.id, r.check_name, r.entity_id, r.entity_label, r.expected, r.actual, r.detail,
           coalesce(prev.explained_note, ''), prev.explained_by
    from public.reconcile_business(v_b.id) r
    -- Keep an earlier explanation while the difference is unchanged.
    left join lateral (
      select x.explained_note, x.explained_by from public.reconciliation_issues x
      where x.business_id = v_b.id and x.check_name = r.check_name
        and x.entity_id is not distinct from r.entity_id and x.explained_note <> ''
        and x.expected = round(r.expected, 3) and x.actual = round(r.actual, 3)
      order by x.created_at desc limit 1) prev on true;
  end loop;

  select count(*), count(*) filter (where explained_note = '')
    into v_total, v_open from public.reconciliation_issues where run_id = v_run;
  update public.reconciliation_runs
     set finished_at = now(), businesses = v_count, issues = v_total, unexplained = v_open
   where id = v_run;
  return jsonb_build_object('run_id', v_run, 'businesses', v_count, 'issues', v_total,
                            'unexplained', v_open);
end $$;

-- reconciliation, admin only (as 0050)
create or replace function public.explain_reconciliation_issue(p_issue uuid, p_note text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_run uuid;
begin
  if not public.is_admin() then
    raise exception 'Only the Dukania admin can explain reconciliation issues' using errcode = '42501';
  end if;
  if btrim(coalesce(p_note, '')) = '' then raise exception 'Write what explains it'; end if;
  update public.reconciliation_issues set explained_note = btrim(p_note), explained_by = auth.uid()
    where id = p_issue returning run_id into v_run;
  if v_run is null then raise exception 'Issue not found'; end if;
  update public.reconciliation_runs
     set unexplained = (select count(*) from public.reconciliation_issues
                        where run_id = v_run and explained_note = '')
   where id = v_run;
end $$;

-- the admin's today list, comment only (as 0054)
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
    -- Support tickets waiting for Dukania: the shop wrote last (0054).
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
-- The website is Dukania's own (dukania.in): the product page is the
-- home page and the agency pages are gone, so their copy goes too.
-- ============================================================
insert into public.website_seo (path, title, description, keywords) values
  ('/', 'Dukania — billing, stock & GST software for Indian shops',
   'Dukania runs billing, stock, GST and khata for Indian shops — on Android phones and Windows PCs, online or completely offline. Free trial.',
   array['gst billing app', 'billing software for shops', 'offline billing', 'inventory app india', 'pos app'])
on conflict (path) do update set title = excluded.title, description = excluded.description,
  keywords = excluded.keywords;
-- The home page's share texts follow its title and description again.
update public.website_seo set og_title = '', og_description = '', twitter_title = '',
  twitter_description = '' where path = '/';
update public.website_seo set
  title = 'Contact — Dukania',
  description = 'Talk to Dukania. Book a free demo, or ask anything about billing, stock and GST for your shop.',
  keywords = array['dukania demo', 'billing software demo', 'gst billing help']
where path = '/contact' and (title ilike '%softraxa%' or description ilike '%softraxa%');
delete from public.website_seo
  where path in ('/about', '/dukania', '/services', '/products', '/services/custom-solutions');
delete from public.website_content where page in ('home', 'about', 'services', 'products');

-- Anything left (FAQ answers, the contact page, share texts, keywords)
-- names Dukania, in any spelling, and its email is on dukania.in.
create or replace function pg_temp.dukania(p text) returns text language sql immutable as $f$
  select regexp_replace(regexp_replace(regexp_replace(p,
    'softraxa product', 'Billing & stock software', 'gi'),
    'softraxa\.(com|in)', 'dukania.in', 'gi'),
    'softraxa(?!@)', 'Dukania', 'gi');
$f$;
update public.website_content set value = pg_temp.dukania(value::text)::jsonb
  where value::text ilike '%softraxa%';
update public.website_seo set
  title = pg_temp.dukania(title),
  description = pg_temp.dukania(description),
  keywords = pg_temp.dukania(keywords::text)::text[],
  og_title = pg_temp.dukania(og_title),
  og_description = pg_temp.dukania(og_description),
  twitter_title = pg_temp.dukania(twitter_title),
  twitter_description = pg_temp.dukania(twitter_description),
  structured_data = pg_temp.dukania(structured_data::text)::jsonb
  where (title || description || keywords::text || og_title || og_description || twitter_title
         || twitter_description || structured_data::text) ilike '%softraxa%';
