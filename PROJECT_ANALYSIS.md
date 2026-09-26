**Dukania / SOFTRAXA project review — 21 September 2026**

**Fix status — 26 September 2026 (release R0)**

All 20 findings have code fixes in the working tree. The database fixes are in migrations 0037–0039 and **have not yet been run against any database**. They must be applied to a staging copy and verified with `supabase/tests/r0_security_and_integrity.sql` before production. The owner must also rotate the ImageKit key and make the repository private.

| # | Fix | Where |
|---|---|---|
| 1 | Role and business can't be self-edited; update policy has a check | 0037 §B |
| 2 | Every reference is checked against the row's business; stock trigger scoped by business | 0037 §D, §E |
| 3 | Plan RPCs require a platform admin or the service role | 0037 §J |
| 4 | Permissions enforced in RLS and document triggers (incl. inside RPCs); 4 new permissions; price and discount checks; app screens and routes match | 0037 §A, §F, §G; app |
| 5 | One local database per signed-in user; queued bills only sync under their creator | app `local_db.dart`, `offline_service.dart` |
| 6 | Offline start-up from the last saved context (72 h); full paged catalogue cache | app `supabase_providers.dart`, `offline_service.dart` |
| 7 | Recovery links now show a set-new-password form | website `auth/callback` |
| 8 | Return quantities aggregated per product under a lock on the original document | 0038 §B, §C |
| 9 | Returns credit the original bill first; bills with returns can't be edited or cancelled | 0038 §A, §D |
| 10 | Provisioning and suspension are single transactions; failures clean up | 0039; admin API |
| 11 | No passwords chosen, emailed or logged; set-password invitation; honest email result; HTML escaped | admin `email.ts`, `invite.ts` |
| 12 | Push function requires a secret, POST only, one run per day | `push-alerts`; 0039 |
| 13 | Owners can list their staff | 0037 §B |
| 14 | Empty plan limit = unlimited; no plan = owner only; limit checked under a lock; staff logins created correctly | 0037 §I |
| 15 | Sold serials can't be re-imported; sales require an available serial of the right product | 0037 §H |
| 16 | Expired or suspended shops are read-only in the database (payments still allowed) | 0037 §A, §F, §G |
| 17 | CMS saves publish immediately; hourly fallback | website `api/revalidate`, layout |
| 18 | Stock ledger append-only; stock totals derived only from it | 0037 §E, §F |
| 19 | Payments must match the bill's customer or supplier, be open, and not exceed its due | 0038 §E |
| 20 | CI workflow, secret scan, unique migration numbers, lint clean, contact-form abuse protection | `.github/workflows/ci.yml`, `scripts/check-repo.sh`, website |

Known limits, scheduled for R1:
- Staff without the cost/profit permission are blocked from reports and dashboard figures, but raw cost columns (for example `products.purchase_price`) can still be read through the API. Hiding them needs a separate cost table.
- ~~Unrefunded return credit beyond a bill's due is still kept as a negative customer balance until advances are modelled (PD22).~~ Resolved in migration 0041: it becomes a customer advance (also payment excess, paid-then-cancelled bills and bills edited below the amount paid).

Check results (26 Sep): Flutter analyze reports no issues; 87 Flutter tests pass; admin and website lint with 0 errors, type-check and production-build successfully.

The repository contains a substantial inventory and billing implementation, but the checked-in access controls and several transaction workflows are not ready for production use without correction. The highest priority is protecting tenant boundaries and privileged operations, followed by offline account isolation and accounting consistency.

This is a source review of the current working tree, including existing uncommitted additions. Findings describe the repository's behavior; the deployed database policies, grants, migration state, external service configuration, and production data were not audited. No application source or database records were changed. This report is not a claim that every screen, platform, or scenario has been tested.

**Architecture and implemented scope**

