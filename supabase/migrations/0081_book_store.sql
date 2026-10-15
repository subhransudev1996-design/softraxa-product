-- ============================================================
-- 0081_book_store.sql
--
-- New shop category: book store (school books, novels, exam guides).
-- Category defaults: none beyond the general ones — books sell by the
-- piece and there are no repair jobs, so apply_category_defaults()
-- (0047) already does the right thing through its "else" branches.
--
-- Run AFTER 0080. The new value can only be used after this migration
-- is committed, so run its test (tests/book_store.sql) as a separate
-- step.
-- ============================================================

alter type public.business_type add value if not exists 'book_store';
