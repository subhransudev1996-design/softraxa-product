-- ============================================================
-- 0062_pack_rate_precision.sql — a pack price that doesn't divide evenly
--
-- A pack line (0061) is stored as its pieces at the pack price per piece.
-- A tray of 30 eggs at ₹190 is ₹6.3333 an egg; unit_price kept 2 decimals,
-- so it was saved as ₹6.33 and the bill read "1 Tray × ₹189.90" with a
-- 10-paise round-off. Four decimals keep 30 × 6.3333 at ₹190.00.
--
-- Bills already saved are unchanged (their rates had 2 decimals anyway);
-- the app sends 4 decimals only on pack lines.
--
-- Run AFTER 0061.
-- ============================================================

-- The tax-split trigger (0040) lists unit_price, which blocks the type
-- change: drop it, widen the column, recreate it exactly as before.
drop trigger if exists trg_invoice_items_tax_split on public.invoice_items;

alter table public.invoice_items
  alter column unit_price type numeric(14,4);

create trigger trg_invoice_items_tax_split
  before insert or update of tax_amount, quantity, unit_price, discount_amount on public.invoice_items
  for each row execute function public.split_invoice_item_tax();