| Component | Implementation | Responsibilities |
|---|---|---|
| Shop application | Flutter, Riverpod, GoRouter, Supabase, Drift | Android/Windows app; POS, catalog, variants, serials, invoices, purchases, returns, customers, suppliers, expenses, stock, reports, job cards, printing, import, staff and subscription screens |
| Administration | Next.js 16.2.10, React 19, Supabase SSR | Client provisioning, plans, subscriptions/payments, support, audit, software products and lead management |
| Public website | Next.js 16.2.10, React 19, animation libraries | Marketing pages, lead capture, CMS/SEO editing and email-authentication callback |
| Backend | Supabase Auth/Postgres/Storage, SQL RPCs, Edge Function | Tenancy, transactional billing and stock ledger, reporting, subscription configuration and FCM alerts |
| Offline storage | Drift/SQLite | Cached products/customers and pending invoice payloads |

There are 37 migration files, numbered through 0035, with duplicate prefixes 0026 and 0027. The mobile app has 74 non-generated Dart source files. The README describes manual SQL-editor migration application; no automated migration smoke-test or CI workflow was found. Existing mobile tests cover arithmetic and parsing/reporting helpers, but do not establish database authorization or full transaction correctness.

Useful foundations include database-side transaction functions, a signed stock-movement ledger, a unique `(business_id, local_id)` invoice index for offline deduplication, separate service-role use in admin server routes, and functional production builds for both web applications. These are worth retaining while tightening the boundaries around them.

**Verification performed**

| Check | Result |
|---|---|
| Admin `npm run build` | Passed, including TypeScript and route generation |
| Website `npm run build` | Passed, including TypeScript and route generation |
| Admin `npm run lint` | Passed with one unused `businessId` warning in the send-email route |
| Website `npm run lint` | Failed: 32 errors and 25 warnings; issues include explicit `any`, `@ts-ignore`, and CMS component lint violations |
| Mobile `flutter test --no-pub` | Failed before tests executed: Flutter SDK `paragraph.dart` uses `.max` syntax requiring dot-shorthands, but the local package configuration identifies Flutter's language version as 3.8 |
| Mobile `flutter analyze --no-pub` | Exit 1: one unused-element warning and five informational issues (three async BuildContext uses, one const-constructor suggestion, one deprecated API); no analyzer errors |

The installed Dart executable reports 3.12.2; Flutter's source manifest requires at least 3.10, while the project's existing generated package configuration says 3.8 for Flutter. Restore a consistent SDK/dependency configuration and rerun the normal test command. This test-load failure is not evidence that the application's assertions failed. The review did not upgrade the SDK or rewrite dependency locks.

No authenticated UI walkthrough, physical printer/scanner test, Android/Windows release build, live email/push delivery, concurrency test against Postgres, or clean database migration replay was performed. Production builds can fetch public CMS data; no live mutation was intentionally invoked.

**Highest-priority findings**

1. **Critical — users can modify their own privilege and tenant assignment.**

   Evidence: [profile update policy](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/supabase/migrations/0010_rls.sql:11), [profile fields and authorization helpers](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/supabase/migrations/0001_core.sql:49).

   The self-update policy restricts the row by user ID but does not restrict `role` or `business_id`. No later migration adds a protective trigger or column restriction. Under the table update permissions this application expects, an ordinary user can promote their own profile to `admin` or change its business assignment. `is_admin()` and the admin HTTP routes then trust that profile. This undermines tenant isolation, admin API authorization, and CMS protection.

   Fix: make role and business assignment writable only through controlled administrative operations. Limit self-service updates to explicit safe fields. Regression-test role escalation, business reassignment, and normal profile editing with separate authenticated users.

2. **Critical — stock writes can target another business through unchecked foreign keys.**

   Evidence: [stock trigger](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/supabase/migrations/0007_stock_expenses.sql:24), [tenant write policy](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/supabase/migrations/0010_rls.sql:87), [invoice creation](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/supabase/migrations/0028_auto_round_off.sql:138).

   A stock movement's `business_id` is checked, but its product and variant references are not constrained to that business or to each other. The security-definer trigger updates products and variants by ID alone. A movement carrying the caller's business and another business's known product UUID can therefore change that other product's stock. Invoice payloads also accept those IDs without ownership validation.

   Fix: validate product/variant ownership and relationships in every RPC, add tenant-consistent composite foreign keys where appropriate, and include tenant conditions in the trigger. Restrict direct ledger mutation. Test with two tenants and deliberately mismatched references.

