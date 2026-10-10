-- ============================================================
-- 0076: Bill settings — what the shop prints on its bills.
--
--   bill_terms     its terms & conditions, one per line, numbered on the bill
--                  ("Exchange within 7 days with packing")
--   bill_footer    the closing line ("Thank you! Visit again.")
--   bill_show_sku  print each item's stock no. (SKU) on the bill
--
-- The owner changes them in Business settings, like the rest of the
-- profile (policy "own business update"). The app shows these settings
-- only once the columns exist, so older databases keep working.
-- ============================================================

alter table public.businesses
  add column if not exists bill_terms text not null default '',
  add column if not exists bill_footer text not null default 'Thank you! Visit again.',
  add column if not exists bill_show_sku boolean not null default false;

alter table public.businesses drop constraint if exists businesses_bill_text_check;
alter table public.businesses add constraint businesses_bill_text_check
  check (char_length(bill_terms) <= 1500 and char_length(bill_footer) <= 200);
