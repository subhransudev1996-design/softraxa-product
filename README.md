# Dukania (by SOFTRAXA) — GST Billing & Stock Management

A mobile-first inventory, billing, and stock management system for local Indian shops (mobile, garment, hardware). See [prd.md](prd.md) for the original requirements, [LAUNCH_SPECIFICATION.md](LAUNCH_SPECIFICATION.md) for the launch specification and release plan, and [PROJECT_ANALYSIS.md](PROJECT_ANALYSIS.md) for the security review and its fix status.

## Structure

| Path | What it is |
|---|---|
| `apps/mobile` | Flutter shop app (owners and staff; Android + Windows) |
| `apps/admin` | Next.js admin panel (SOFTRAXA staff) |
| `apps/website` | Next.js marketing site, CMS and the password-setting page |
| `supabase/migrations` | Numbered SQL migrations — run in order |
| `supabase/tests` | SQL verification scripts — run on a staging copy |
| `supabase/functions` | Edge Functions (push alerts) |
| `scripts/check-repo.sh` | Repository checks used by CI (migration numbering, secret scan) |

## Getting started

1. **Database:** Supabase SQL Editor → run each file in `supabase/migrations/` in numeric order.
   - Migrations **0036–0039** harden security and accounting. Run them on a **staging copy** first, then run `supabase/tests/r0_security_and_integrity.sql` there: every check must print `PASS`. It rolls back its own test data.
   - Migration **0040** adds GST credit/debit notes and the GSTR-1 / GSTR-3B / purchase register reports. Test it on staging with `supabase/tests/r1_gst_returns.sql` the same way.
   - Migration **0041** adds customer advances and payment allocation. Test with `supabase/tests/r1_customer_advances.sql`. Apply it before running the matching app build (the app reads `advance_amount`).
   - Migration **0042** adds returned-goods condition (held stock), the return window and exchanges. Test with `supabase/tests/r1_returns_exchanges.sql`; apply before the matching app build.
   - Migration **0043** adds customer agreed prices, wholesale customers and staff discount limits (bills are checked in `create_invoice`/`update_invoice`). Test with `supabase/tests/r1_pricing.sql`; apply before the matching app build.
   - Migration **0044** adds the owner approval inbox (below cost, credit limit, overdue, over-limit discounts), due dates and overdue grace days. Test with `supabase/tests/r1_approvals.sql`; apply before the matching app build.
   - Migration **0045** adds the daily cashbook and day closing (cash drawer permission for staff). Test with `supabase/tests/r1_cashbook.sql`.
   - Migration **0046** adds repair estimates with versioned, staff-recorded customer approval, vehicle job fields and the private `job-attachments` Storage bucket for photos. Test with `supabase/tests/r1_repair_estimates.sql`; apply before the matching app build.
   - Migration **0047** adds the R1 shop categories and the setup wizard (GST, turnover band, UPI ID). Run it on its own first, then `supabase/tests/r1_categories_setup.sql` (new category values only exist once the migration is committed). Apply before the matching app build.
   - Migration **0048** starts a new invoice number series each financial year (`INV/26-27/0001`), adds composition shops (bill of supply) and requires HSN/SAC on bills to GST-registered customers. Run it on its own, then `supabase/tests/r1_gst_series.sql`.
   - Migration **0049** makes cut pieces part of the sale: best-fit suggestion with cutting allowance, leftover kept or scrapped by threshold, cutting loss as stock loss, optional cutting charge, returns only when allowed. Test with `supabase/tests/r1_cut_pieces.sql`; apply before the matching app build.
   - Migration **0050** adds the nightly reconciliation (admin panel → Reconciliation) and the owner's full data export. Enable **pg_cron** first (Dashboard → Integrations → Cron) so the migration can schedule the run for 02:00 IST. Test with `supabase/tests/r1_reconciliation.sql`.
   - After 0037: create a **new** ImageKit private key (the old one was published) and store it in Vault:
     `select vault.create_secret('<new private key>', 'imagekit_private_key');`
2. **Mobile app:**
   ```
   cd apps/mobile
   copy .env.example .env   # then paste your SUPABASE_URL and SUPABASE_ANON_KEY
   flutter pub get
   flutter run
   ```
3. **Admin panel:**
   ```
   cd apps/admin
   copy .env.example .env.local   # service-role key, WEBSITE_URL, RESEND_API_KEY
   npm install
   npm run dev
   ```
   New clients receive an email link to set their own password. Without `RESEND_API_KEY`, the panel says the email wasn't sent and shows the link to share instead.
4. **Push alerts (optional):** set the `FIREBASE_SERVICE_ACCOUNT` and `PUSH_ALERTS_SECRET` secrets, deploy `push-alerts`, and schedule a daily `POST` with `Authorization: Bearer <PUSH_ALERTS_SECRET>` (see the function's header comment).

## Checks

CI (`.github/workflows/ci.yml`) runs on every push to `master`: repository checks, Flutter analyze + tests, and lint + type-check + build for the admin panel and website. Run the same locally:

```
bash scripts/check-repo.sh
cd apps/mobile && flutter analyze && flutter test
cd apps/admin && npm run lint && npx tsc --noEmit && npm run build
cd apps/website && npm run lint && npx tsc --noEmit && npm run build
```