3. **High — plan-management RPCs have no server-side admin authorization.**

   Evidence: [apply_plan_features](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/supabase/migrations/0033_feature_enforcement.sql:48), [resync_plan_features and grants](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/supabase/migrations/0033_feature_enforcement.sql:83).

   Both functions run as security definer; neither checks `is_admin()` or restricts the supplied business. They are explicitly granted to authenticated users. An admin-only screen does not protect an independently callable RPC. Ordinary users can call these functions to change feature flags outside the intended admin workflow. Public/anonymous execute privileges also need explicit inspection and revocation where inappropriate.

   Fix: enforce admin authorization inside both functions and explicitly define execute grants for privileged helpers.

4. **High — staff permissions do not enforce the promised restrictions.**

   Evidence: [tenant policies](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/supabase/migrations/0010_rls.sql:75), [permission getters](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/apps/mobile/lib/core/supabase_providers.dart:48), [invoice RPC](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/supabase/migrations/0028_auto_round_off.sql:40), [router](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/apps/mobile/lib/core/router.dart:111).

   Tenant policies grant all same-business users broad CRUD access. Billing/reporting RPCs do not consult `staff_permissions`. Several getters, including `canCreateInvoice`, `canEditPrices`, `canManageProducts`, `canManageStock`, and `canViewReports`, have no consumers outside their declarations. Some screens hide profit/expense controls, but underlying data remains accessible. Granting `can_manage_staff` also exposes navigation while staff-management RPCs still require owner/admin.

   Fix: define an action-permission matrix, enforce it in RLS/RPCs, and then match navigation and buttons to those same rules. Sensitive purchase-cost/profit fields require data-level protection, not just hidden widgets.

5. **High — offline cache and pending bills are not scoped to an account or business.**

   Evidence: [local tables and shared database name](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/apps/mobile/lib/features/offline/local_db.dart:12), [queue replay](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/apps/mobile/lib/features/offline/offline_service.dart:155).

   Cached rows and pending bills have no tenant/account column; all sessions use `softraxa_local`. Replay checks only that some user is logged in and sends every queued payload using that user's session. After A logs out and B logs in on the same device, B can encounter A's cached data, and A's bills can be submitted under B's business. Unchecked product references compound the stock risk.

   Fix: tenant-scope storage and queue ownership; capture and verify that ownership before every replay. Switch/invalidate account-dependent providers on authentication changes. Preserve unsynced bills for their original account rather than deleting them on logout.

6. **High — a cold start without internet blocks the advertised offline workflow.**

   Evidence: [remote context load](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/apps/mobile/lib/core/supabase_providers.dart:106), [splash redirect on context error](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/apps/mobile/lib/core/router.dart:120), [POS cache population](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/apps/mobile/lib/features/pos/pos_providers.dart:44).

   The router requires `get_my_context` to succeed before allowing access to POS. With a saved login but no network after restart, the app stays at the error splash. The cache is also populated only from an unfiltered first-100 product query; searching for other products does not cache those results. Offline billing is therefore a limited fallback during an already initialized session, not complete offline operation. Job cards and general stock management use online calls too, contrary to the broader FAQ claim in `apps/website/src/lib/cms.ts`.

   Fix: persist an account-scoped last-known context with explicit offline access rules, implement complete/paginated cache preparation and stale-row handling, and test restarting in airplane mode with more than 100 products. Align website claims with implemented coverage.

7. **High — the supplied password-reset flow consumes the token without changing the password.**

   Evidence: [recovery email link](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/supabase/email-templates/reset-password.html:28), [callback verification](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/apps/website/src/app/auth/callback/callback-client.tsx:46).

   The template sends `type=recovery` to the website callback. That page verifies the token, displays “Email verified”, and tells the user to log in with their password. It never renders a new-password form or calls `updateUser`. The mobile recovery dialog listens for an event in the app, but the supplied link completes in a separate browser session. The magic-link template similarly ends at a verification page rather than a usable app sign-in.

   Fix: implement distinct confirmation, recovery, and magic-link completion paths. For recovery, retain the verified browser session long enough to securely set a password, or implement a tested app deep-link flow.

