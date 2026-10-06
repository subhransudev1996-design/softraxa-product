# Dukania 1.0.5 — implementation plan

Goal: make daily counter work faster and help shops collect credit, without
changing anything that already works. Builds on 1.0.4 (committed, not yet
released).

## Rules for every step

- One item at a time; `flutter analyze` clean and the whole `flutter test`
  suite green before moving on; commit per item.
- New behaviour gets its own unit/widget test.
- App-only where possible. No new database change unless an item can't be
  done without one (none planned).
- Nothing changes for screens the item doesn't touch. Existing labels,
  shortcuts (F2/F4/F12, Esc) and flows keep working.
- Checked by hand in the Windows app on the demo shop at the end of each
  phase; test data is cleaned up afterwards.

## Status

A ✅ B1 ✅ B2 ✅ C1 ✅ C2 ✅ D1 ✅ — all committed with tests; on-screen check of
B1/B2/C1/D1 pending (needs the PC free).

## Phase A — fixes found while testing (small, low risk)

| # | Fix | Where | How |
|---|-----|-------|-----|
| A1 | Profit in checkout took GST off Non-GST / cash memo / estimate bills (showed −₹10 on a +₹28 sale) | `pos/checkout_sheet.dart`, `pos/cart.dart` | Keep `cart.applyGst` in step with the chosen bill type (it was never set). Test: Non-GST profit has no GST taken off. |
| A2 | Error messages hidden behind open dialogs / sheets | `core/widgets.dart` (`showError`, `showSuccess`) | When the caller is inside a dialog or bottom sheet, show the message on the top overlay instead of the page's snackbar. Widget test. |
| A3 | Cancelling a walk-in bill said the money is "kept as the customer's advance" | `invoices/invoice_detail_screen.dart` | Walk-in: "Give back ₹X to the customer"; customer bill: keep today's text with their name. |
| A4 | Cloud icon on bills made offline had no explanation | `invoices/invoices_screen.dart` | Tooltip "Made offline — synced". |
| A5 | Cart shows "0.1 kg" after selling 100 g | `pos/pos_desktop.dart`, `pos/pos_screen.dart` | Cart qty box reads "100 g" / "250 ml" under 1 kg / 1 L. Bills and PDFs unchanged (their rate is per kg). |

## Phase B — collect credit (udhaar)

**B1. WhatsApp payment reminder**
- Button "Remind on WhatsApp" on the customer page (when they owe) and a
  chat icon on each customer card that has a due (the Customer due report
  is a shared text table for all reports, so it stays as it is).
- Message (editable before sending, shop language later):
  "Namaste {name} ji, aapka {shop} mein ₹{due} baaki hai. Kripya jaldi
  bhugtan karein. UPI: {upi_id}. — {shop}, {phone}"
- Opens WhatsApp to the customer's number (same launcher as Reorder); no
  phone → the share sheet. Nothing is sent without the owner pressing send.
- Pure message builder in its own file + unit tests.

**B2. Customer statement (khata) PDF**
- "Statement (PDF)" button on the customer page: shop header, customer,
  period (This month / Last 3 months / This year / All), bills in the
  period (amount, paid, due now), payments, returns, every unpaid bill,
  total due less advance = amount payable, and the UPI ID.
- No running balance: rebuilding one from history drifts with cancelled
  bills, advances and edits. Every figure shown is one the app stores, so
  the statement always matches the customer page.
- Share PDF / Print, same as the reorder PDF.
- Uses the ledger the customer page already loads (no new query shape).
- Unit tests for the period, unpaid bills and earlier balance.

## Phase C — faster billing

**C1. Hold bill**
- "Hold" button on New Bill (and F8). Saves the whole cart (lines, customer,
  discount) and clears the counter for the next customer.
- "Held bills (n)" chip shows the list (customer/first item, items, total,
  time); tap to resume. Resuming while the counter has items asks to hold
  those first.
- Kept on this device while the app is open (closing the app drops held
  bills — a held cart is short-lived). Not used while editing a bill or
  in an exchange.
- Tests: hold → clear → resume gives the same cart; nothing on the counter
  is lost when resuming.

**C2. Quick items**
- A row of the shop's best sellers (last 30 days, up to 12) on New Bill while
  the search box is empty. One tap adds, exactly like picking it from search
  (loose / pack / serial / cut-length prompts still appear).
- Counted per bill line over the last 30 days (most often billed, not
  highest revenue), readable by every staff member; hidden when offline.

## Phase D — end of day

**D1. Today's summary**
- From the dashboard: bills count, sales total, received by Cash / UPI /
  Card, credit given today, old dues collected, returns refunded, expenses,
  and (owner only) profit. Pick another date with ← →.
- "Share on WhatsApp" (text) for the owner when staff close the shop.
- Complements the Cash book closing (cash counting), doesn't replace it.

## Later (not in this round)

- Hindi language (whole app — its own release).
- Barcode label printing.
- Stock count (physical stock check) screen.
- Repeat last bill for regular customers.

## Release

After all phases: full test suite, Windows check of each item, then the
phone check, then 1.0.5 with "build and push" from the owner.
