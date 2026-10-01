-- ============================================================
-- 0059_website_public_info.sql — the website reads its facts from Settings
--
--   * public_site_info(): what the public website may show — SOFTRAXA's
--     contact details, the app download links, Dukania's starting price
--     and trial length. Callable without logging in; it returns nothing
--     else from Settings (never the UPI ID, GSTIN or internal fields).
--     The website used placeholder contact details and had no download
--     links or prices; now changing them in the admin panel updates the
--     website.
--   * Two download links in Settings (Android, Windows), saved through
--     admin_save_settings like the other settings. A save that doesn't
--     mention them leaves them as they are.
--   * The Dukania page's FAQ in the website CMS: answers for the trial,
--     price, installing, printing, data export and Windows.
--
-- Run AFTER 0058.
-- ============================================================

-- ============================================================
-- A. Download links
-- ============================================================
alter table public.platform_settings add column if not exists android_download_url text not null default '';
alter table public.platform_settings add column if not exists windows_download_url text not null default '';

-- 0056's save, plus the two links (https only; omitted keys keep their value).
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
    raise exception 'That doesn''t look like a UPI ID — it should be like softraxa@okaxis';
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
    payment_payee_name   = coalesce(nullif(btrim(p ->> 'payment_payee_name'), ''), 'SOFTRAXA'),
    support_whatsapp     = v_wa,
    business_name        = coalesce(nullif(btrim(p ->> 'business_name'), ''), 'SOFTRAXA'),
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

-- ============================================================
-- B. What the public website may show
-- ============================================================
create or replace function public.public_site_info()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'whatsapp', s.support_whatsapp,
    'phone',    s.business_phone,
    'email',    s.business_email,
    'address',  s.business_address,
    'android_download_url', s.android_download_url,
    'windows_download_url', s.windows_download_url,
    -- Dukania's cheapest paid plan that shops can ask for.
    'from_yearly', (select min(p.yearly_price) from public.plans p
                    join public.software_products sp on sp.id = p.software_id
                    where sp.slug = 'dukania' and p.is_active and not p.is_trial
                      and not coalesce(p.is_custom, false) and p.yearly_price > 0),
    'from_monthly', (select min(p.monthly_price) from public.plans p
                     join public.software_products sp on sp.id = p.software_id
                     where sp.slug = 'dukania' and p.is_active and not p.is_trial
                       and not coalesce(p.is_custom, false) and p.monthly_price > 0),
    'trial_days', (select trial_days from public.software_products where slug = 'dukania'))
  from public.platform_settings s where s.id = 1
$$;

revoke execute on function public.public_site_info() from public;
grant execute on function public.public_site_info() to anon, authenticated;

-- ============================================================
-- C. The Dukania page FAQ (website CMS)
-- ============================================================
update public.website_content set value = $json$[
  {"q": "Is there a free trial?", "a": "Yes. Sign up in the app and your shop starts on a free trial straight away — no card, no payment. Every feature is open during the trial, so you can bill real customers before you decide."},
  {"q": "How much does Dukania cost?", "a": "Plans are priced per shop per year, for real shop margins — see the starting price above. You pay by UPI, cash or bank transfer; there are no hidden charges and no per-bill fees. Message us on WhatsApp for the plan that fits your shop."},
  {"q": "Does it really work with no internet?", "a": "Yes. Billing works fully offline — bills are saved on the device and sync automatically once the connection is back, with no manual step."},
  {"q": "How do I install it?", "a": "Download the Android app or the Windows installer from the Download page, sign up with your email, and the setup wizard asks for your shop's details. Most shops are billing within 10 minutes."},
  {"q": "Can I print bills?", "a": "Yes — on 58 mm / 80 mm Bluetooth thermal printers from the phone, and on any printer (thermal or A4) from Windows. Bills can also be shared as a PDF on WhatsApp."},
  {"q": "Can my staff have their own logins?", "a": "Yes. Each staff member gets their own login with only the permissions you choose — for example billing but not prices, or no access to profit. Selling below cost, a discount over their limit, or credit beyond a customer's limit waits for your approval."},
  {"q": "Does it handle GST?", "a": "Yes — GST bills with HSN codes, CGST/SGST/IGST, plus GSTR-1 and GSTR-3B reports and an export your accountant can use. Non-GST bills, cash memos and estimates are there too."},
  {"q": "Is my shop's data safe, and can I take it out?", "a": "Each shop's data is kept separate at the database level, so no other shop can ever see it. You can export your products, customers and bills to Excel at any time — your data stays yours."}
]$json$::jsonb
where page = 'dukania' and section = 'faqs' and key = 'items';

-- ============================================================
-- D. Home page headline (website CMS): a short two-line headline about
--    shops, leading to Dukania (the old one wrapped onto three lines).
-- ============================================================
update public.website_content set value = $json${
  "badge": "Made in India · for Indian shops",
  "title": "Software that runs\nyour shop, online or off.",
  "description": "Softraxa makes Dukania — billing, stock and GST software that keeps working when the internet doesn't. On the phone you already have and the counter PC.",
  "primary_cta": "Explore Dukania",
  "secondary_cta": "Book a free demo"
}$json$::jsonb
where page = 'home' and section = 'hero' and key = 'content';