8. **High — return limits can still be exceeded.**

   Evidence: [sale return validation](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/supabase/migrations/0024_return_quantity_checks.sql:43), [purchase return validation](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/supabase/migrations/0024_return_quantity_checks.sql:150).

   Validation loops run before any return items are inserted. Two entries for the same product/variant in one payload are each compared against the same remaining quantity. For example, two entries of 1 both pass against a sold quantity of 1. Concurrent requests can also read the same remaining quantity because the original document is not locked before validation. Document-number serialization occurs only after the checks.

   Fix: aggregate submitted quantities by original line/serial, lock the original document before checking, and validate the combined quantities within the transaction. Test duplicate payload entries and two simultaneous returns.

9. **High — returns and cancellation can make balances and stock disagree.**

   Evidence: [return balance adjustment](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/supabase/migrations/0024_return_quantity_checks.sql:114), [invoice cancellation](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/supabase/migrations/0008_functions.sql:305), [FIFO payment allocation](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/supabase/migrations/0018_fifo_due_payments.sql:43).

   Returns reduce the customer's aggregate due but do not reduce the original invoice's generated due or record an applied credit. An unpaid invoice of 100 fully returned with no cash refund leaves customer due at 0 while invoice due stays 100. Subsequent allocation can collect against that stale invoice. Cancellation restores every originally sold unit without subtracting units already restored by returns, allowing double restocking; invoice editing likewise reverses original stock without reconciling prior returns. The supplier side has the analogous aggregate-versus-document credit issue.

   Fix: model return credits explicitly and derive/reconcile document and party balances from the same ledger. Prevent or correctly reconcile edits/cancellation after returns. Verify sale → partial return → payment → cancellation and equivalent purchase flows.

10. **High — client provisioning can report success after required database operations fail.**

    Evidence: [unchecked provisioning writes](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/apps/admin/src/app/api/clients/route.ts:65), [subscription insert](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/apps/admin/src/app/api/clients/route.ts:98), [partial rollback](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/apps/admin/src/app/api/clients/route.ts:138).

    Profile linkage, feature flags, master-data inserts, subscription creation, and plan-feature application do not inspect returned errors. A failed subscription insert can still result in a welcome email and successful HTTP response. The catch path deletes only the auth user and can leave a created business behind. Separately, the status-toggle route ignores the subscription-update result and returns the old subscription status when restoring a client.

    Fix: check every operation; use a transactional database provisioning RPC after creating the auth user, with reliable compensation and an idempotency key. Make business/subscription status changes atomic and return their actual resulting state.

11. **High — missing email configuration logs passwords and reports delivery success.**

    Evidence: [email fallback](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/apps/admin/src/lib/email.ts:126).

    When `RESEND_API_KEY` is absent, the fallback logs the client's plaintext password and returns `{success: true, provider: "simulated"}`. The create-client route consequently reports `emailSent: true` without delivery. The HTML also interpolates caller-supplied values without escaping.

    Fix: return an explicit not-configured/not-sent result, remove password logging, escape HTML values, and use an invitation or password-setting link instead of transmitting a reusable password.

12. **High, deployment-dependent — push-alert endpoint permits arbitrary invocation under its documented deployment command.**

    Evidence: [deployment instruction](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/supabase/functions/push-alerts/index.ts:8), [request handler](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/supabase/functions/push-alerts/index.ts:141).

    The file instructs deployment with `--no-verify-jwt`; the handler has no request authorization check and can send alerts to all registered devices. If deployed as documented, external callers can repeatedly trigger a notification broadcast and consume backend resources. The deployed gateway configuration was not inspected.

    Fix: authenticate the scheduler request with a verified credential, restrict the method, and add run deduplication/rate limits.

**Additional functional and operational findings**

13. **Staff listing is incompatible with profile RLS.** [The staff provider](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/apps/mobile/lib/features/staff/staff_screen.dart:20) queries every profile in the business, but [profile SELECT policy](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/supabase/migrations/0010_rls.sql:9) permits only the caller's row or a global admin. An ordinary shop owner therefore cannot list newly created staff for management. Add a narrowly scoped owner/authorized-manager staff-list policy or RPC without widening sensitive self-updates.

