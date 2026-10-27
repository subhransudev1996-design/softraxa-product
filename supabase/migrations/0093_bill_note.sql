-- ============================================================
-- 0093: A longer note at the bottom of the bill.
--
-- bill_footer was one closing line ("Thank you! Visit again.", up to 200
-- characters). Shops want more there: business hours, the closed day,
-- the return / exchange policy. It is now a note of several lines, up to
-- 1000 characters, printed line by line in the middle; a line written
-- between *stars* prints in bold (the app does the printing).
-- ============================================================

alter table public.businesses drop constraint if exists businesses_bill_text_check;
alter table public.businesses add constraint businesses_bill_text_check
  check (char_length(bill_terms) <= 1500 and char_length(bill_footer) <= 1000);