14. **Unlimited staff plans become one-user plans.** Both [staff creation](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/supabase/migrations/0034_staff_permissions.sql:80) and [context loading](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/supabase/migrations/0034_staff_permissions.sql:232) use `coalesce(pl.user_limit, 1)`, although migration 0032 defines NULL as unlimited. A subscribed owner on a NULL-limit plan is already at the resulting limit of 1 and cannot add staff. Distinguish no subscription, no selected plan, and unlimited plan explicitly; enforce counts under a suitable lock.

15. **Serial import can resurrect a sold IMEI.** [The conflict clause](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/supabase/migrations/0035_imei_serial_helpers.sql:27) resets an existing serial to `in_stock` and can reassign its product without clearing/reconciling its old invoice reference. The sale function also updates serial status without requiring an available serial belonging to the selected product. Reject duplicate imports or route them through explicit return/correction operations; atomically reserve available serials during sales.

16. **Subscription suspension and expiry are mainly client-side gates.** [Tenant policies](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/supabase/migrations/0010_rls.sql:87) and [invoice creation](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/supabase/migrations/0028_auto_round_off.sql:40) do not enforce active/unexpired access. A blocked account can continue calling permitted database operations directly, and the broad business self-update policy includes `is_active`. Define which reads remain allowed and enforce write restrictions centrally in the database.

17. **CMS changes lack a production publication/invalidation path.** The successful website build classified marketing pages as static. [Content loading](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/apps/website/src/lib/cms.ts:216) has no explicit revalidation/dynamic policy, and no cache-invalidation handler was found. CMS saves alone will not reliably update those pre-rendered pages without a rebuild. Choose a documented publication model and verify a CMS edit against a running production build.

18. **Direct mutation can invalidate the stock ledger.** The tenant-all policy permits updating/deleting stock movements, while [the stock trigger](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/supabase/migrations/0007_stock_expenses.sql:43) reacts only to inserts. Editing/deleting a movement changes the ledger without correcting the stored stock total; directly changing `products.current_stock` creates the opposite mismatch. Make the ledger append-only for application users and use compensating entries for corrections.

19. **Payment references are not fully validated.** [Explicit payment allocation](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/supabase/migrations/0018_fifo_due_payments.sql:36) checks an invoice's business but not whether it belongs to the supplied customer, is cancelled, or is an estimate. It also accepts amounts above the document due without an explicit credit-allocation model. The supplier path has the same missing party/document relationship check. Require matching party/document ownership and represent unapplied credit separately.

20. **Release and maintenance safeguards are incomplete.** Duplicate migration version prefixes complicate adopting tracked migrations; no clean-database replay or backend integration tests were found. The website CMS combines a large amount of editing UI, state, and data logic in one file, and repeated SQL function replacements make effective behavior harder to inspect. Generated database types, smaller feature modules, and a single explicit validation entry point would reduce drift. The public contact endpoint also has no application-level rate limit or bot protection; infrastructure protections were not inspected.

**Repair order and acceptance checks**

| Order | Work | Evidence required before moving on |
|---|---|---|
| 1 | Lock profile fields, privileged RPCs, cross-tenant foreign keys and stock mutations | Two-tenant authorization tests; no role escalation or cross-business writes |
| 2 | Enforce staff permissions and subscription rules in the backend | Owner/staff/admin permission matrix tested through direct API calls |
| 3 | Scope offline data and support authenticated offline startup | A→B account switch with queued bills; restart offline; full catalog cache; timeout/retry deduplication |
| 4 | Reconcile returns, credits, cancellation, editing and serial state | Stock and party/document balances agree across lifecycle and concurrent-request tests |
| 5 | Complete recovery, provisioning and notification delivery | Password-reset round trip; injected provisioning failures; truthful email outcome; unauthorized push invocation rejected |
| 6 | Restore reproducible verification and CMS publication | Passing normal Flutter tests/analyzer, clean web lint/builds, clean migration replay, tested CMS edit publication |

The Phase 2 plan explicitly defers purchase orders, delivery challans, cashbook, richer service history, estimate-to-job conversion, and advanced reports. Treat those as planned scope rather than silently considering them completed. Resolve the correctness and authorization findings before expanding those modules.
