**Dukania — product and launch specification**

Working draft, started 21 September 2026; completed for review 25 September 2026. This document records agreed product decisions and separates them from proposed rules. Every area now has either a confirmed decision or a proposed default, so the specification is complete enough to review, but it is not a launch approval. Inclusion in a release does not mean that the current implementation is complete or verified.

How to read the labels:

| Label | Meaning |
|---|---|
| **Confirmed (Dxx)** | Agreed with the owner; change only by recording a new decision. |
| **Proposed default (PDxx)** | Recommended rule, filling a detail left open. It stands unless the owner changes it during review. |
| **Owner to set** | A business value only the owner can supply, such as a price or a date. |
| **Release R0–R3** | When the requirement ships; see *Release plan*. |

**Purpose**

Define the product, supported business workflows, implementation requirements, acceptance criteria, and operational readiness needed to launch Dukania. The source review is recorded in [PROJECT_ANALYSIS.md](/C:/Projects/SOFTRAXA/INVENTORY-SOFTWARE/PROJECT_ANALYSIS.md). Existing implementation must be checked against this specification rather than treated as proof of readiness.

**Confirmed decisions**

| ID | Decision |
|---|---|
| D01 | Launch serves multiple business categories, rather than only mobile shops. |
| D02 | Each business account initially manages one store at one physical location. Multi-location operation and transfers between branches/godowns are future scope. A standalone godown can be the business's single location. |
| D03 | Audience includes mobile shops, mobile repair shops, garment shops, hardware shops, godowns/warehouses, marble shops, rod/steel sellers, electrical shops, car workshops, bike garages, and wholesalers. “Marble”, “rods”, and “electrical” are the working interpretations of the user's original terms. |
| D04 | Cut-quantity sales and remaining-piece tracking are core requirements, including rods and wire. |
| D05 | Purchase and sale units may differ for the same product, using product-appropriate conversions. Examples include coils to metres, drums to litres, dozens to pieces, and weight/length or slab/area where supported by product dimensions and measurements. |
| D06 | Vehicle repair/service businesses are in scope alongside device repair businesses. Their job-card workflows need business-specific fields. |
| D07 | Wholesale is an explicit launch audience, not merely a separate price field. |
| D08 | Wholesale sales orders can be booked before delivery, delivered later, and fulfilled across multiple partial deliveries. Immediate collection must remain possible. |
| D09 | Confirmed sales orders reserve their stock by default. Reservations can be modified manually. Confirmed 22 September 2026; permissions follow D11, while detailed exception rules remain to be defined. |
| D10 | Each partial delivery creates its own invoice by default, with manual modification available. In the context of the discussion, this includes choosing a combined invoice for multiple deliveries. Confirmed 22 September 2026; permissions follow D11, while grouping limits and issued-document correction rules remain to be defined. |
| D11 | Owners have access to reservation and delivery-invoicing overrides within their own business. Owners can grant selected staff each override permission separately. Granting one does not grant the other. Confirmed 22 September 2026. |
| D12 | Accept sales orders exceeding available stock. By default reserve the available quantity and mark the remaining quantity as awaiting stock for later delivery after replenishment. Example: order 100, reserve 60 available, mark 40 awaiting stock. Confirmed 22 September 2026; replenishment allocation follows D13. |
| D13 | Newly received eligible stock is automatically reserved for awaiting-stock orders, oldest confirmed orders first by default. Owners and staff with reservation permission can change allocation priority manually. Confirmed 22 September 2026. |
| D14 | Launch includes all four pricing models: retail prices; wholesale prices with quantity-based discounts; customer-specific agreed prices; and negotiated prices or discounts controlled by staff permissions. Confirmed 22 September 2026. Precedence follows D15 and extra discounts follow D16; detailed calculation rules remain open. |
| D15 | Default price precedence, highest first: authorized negotiated price → customer-specific agreed price → applicable wholesale/quantity-tier price → retail price. Users can manually choose another applicable price subject to price-override permissions. Do not automatically choose the lowest eligible price. Confirmed 22 September 2026. |
| D16 | Do not automatically apply an extra discount on top of the selected price. Owners and staff with discount permission can apply an extra discount manually. The owner sets staff discount limits. Confirmed 22 September 2026; limit units and calculation basis remain open. Below-cost handling follows D17. |
| D17 | A sale below purchase cost displays a warning and requires explicit owner approval before proceeding. Staff price/discount permissions alone do not authorize a below-cost sale. Recorded 23 September 2026 from the user's confirmation. Cost basis remains open; the approval flow follows D18. |
| D18 | For a staff-initiated below-cost sale, staff submit an approval request and the owner reviews and approves or rejects it in their own signed-in phone or desktop app. The sale remains pending until approved; rejection allows staff to revise it. Confirmed 23 September 2026. This records launch requirements, not implemented functionality. |
| D19 | If the owner is unavailable or the device is offline, save the below-cost sale as a pending draft and prevent completion until owner approval can be verified. Staff can serve other customers or revise the price within their permissions so a below-cost exception is no longer needed. Confirmed 23 September 2026. This does not define or disable ordinary offline billing. |
| D20 | For cut-piece sales, automatically suggest a suitable available source piece/roll with the smallest remainder, accounting for cutting waste and existing reservations. Staff can manually select another suitable available source. Example: for a 4-metre cut, suggest an eligible 5-metre piece over a 12-metre piece. Confirmed 23 September 2026; product-specific suitability remains to be defined; remnant classification follows D21. |
| D21 | Keep usable offcuts as individually tracked stock linked to their source piece. Owners configure minimum reusable dimensions per product. Suggest scrap for leftovers below those thresholds, allowing authorized correction with a recorded reason. Record cutting loss separately from retained remnants. Confirmed 23 September 2026; correction permissions and scrap resale remain open; cutting charges follow D22. |
| D22 | Default cut-piece billing charges for the quantity delivered, treats cutting waste as the shop's stock loss, and permits an optional owner-configured cutting/service charge. Include a manual option to charge for the full source piece when agreed with the customer. Confirmed 23 September 2026. Full-piece remnant ownership follows D23; charge calculation and override permissions remain to be defined. |
| D23 | When the customer pays for the full source piece, the usable leftover belongs to the customer. Record it as handed over or held for collection, excluding it from shop-owned available stock. The shop may take ownership only with recorded customer agreement. Confirmed 23 September 2026. Custody details and transfer valuation remain to be defined. |
| D24 | Allow customer credit sales with owner-configured credit limits and payment due dates. When a sale would exceed the customer's limit, show a warning and require explicit owner approval before proceeding. Confirmed 23 September 2026. Overdue balances follow D25; exposure calculation, approval mechanics and offline behavior remain to be specified. |
| D25 | If a customer has an overdue unpaid balance, additional credit requires a warning and explicit owner approval even when within the credit limit. Fully paid new sales may continue, subject to other sale controls. Payment for a new sale does not automatically settle old debt. Confirmed 24 September 2026. Grace periods and overdue-date calculation remain open. |
| D26 | Apply general customer payments to the oldest outstanding invoices first by default. Allow authorized manual selection of invoices. Retain excess as unapplied customer advance. Payments explicitly collected for a new sale remain allocated to that sale. Confirmed 24 September 2026; age definition, detailed permissions and later reallocation rules remain open. |
| D27 | For an accepted sale return, reduce the original invoice's unpaid balance first. For any remaining return credit, an authorized user chooses a refund or customer credit for future purchases. Prevent duplicate refunds or credits. Confirmed 24 September 2026; eligibility, valuation, permissions and tax adjustments remain to be specified. |
| D28 | Inspect accepted returned goods and classify them as sellable, damaged/awaiting inspection, or scrap. Only sellable goods re-enter available stock. Validate IMEI/serials for tracked goods and record actual returned dimensions for cut pieces. Confirmed 24 September 2026; inspection permissions and category-specific return eligibility remain open. |
| D29 | Support exchanges as a linked return and new sale. Apply eligible return credit toward the replacement, collect any additional amount, and refund or retain eligible excess when the replacement costs less. Preserve stock and payment history across both transactions. Confirmed 24 September 2026. Original-invoice due settlement under D27 precedes use of remaining credit for the replacement. |
| D30 | Launch includes supplier purchase orders with multiple partial receipts. Track ordered, received and outstanding quantities per line. Add stock only when goods are physically received; allocate eligible received stock to waiting customer orders under D13. Link supplier bills and payments without duplicating stock receipts. Confirmed 24 September 2026; supplier-bill grouping follows D31; inspection and receipt exceptions remain open. |
| D31 | Support one supplier bill per delivery/receipt or a combined bill for several receipts from the same supplier, matching the supplier's actual document. Link billed quantities to the relevant receipt lines and prevent duplicate billing of those quantities. Confirmed 24 September 2026. Advance bills, price variances and detailed matching rules remain open. |
| D32 | General supplier payments settle the oldest outstanding supplier bills first by default. Allow authorized manual bill selection and keep excess as an unapplied advance paid to that supplier. A payment explicitly designated for a bill or purchase order stays linked to that purpose. Confirmed 25 September 2026; age definition, detailed permissions and advance-application rules remain open. |
| D33 | Support purchase returns with separate physical dispatch and supplier financial settlement. Link original receipts/bills where available. After supplier acceptance, apply return credit to the original bill's unpaid balance first; retain any remainder as supplier credit or record a refund actually received. Keep pending/disputed claims visible without treating them as accepted credit. Confirmed 25 September 2026; replacement and unbilled-return rules remain open. |
| D34 | Launch includes a daily cashbook and closing workflow: track opening cash and actual cash inflows/outflows, compare expected closing cash with physically counted cash, and record differences with a reason for owner review. Keep UPI/card/bank movements separate from physical cash. Confirmed 25 September 2026; counters/shifts follow D35; closing permissions remain open. |
| D35 | Default to one shared cash drawer per store. Launch also supports optional separate billing counters and cashier shifts with individual opening cash, handovers and closings. All remain within the same store and physical location under D02. Confirmed 25 September 2026; assignment, handover confirmation and closing permissions remain to be specified. |
| D36 | Lock cash closings against ordinary staff edits upon submission. Only the owner may reopen a closing or authorize a correction, with a recorded reason and preserved original closing history. Confirmed 25 September 2026. Detailed correction execution, offline closing and effects on subsequent periods remain to be specified. |
| D37 | For mobile repairs and car/bike garage jobs, prepare a parts-and-labour estimate and record customer approval before repair work begins. Additional work or charges beyond the approved estimate require renewed customer approval. Confirmed 25 September 2026; approval evidence/channels, diagnostic fees and deposits remain open. |
| D38 | Repair approval evidence at launch: staff record in-person or phone approval with the customer's name, approved estimate version, time, staff member and notes, and may attach customer confirmation such as a WhatsApp screenshot or photo. Such records are labelled "staff-recorded", never "digitally verified". Automated WhatsApp or customer approval links are out of launch scope. Confirmed 25 September 2026. |
| D39 | Deliver in staged releases instead of one launch: R0 security and correctness hardening, R1 pilot launch, R2 wholesale and purchasing, R3 advanced operations. All confirmed decisions are kept; each is assigned to a release in the *Release plan*. Confirmed 25 September 2026; the assignment of individual items is a proposed default. |
| D40 | GST scope for launch: GST-compliant tax invoices and bills of supply, credit notes for sale returns, HSN summary, and GSTR-1/GSTR-3B export reports (Excel/CSV) for the shop's accountant. Direct e-invoice (IRN) and e-way bill integration are not in launch scope. Confirmed 25 September 2026. |

**Release plan — confirmed staging (D39), proposed assignment**

Where a confirmed decision or section below says "launch" or "launch scope", read it as the release assigned here. Where a section says a detail "remains open", the matching proposed default in *Proposed defaults for open details* applies unless the owner changes it. Each release has its own exit criteria (see *Release criteria*). Later releases do not start until the previous one meets its exit criteria in production. Target dates: owner to set.

| Release | Goal | Scope |
|---|---|---|
| **R0 — Hardening** (blocker for any real customer data) | Make the existing product safe and correct | Rotate the exposed ImageKit key, remove it from source and make the repository private. Close all 20 findings in PROJECT_ANALYSIS.md: profile privilege escalation, cross-tenant references, admin RPC authorization, append-only stock ledger, return quantity limits and balances, provisioning, email and push authorization. Enforce staff permissions and subscription status in the database. Isolate offline data per account and support offline cold start. Fix the password reset. Add CI, a clean migration replay and two-tenant security tests. |
| **R1 — Pilot launch** | Retail and repair shops can run daily billing, credit and cash on Dukania | Categories: mobile, mobile repair, garment, hardware, electrical, car and bike workshops (D01, D03, D06). GST invoicing, credit notes and GSTR exports (D40, *GST and tax*). Retail, single-tier wholesale and customer-specific pricing with precedence, discount limits and price-source snapshots (D14–D16). Owner approval inbox for below-cost sales, credit-limit exceptions and overdue exceptions (D17–D19, D24, D25). Customer payment allocation and advances (D26). Returns settlement, inspection and exchanges (D27–D29). Fixed unit conversions (D05, fixed factors only). Linear cut pieces: suggestion, cutting allowance, remnant thresholds and delivered-quantity billing (D04, D20, D21, D22 default mode). Daily cashbook with one shared drawer and locked closings (D34, D35 default, D36). Repair estimates with versioned approval and D38 evidence (D37, D38). Roles and permissions, subscriptions, offline billing, onboarding and support as specified below. |
| **R2 — Wholesale and purchasing** | Wholesalers and godowns can operate end-to-end | Sales orders, reservations, backorders, replenishment allocation, partial deliveries and delivery invoicing modes (D07–D13). Reservation and invoicing override permissions (D11). Multi-tier quantity pricing (D14 wholesale tiers). Purchase orders with partial receipts, receipt-linked and combined supplier bills, supplier payment allocation and advances, purchase-return claims (D30–D33). Full-piece cut billing and customer-owned remnants (D22 manual option, D23). Variable-measure units (actual weight or length per piece). Onboarding opens to wholesale and godown categories. |
| **R3 — Advanced operations** | Larger single-location stores and heavy-material trades | Multiple counters and cashier shifts with handovers (D35 optional mode). Two-dimensional slab and marble cutting (D20 slab rules). Scrap resale and valuation. E-invoice (IRN) and e-way bill integration (required before onboarding any business above the e-invoicing turnover threshold). Supplier bills before goods. Label printing. Multi-location remains future scope beyond R3 (D02). |

Pilot eligibility follows the release. A business needing an R2 capability, for example a wholesaler that books orders before delivery, is not onboarded until R2.

**Workflow direction — details to confirm**

These are proposed requirements for elaboration, not individually approved business rules. The details they leave open are covered by *Proposed defaults for open details*.

| Area | Proposed requirements |
|---|---|
| Business configuration | Retail, wholesale, service, or combined workflows; show relevant fields and modules for the selected business. |
| Units | One stock base unit per product; explicit purchase/sale conversions; precision and rounding rules; transaction snapshots of conversions. Variable piece dimensions or weight must not be represented as an inaccurate universal conversion. |
| Cutting | Identify the source roll/slab/rod, quantity consumed, usable remainder(s), and waste. Reconcile physical pieces with aggregate stock. Define pricing for cuts, waste, and cutting labour. |
| Pricing | All four pricing models are confirmed by D14; default precedence and manual selection follow D15; manual extra discounts and owner-set staff limits follow D16. Wholesale eligibility, quantity thresholds, discount calculation and detailed limit enforcement remain to be specified. |
| Wholesale orders | Order → optional advance → one or more deliveries → linked invoice(s) → balance collection → closure. Track ordered, delivered, cancelled, and outstanding quantity per line. |
| Delivery controls | Link each delivery to its source order; prevent accidental over-delivery and duplicate posting; document cancellation, returns, delivery acknowledgement, and correction behavior. |
| Credit | Customer credit sales, owner-set limits/due dates and owner approval for limit exceptions are confirmed by D24. Opening balances, advances, partial payments, return credits, statements, exposure calculation and supplier-side rules remain to be specified. |
| Repairs | Estimate approval and renewed approval for additional work/charges are confirmed by D37. Device/vehicle intake, inspection, technician assignment, parts, labour, advance, status, delivery, warranty and service-history details remain to be specified. Vehicle fields can include registration, make/model, odometer and optional chassis/VIN. |

**Sales-order reservation — confirmed default and proposed operating rules**

Confirmed: reserve stock when an order is confirmed, with manual modification available. A manual reservation change must be distinguished from changing the customer's ordered quantity or recording a physical stock adjustment.

Proposed operating rules for review:

- Display physical on-hand, reserved, and available-to-sell quantities separately, with available-to-sell calculated from sellable on-hand stock minus active reservations.
- Allow a permitted user to increase, reduce, or release an order-line reservation, within the outstanding order quantity and available stock. Reducing a reservation leaves the order outstanding; it does not cancel the customer's order.
- Record the actor, time, reason, and previous/new reserved quantities for manual changes. Owner access and separately assignable staff reservation-override permission are confirmed by D11; audit details are proposed.
- Reserve atomically so simultaneous confirmations cannot allocate the same stock twice. Do not count a reservation as a sale or physical stock movement.
- On delivery, reduce physical stock and consume the corresponding reservation exactly once. A partial delivery retains reservations for the remaining reserved quantity; cancellation releases the cancelled portion.
- If stock is insufficient, accept the order, reserve the available quantity by default, and explicitly show the shortfall as awaiting stock (D12). Replenishment automatically serves oldest confirmed orders first, with authorized manual priority changes (D13). Offline confirmation and any store-wide default setting remain open decisions.
- For serials and cut pieces, define whether a reservation identifies a particular physical item or only a quantity. Aggregate length alone must not imply that a suitable uncut length is available.

Proposed acceptance example: with 100 units on hand, confirming an order for 30 reserves 30 and leaves 70 available. Manually reducing its reservation to 20 leaves the order at 30 units and raises availability to 80. Delivering 10 reserved units leaves 90 on hand, 10 reserved, 80 available, and 20 still to deliver on the order, of which 10 are unreserved.

**Delivery invoicing — confirmed default and proposed operating rules**

Confirmed: each partial delivery creates its own invoice by default; the user can manually change this behavior, including choosing combined invoicing for multiple deliveries.

Proposed operating rules for review:

- Offer the invoicing choice before finalizing a delivery. Default to an invoice for that delivery's quantities only; allow an authorized user to select combined invoicing instead.
- In combined mode, retain a separate delivery record and show delivered-but-uninvoiced quantities until they are included in a combined invoice. Whether grouping is restricted to one order or can span multiple orders for the same customer remains open.
- Preserve line-level links between order, delivery and invoice. A delivered quantity may be invoiced only once, including when requests are retried or two users act concurrently.
- Physical stock decreases on delivery exactly once. Creating an invoice for a recorded delivery must not deduct stock again. Immediate counter sales must likewise record only one stock deduction.
- An order-level advance must be allocated explicitly across invoices; the same advance cannot be applied in full to every partial invoice. Unallocated advance remains separately visible. Default allocation order remains to be agreed.
- Switching modes does not silently merge, delete or overwrite issued invoices. Define a separate correction process that preserves original records, payments, return links and audit history.
- Record the actor, time and reason for manual overrides. Owner access and separately assignable staff invoicing-override permission are confirmed by D11. Audit details and whether a persistent store-level setting is available remain open.
- Validate invoice timing, delivery-document requirements and corrections against applicable tax rules before implementation sign-off. This product decision is not approval of every possible delayed-invoicing scenario.

Proposed acceptance examples: an order for 30 units delivered as 10 and 20 creates two invoices by default, for 10 and 20 respectively. If combined mode is selected before either delivery is invoiced, those two deliveries can feed one invoice for 30, subject to the agreed grouping and timing rules. In either case, total physical stock reduction is 30, not 60, and no delivery quantity or advance is counted twice.

**Manual-override permissions — confirmed access model**

Owners can modify reservations and delivery-invoicing mode for their own business. They can assign these capabilities individually to selected staff.

| Capability | Owner | Staff |
|---|---|---|
| Modify order reservations | Allowed within own business | Requires reservation-override permission |
| Change replenishment allocation priority | Allowed within own business | Uses the same reservation-override permission (D13) |
| Change delivery-invoicing mode | Allowed within own business | Requires invoicing-override permission |

Proposed implementation and acceptance requirements:

- Deny both staff overrides by default until explicitly granted. Assignment/revocation by other delegated roles remains undecided; neither override permission itself grants permission-management access.
- Enforce each permission in backend operations as well as the interface, always within the caller's business.
- Recheck permissions when committing an override; revoked permissions must not remain effective merely because a screen is already open. Offline override handling requires a separate decision.
- Log permission grants/revocations and override actions. Overrides cannot bypass tenant isolation, duplicate-billing protection or stock-accounting invariants.
- Test staff with neither permission, each permission individually, and both permissions. A reservation-only staff member must be rejected when attempting an invoicing override, including through a direct API call.

**Orders exceeding available stock — confirmed backorder support**

Confirmed: accept the full order even when available stock is insufficient. Reserve what is available by default and mark the shortage as awaiting stock. Fulfil the remainder later after replenishment; existing reservation overrides follow D09 and D11.

Proposed operating rules and acceptance checks:

- Calculate availability after other active reservations, rather than using total physical stock. For 80 units on hand with 20 already reserved, a new order of 100 reserves 60 and has 40 awaiting stock.
- Track ordered, cancelled, delivered, reserved and awaiting-stock quantities per line. Distinguish a shortage from a reservation manually released by an authorized user; an intentional release must not silently become an automatic allocation request.
- Never treat incoming purchase orders or an expected delivery date as physical stock already received. Receiving and allocating replenishment does not itself record a customer delivery or invoice.
- In the standard flow, prevent delivery of unavailable quantities and prevent consuming another order's reservation without an explicit authorized reallocation. Do not represent the backorder itself as negative physical stock.
- Example: start with 60 units on hand and an order for 100. Confirmation leaves 60 reserved, 40 awaiting stock, and 0 available. Delivering 60 leaves 0 on hand and 40 still awaiting stock; the default invoice covers only the 60 delivered. Receive another 40: if this is the oldest eligible waiting order and there is no manual priority override, automatically reserve those 40 for it. There are then 40 on hand and reserved, with 0 awaiting stock. Delivering those 40 completes the order and creates the second default invoice.
- Validate that partial replenishment, cancellation of the undelivered balance, repeated receipt processing, and concurrent orders do not duplicate reservations, delivery quantities or invoices.

**Allocation after replenishment — confirmed default and override**

Confirmed: automatically allocate newly received eligible stock to awaiting-stock quantities, serving the oldest confirmed orders first by default. Owners and staff with reservation permission can change priority manually.

Proposed implementation rules and acceptance checks:

- Use the original confirmation timestamp for default order age, with a stable tie-breaker for equal timestamps. Editing an order must not accidentally reset its priority; treatment of later quantity increases remains to be defined.
- Allocate only actually received, sellable, unreserved stock matching the order's product/variant and physical requirements. Skip cancelled or completed demand and quantities intentionally excluded from automatic reservation by a manual release.
- Process receipt and allocation with concurrency protection and retry deduplication so simultaneous receipts or sales cannot reserve the same stock twice.
- Manual priority changes must show the affected orders and quantities and record actor, time and reason. Reprioritizing future receipts must not silently remove an existing reservation; moving already-reserved stock requires an explicit reservation change under D09/D11. Duration of a manual priority override remains to be defined.
- Example: older order A awaits 40 units and newer order B awaits 30 of the same product/variant. Receiving 50 reserves 40 for A and 10 for B, leaving B awaiting 20. If an authorized user prioritizes B before allocation, the same receipt reserves 30 for B and 20 for A, leaving A awaiting 20.
- Allocation alone neither dispatches goods nor generates an invoice. Delivery and invoicing remain separate actions governed by D08 and D10.

**Launch pricing models — confirmed scope**

All four models are required at launch:

| Model | Confirmed capability |
|---|---|
| Retail | Standard retail selling prices |
| Wholesale | Wholesale selling prices with quantity-based discounts |
| Customer-specific | Agreed prices for individual customers |
| Negotiated | Manual sale prices or discounts controlled by staff permissions |

Proposed operating rules and acceptance checks:

- Display the selected price source and selling unit on each line. Keep unit conversion and tax treatment explicit so rates can be compared on the same basis.
- Store the applied price, discount and source on the transaction rather than relying on a mutable catalog rate. Changes to future prices must not silently rewrite issued documents.
- Evaluate quantity thresholds consistently in a defined unit. Whether thresholds apply per line, per product across an order, or across customer purchases remains open; partial deliveries must not accidentally change an agreed order rate.
- Apply D15 to choose the price source. Do not silently stack wholesale discounts, customer rates, and negotiated discounts. Extra discounts require explicit manual application under D16.
- Enforce staff price/discount permissions in the backend and record overrides. Separate permissions for changing a sale price, applying a discount, maintaining price lists and viewing cost/profit are proposed; detailed roles and limits remain open.
- Test each model, tier boundaries, changed quantities, customer selection changes, unit conversion, partial delivery, returns, and unauthorized overrides.

**Pricing precedence — confirmed default and manual selection**

Confirmed priority, highest first: authorized negotiated price → customer-specific agreed price → applicable wholesale/quantity-tier price → retail price. Apply the first applicable source by default. An authorized user may manually select another applicable price; the system must not automatically substitute the lowest eligible price.

Proposed operating rules and acceptance checks:

- A negotiated price applies only when explicitly entered or selected with authorization; do not invent a negotiated rate automatically.
- Show applicable price options, the default source, the chosen source and any manual override on the sale line. Selecting a different source is subject to the same backend controls as editing its price.
- Record the default and chosen rate, selling unit, actor and reason for an override. A transaction-level choice does not modify the customer's agreement or product price list.
- Example: retail 100, applicable wholesale 90, and customer-agreed 95 results in a default price of 95. An authorized user can choose wholesale 90 or explicitly negotiate another price; an unauthorized staff member cannot override 95 through either the interface or a direct API call.
- Define how draft quantity/customer changes affect a manual choice before finalization; do not silently reset an override or retain an ineligible tier. Issued-document correction remains a separate process.

**Additional discounts — confirmed manual control and staff limits**

Confirmed: no automatic extra discount is added to the selected price. Owners and staff with discount permission may apply one manually. Staff must remain within limits configured by the owner.

Proposed operating rules and acceptance checks:

- Show the selected price, extra discount and resulting amount separately. An extra discount changes this transaction, not the product price list or customer agreement.
- Validate both discount permission and the owner's configured limit in the backend at finalization. Staff may not change their own limits or obtain discount permission merely by having reservation/invoicing permissions.
- Record who applied or changed a discount, its amount, the limit checked and the reason. Whether a reason is mandatory for every discount remains to be decided.
- Define limits as percentage, fixed amount, or both; specify the base, rounding, line/bill scope and how combined line and bill discounts consume the limit. Repeated smaller discounts must not bypass the intended cap.
- Decide whether a price override followed by a discount is measured against the selected price or an earlier reference price. This must be explicit so negotiated pricing cannot unintentionally bypass owner controls.
- Example, assuming a percentage cap on the selected price: for a 1,000 line amount and a staff cap of 5%, an explicit 50 discount is allowed, while 60 is rejected for that staff member. With no explicit discount, the amount remains 1,000. The sample cap is illustrative, not a default chosen for every store.
- Test unauthorized discounts, exact-limit and over-limit discounts, changed quantities, combined discounts, revoked permission and direct API requests. Rules for owner approval of an over-limit staff request remain open.

**Sales below cost — confirmed owner approval**

Confirmed: show a warning and require explicit owner approval before a below-purchase-cost sale proceeds. Ordinary staff price/discount permission does not bypass this requirement. An owner making the sale must also explicitly acknowledge the warning rather than receiving implicit approval merely from their role.

Proposed operating rules and acceptance checks:

- Compare the effective product-line price after all allocated discounts against its cost on a consistent unit and tax basis. Allocate bill-level discounts before the check so a bill discount cannot bypass approval. Cost method, tax treatment, allocation rounding, missing costs and service-line treatment remain open.
- Bind approval to the specific sale, affected lines, quantities, prices, discounts and cost snapshot. Material changes after approval require a fresh check and renewed approval where applicable.
- Enforce approval in the backend. Record owner identity, time, affected lines and approved values; a staff checkbox or client-supplied approval flag is insufficient evidence.
- Proposed audit field: reason for the below-cost sale, such as clearance or damaged stock. Whether that reason is mandatory remains to be agreed.
- Keep cost figures and margin details hidden from staff without cost/profit visibility permission; those staff can receive an owner-approval-required message instead.
- Approval does not waive other rules such as tenant isolation, stock availability or invoice integrity. Do not share the owner's account credentials with staff to approve a sale.
- Example on a consistent per-unit basis: cost 100 and effective selling price 90 triggers the warning and cannot finalize without owner approval. A price of exactly 100 does not trigger this below-cost rule. Reducing an approved price of 90 to 85 requires renewed approval under the proposed approval-binding rule.
- Test missing approval, approval by a non-owner, approval from another business, modified sale data, allocated bill discounts and an owner completing their own sale.

**Owner approval — confirmed launch workflow**

Confirmed: staff submit an approval request; the owner reviews and approves or rejects it from their own signed-in app on a phone or desktop. The sale remains pending until approved. If rejected, staff can revise the sale; any revised below-cost sale still requires approval under D17.

Proposed implementation details and acceptance checks:

- Show requests in an owner approval inbox with the customer, affected products, quantities, cost basis, effective selling prices, discounts and estimated loss. In-app visibility is required even if a push notification is delayed; notification channels remain to be specified.
- Track pending, approved, rejected, withdrawn, superseded and consumed requests. Staff can see status without gaining access to restricted cost/profit details.
- Store decisions server-side with the requesting user, approving owner, business, transaction revision and timestamps. Only the owner of that business can approve; staff cannot approve by changing a request field directly.
- Approval permits staff to finalize the reviewed sale; it does not itself dispatch stock, issue an invoice or collect payment. Recheck transaction revision, stock eligibility and other validations on finalization, and consume the approval atomically to prevent duplicate use.
- A revised below-cost sale requires a fresh request if the previous request was rejected or its approved values have materially changed. Withdrawal and supersession must prevent stale approvals from finalizing the sale.
- Verify approval and rejection from another signed-in device, unauthorized approval attempts, stale requests, repeated submissions, concurrent decisions and retry-safe finalization.
- Approval expiry, temporary stock holds while waiting, offline request submission/synchronization and any same-device owner authentication alternative remain open. Owner-unavailable and offline completion behavior follow D19.

**Owner unavailable or device offline — confirmed fallback**

Confirmed: preserve the sale as a pending draft and block below-cost finalization until owner approval can be verified. Staff can continue serving other customers or revise the sale within their price/discount permissions so it no longer requires a below-cost exception. Ordinary offline billing coverage remains a separate requirement.

Proposed implementation rules and acceptance checks:

- Persist the draft under its originating business and user context; recover it after restart without exposing it to a different account. A queued offline request must be labelled awaiting submission, not owner-approved.
- Do not create a finalized invoice, physical stock deduction or recorded payment merely by saving the draft. Existing order reservations remain subject to the reservation rules; additional draft stock holds are undecided.
- On reconnect, synchronize the current draft/request without duplicates and fetch the authoritative approval state. Connectivity restoration alone must not approve or automatically finalize the sale.
- Revalidate current prices, cost basis, permissions, approval revision and stock before finalization. A cached or client-edited approval flag cannot bypass D17–D19.
- If staff revise the price so the exception is no longer required, withdraw or supersede the old request and run normal sale checks. Do not let a later response to that stale request finalize a superseded draft.
- Test restart while pending, owner unavailable, request queued offline, reconnect retries, account switching, rejected approval and permitted price revision. Confirm that saving or synchronizing the draft never doubles stock movements or invoices.

**Cut-piece selection — confirmed suggestion and manual choice**

Confirmed: automatically suggest a suitable available source piece or roll that leaves the smallest remainder after the requested cut and cutting waste. Staff can choose another suitable available source manually. Existing reservations must be respected. This is a selection aid; it does not automatically execute a physical cut.

Proposed operating rules and acceptance checks:

- For linear stock, compare available matching pieces/rolls by remaining length after the requested cut plus the configured cutting allowance. Exact fits are eligible only if the required cutting allowance also fits. Require the matching product/variant and relevant specifications such as diameter, gauge or grade.
- For a 4-metre cut with zero cutting loss, prefer a suitable available 5-metre piece over a 12-metre piece, leaving 1 metre. If that product requires 0.01 metre cutting loss, the same cut leaves 0.99 metre. These loss values illustrate the calculation and are not universal product defaults.
- Display source-piece identity/location, starting dimensions, requested cut, expected waste and expected remainder before confirmation. Manual selection cannot consume another order's reserved stock without the separate reservation override defined in D11.
- Do not treat two short pieces as one continuous length. For example, two 3-metre pieces cannot fulfil a request for one continuous 4-metre piece. Multi-piece orders need explicit quantities and cut dimensions.
- Recheck source availability and reserve/consume it atomically at the appropriate workflow step. Simultaneous users must not allocate the same physical portion twice; the exact point of cutting relative to delivery remains open.
- Preserve lineage from source piece to sold cuts, retained remnants and scrap. Reconcile source quantity with delivered cuts, physical remainders and waste in the stock base unit; delivery must not deduct a cut quantity a second time if already accounted for by the chosen cutting workflow.
- Marble/slab suitability must consider length, width, thickness, orientation and the required cut layout, rather than area alone. Detailed two-dimensional selection rules remain open; a globally optimal cutting-layout solver is not implied by this decision.
- Test exact fits, cutting allowance, reserved sources, manual selection, incompatible dimensions, insufficient continuous length, concurrent selection and retry-safe posting.

**Reusable remnants and scrap — confirmed classification approach**

Confirmed: keep usable offcuts as individually tracked stock linked to their source piece. Owners set minimum reusable dimensions per product. Suggest scrap for smaller leftovers, with authorized correction and a recorded reason. Record cutting loss separately.

Proposed operating rules and acceptance checks:

- Create each retained offcut with its own identifier, measured dimensions, product/variant, source-piece link and stock status. It must be selectable for a later suitable cut without also leaving its consumed parent quantity available.
- Apply thresholds in the product's configured units: length for linear stock and appropriate dimensions for slabs. For multi-dimensional pieces, define which dimensions must meet the threshold; area alone must not establish usability.
- Treat the threshold as a classification suggestion, not an automatic irreversible disposal. Capture the confirmed classification, actor and reason for an override. Exact role permissions remain to be agreed.
- Keep reusable stock, recoverable scrap and irrecoverable cutting loss distinct. Scrap must not appear as ordinary available-to-sell product stock. Scrap disposal, resale and valuation workflows remain open.
- Preserve quantity reconciliation: source consumed equals customer cut(s), retained reusable remainder(s), recoverable scrap and irrecoverable cutting loss, all converted to a consistent stock basis. A reclassification moves quantity between states rather than adding new material or recording loss twice.
- Changing a product's threshold should affect future suggestions; it must not silently reclassify existing stock. Corrections involving reserved remnants must explicitly resolve affected reservations.
- Example: a 5-metre piece yields a 4-metre cut, 0.01 metre cutting loss and a 0.99-metre remnant. With a 1-metre minimum, suggest scrap for the remnant; an authorized user can retain it as reusable with a reason. With a 0.5-metre minimum, suggest reusable stock. The 0.01 metre loss remains separate in both cases. Sample thresholds are illustrative.
- Test above/below/exact threshold values, unit conversions, multiple remnants, authorized and unauthorized corrections, parent-child lineage, repeated posting and subsequent sale of a retained piece.

**Cutting charges and waste billing — confirmed default and manual option**

Confirmed: charge for the delivered quantity by default and record cutting waste as the shop's stock loss. Owners may configure an optional cutting/service charge. Allow manual full-source-piece billing when agreed with the customer.

Proposed operating rules and acceptance checks:

- Keep requested cut, delivered quantity, charged quantity/basis, cutting loss and remainder dimensions separately recorded. Selecting full-piece billing changes the billing basis, not the measured cutting outcome.
- Display the billing basis and optional cutting charge before confirmation and on the customer-facing document. Record customer agreement for full-piece billing; how agreement is captured remains open.
- Configure cutting charges explicitly, with flat/per-cut/per-unit methods still to be decided. Do not silently add waste quantity to a delivered-quantity bill or duplicate a cutting charge across partial invoices.
- Snapshot the applied billing basis, rate, charge and actor. Define a separate override permission rather than assuming reservation permission permits full-piece billing. Detailed authorization remains open.
- Preserve physical reconciliation under both billing modes. A retained shop-owned remnant remains tracked; a customer-owned remnant must not enter shop-owned available stock. Full-piece leftovers follow D23.
- Example before tax: at 100 per metre, a 4-metre delivery cut from a 5-metre source costs 400 by default, plus any explicitly configured cutting charge. If full-piece billing is selected with customer agreement, the material charge is 500 instead. Cutting loss and measured remainder remain recorded in either case. Prices and charge amounts here are illustrative.
- Test both billing modes, fractional quantities, cutting charges, multiple cuts, partial deliveries, customer agreement records, unauthorized overrides and quantity reconciliation. Applicable tax treatment and below-cost cost allocation still require definition.

**Full-piece leftovers — confirmed customer ownership**

Confirmed: when the customer pays for the full source piece, the usable leftover belongs to that customer. Record it as handed over or held for collection. Exclude it from shop-owned available stock. The shop may take ownership only with recorded customer agreement.

Proposed operating rules and acceptance checks:

- Link every customer-owned remnant to its customer, source piece, cutting record and original sale/invoice. Record dimensions, quantity, custody status and storage position when held at the store.
- Distinguish ownership from physical custody. Material held for a customer is visible in a customer-material register but cannot be automatically reserved or sold to another customer as shop stock.
- Record collection with quantity/dimensions handed over, recipient, time and staff actor. Support partial collection where appropriate without duplicating previously collected quantities. Evidence requirements remain to be specified.
- Collection of material already billed as part of the source piece must not create another material charge or deduct shop-owned stock again. Any separately requested new cutting service needs its own explicit charge, if applicable.
- A transfer to shop ownership requires a recorded agreement linked to the specific remnant and a distinct transfer event. Compensation, valuation, tax treatment and staff permission for such transfers remain open; do not assume every transfer is free.
- Do not automatically treat uncollected customer material as abandoned shop stock or scrap. Retention periods, reminders, disposal and any storage fees require separate rules.
- Example: a customer pays for a 5-metre source cut into a 4-metre delivered piece, 0.01 metre loss and 0.99 metre usable remainder. If the remainder stays at the shop, track 0.99 metre as customer-owned material awaiting collection and exclude it from shop availability. Later collection changes custody, not the original material charge.
- Test handover, storage, partial collection, repeated collection requests, another customer's attempted allocation, ownership transfer with/without agreement and source-quantity reconciliation. Physical quantities must never be counted simultaneously as shop-owned and customer-owned.

**Credit sales and credit limits — confirmed owner-controlled exceptions**

Confirmed: allow customer credit sales with owner-configured credit limits and payment due dates. A sale that would exceed the customer's limit displays a warning and requires explicit owner approval before proceeding.

Proposed operating rules and acceptance checks:

- Require an identified customer for credit exposure and retain a due date on each credit invoice. Default payment terms and who can change individual due dates remain to be agreed.
- Show the configured limit, current exposure, proposed additional unpaid amount and projected exposure. Define whether exposure includes outstanding invoices, opening dues, delivered-but-uninvoiced goods and undelivered orders. Do not count the same delivery again when it becomes an invoice.
- Deduct payments and apply advances/credit notes only once through their recorded allocation. A partly paid sale should add only its unpaid contribution under the agreed exposure definition.
- Distinguish an unset limit, an explicit zero-credit limit and an explicitly unlimited account. Default treatment for a new customer remains open; an absent value must not accidentally bypass control.
- Enforce the limit and any owner exception in the backend using concurrency protection; two simultaneous sales must not each rely on the same remaining credit capacity.
- Bind owner approval to the customer, sale revision and reviewed exposure. Record the approving owner and values. Approval is a transaction exception, not a permanent increase in the customer's credit limit. Proposed reuse of the D18 approval inbox requires confirmation for this exception type.
- If a sale is both below cost and over its credit limit, both exception conditions must be explicitly approved; approval for one must not silently authorize the other. Whether they share a single review screen remains an implementation proposal.
- Example assuming only invoice dues and the new unpaid sale contribute: limit 10,000, existing due 8,000 and new unpaid amount 3,000 produce 11,000 projected exposure, so owner approval is required. If 1,000 is collected and recorded against that new sale, projected exposure becomes 10,000 and the limit alone does not trigger approval. Amounts are illustrative.
- Test exact-limit and over-limit sales, partial payments, advances, return credits, revised sales, concurrent sales, owner rejection and unauthorized direct API calls. Credit approval when offline and the precise enforcement point for deferred invoicing remain open.

**Overdue customer balances — confirmed additional-credit control**

Confirmed: show a warning and require explicit owner approval for additional credit when a customer has an overdue unpaid balance, even if their total exposure remains within the credit limit. Fully paid new sales can continue subject to other controls, including below-cost approval. Money collected for the new sale does not automatically settle old debt.

Proposed operating rules and acceptance checks:

- Evaluate overdue amounts from remaining unpaid balances and their effective due dates, after recorded payments and credits. Time zone, grace days, opening-balance due dates and disputed amounts require explicit rules.
- Check both overdue status and credit-limit exposure before finalization. An approval must identify the exception(s) reviewed; approval of the limit exception alone must not silently approve the overdue exception.
- Treat a partly paid new sale as additional credit for its unpaid portion. Staff cannot bypass the overdue check merely by recording a small payment.
- A fully paid new sale must have its payment allocated to that sale. Do not allocate the same payment to old invoices while also marking the new sale paid.
- Record the owner, transaction revision, overdue amount and decision. Apply concurrency protection and recheck the authoritative balances at finalization. Exact approval inbox reuse and offline handling remain open.
- Example: credit limit 10,000, overdue balance 2,000 and new unpaid sale 1,000 require owner approval despite total exposure of only 3,000. A new sale of 1,000 paid in full against that sale does not require an overdue-credit exception; the old 2,000 remains outstanding.
- Test overdue balances inside/outside the limit, fully and partly paid sales, debt cleared before finalization, payment reversals, owner rejection and unauthorized API calls.

**Customer payment allocation — confirmed default and manual choice**

Confirmed: allocate a general customer payment to the oldest outstanding invoices first, allow authorized manual invoice selection, and retain excess as unapplied customer advance. Payments explicitly collected for a new sale remain linked to that sale under D25.

Proposed operating rules and acceptance checks:

- Record a single receipt with its customer, amount, mode, date and reference, then separate allocations to invoices. Allocated amounts plus the unapplied remainder must equal the receipt amount; allocations must not exceed eligible invoice balances.
- Restrict every allocation to the same business and customer. Exclude cancelled invoices, estimates and already-settled balances. Treatment of opening dues in the automatic queue remains to be defined.
- Preview the automatic allocation and any advance before saving. Confirm whether oldest is determined by invoice date or due date; use a stable tie-breaker for equal dates.
- Permit manual selection only with the relevant authorization, enforced in the backend. Keep an audit trail for allocation changes; receipt reversal and subsequent reallocation must restore balances consistently rather than delete history.
- Keep excess visibly separate as unapplied advance, not as an overpaid invoice. Applying that advance later reduces its available balance atomically and must not count as a second cash receipt. Automatic versus manual use of existing advances remains open.
- Example: oldest invoice owes 1,000 and the next owes 500. A general payment of 1,200 allocates 1,000 to the first and 200 to the second, leaving 300 due. A payment of 1,700 instead clears both and leaves 200 in customer advance. A payment expressly for a new sale is not swept into this queue.
- Test partial settlement, exact settlement, excess advance, manual allocations, another customer's invoice, concurrent receipts, duplicate submissions, reversals and reopening affected balances. Customer totals and document balances must reconcile.

**Sale-return settlement — confirmed allocation rule**

Confirmed: apply an accepted return's credit to the linked original invoice's unpaid balance first. An authorized user chooses a refund or customer credit for future purchases for any remaining amount. Do not refund or credit the same amount twice.

Proposed operating rules and acceptance checks:

- Link the return to the original invoice and eligible line quantities/serials. Validate quantities cumulatively across earlier returns, repeated lines in the current request and concurrent requests. Return eligibility and any no-invoice exception remain open.
- Calculate return value from the original transaction's applied price and discounts, not today's catalog price. Allocation of bill discounts, cutting charges, service charges, rounding and applicable tax corrections require explicit rules.
- Record the accepted return credit separately from cash payments. Show original invoice value, return credits, payments and remaining due without treating a return credit as money collected.
- For accepted return credit R and the invoice's eligible unpaid balance D, allocate min(R, D) to that balance. Only the remainder may become a refund or retained customer credit. Revalidate D atomically when posting.
- Example: invoice total 1,000, payments 600 and unpaid balance 400. A return worth 700 clears the 400 due and leaves 300 for refund or future credit. A return worth 200 leaves 200 due and no refundable remainder. Values are illustrative and assume no other adjustments.
- Track a refund's settlement status and payment reference. If external payout fails or its result is uncertain, retain the liability and resolve it without retrying a second payout blindly or issuing duplicate customer credit.
- Link retained customer credit to its originating return and consume it only once when applied later. Keep its source distinguishable from a cash advance. Customer identification for walk-in returns and treatment of other outstanding invoices remain open.
- Handle returned material condition separately from financial settlement: accepted returns must not automatically become sellable stock. Restocking classification follows D28.
- Test unpaid, partly paid and fully paid invoices, repeated/partial returns, discount allocation, concurrent payments, unauthorized refunds, failed payouts and later use of customer credit. Reconcile invoice due, customer balance, refund liability and stock independently.

**Stock condition on return — confirmed inspection and classification**

Confirmed: inspect accepted returned goods and classify them as sellable, damaged/awaiting inspection, or scrap. Only sellable quantities re-enter available stock. Verify the returned IMEI/serial for tracked goods and capture actual dimensions for cut pieces.

Proposed operating rules and acceptance checks:

- Record condition and accepted quantity per returned item, allowing a return to contain quantities with different conditions. Capture inspector, inspection time and supporting notes; required evidence and permissions remain to be agreed.
- Hold uninspected goods outside sellable availability. Keep damaged and awaiting-inspection reasons distinguishable even if grouped in one screen; mark scrap separately from both.
- Link the returned IMEI/serial to the original sale and validate that it has not already been returned. A mismatch must not silently reset a different serial to in-stock; exception handling remains open.
- For cut pieces, record actual continuous lengths or slab dimensions and source lineage rather than restoring the original uncut source. Eligibility and valuation of shorter/altered returns remain separate decisions.
- Post the physical receipt once, then use auditable state transfers for later reclassification. Moving an inspected piece from hold to sellable changes availability, not total physical quantity; do not count it as a second receipt.
- Preserve ownership: customer-owned material held for collection under D23 must not become shop stock merely because it is inspected. A return receipt and any ownership change need their own linked records.
- Keep condition classification separate from financial settlement under D27. Restocking or reclassification must not automatically issue another refund or credit.
- Example: three accepted returned units comprise one sellable, one awaiting inspection and one scrap. Record three physically received units but only one eligible for normal sale. If the held unit later passes inspection, two are eligible for sale and the physical count remains three until disposal or another movement occurs. Existing reservations still reduce free availability.
- Test mixed-condition returns, inspection release, damaged-to-scrap transfer, serial mismatch, repeated receipts, cut-piece dimensions, unauthorized reclassification and reconciliation with return credits.

**Exchanges — confirmed linked return and replacement sale**

Confirmed: process an exchange as a linked return and new sale. Apply eligible remaining return credit to the replacement, collect any additional amount, and refund or retain eligible excess when the replacement costs less. Settle the original invoice's unpaid balance first under D27. Apply D28 to returned-stock condition and normal sale controls to the replacement.

Proposed operating rules and acceptance checks:

- Use an exchange reference linking the original invoice, accepted return, replacement sale, credit allocation and any receipt/refund. Preserve each document's identity instead of rewriting the original sale.
- Show return value, original due settled, credit available for the replacement, replacement total and the resulting amount to collect/refund/retain. Do not imply that the full returned value is reusable when part settles old debt.
- Value returned goods using the original transaction rules; price the replacement using D14–D16 unless a separately defined price guarantee applies. Return eligibility, exchange windows and price guarantees remain open.
- Check replacement availability, reservations, serials, discounts, below-cost approval, credit limits and overdue rules independently. An accepted return does not authorize an otherwise prohibited new sale.
- Post return stock according to its inspected condition. Deduct replacement stock once and keep serial/cut-piece lineage distinct for the incoming and outgoing items.
- Credit used toward the replacement must not also be refunded or applied elsewhere. Preserve unused credit if the return completes but replacement finalization fails; expose a resumable status and avoid duplicate posting on retry.
- Example: a fully paid item's accepted return is worth 1,000 and the replacement costs 1,200: allocate 1,000 credit and collect 200. For an 800 replacement, 200 remains eligible for refund or future credit. If the original invoice instead still owes 400, settle that first; only 600 of the 1,000 return credit is available, so a 1,200 replacement needs another 600.
- Test equal/higher/lower-priced replacements, unpaid originals, mixed-condition returns, rejected approvals, insufficient stock, interrupted finalization, duplicate requests and later return of the replacement. Returning a replacement must follow its own transaction history rather than creating a second refund against the original sale.

**Purchase orders and partial receiving — confirmed launch scope**

Confirmed: supplier purchase orders may arrive in multiple deliveries. Track ordered, received and outstanding quantities per line. Add physical stock only on receipt; only eligible sellable receipts can serve waiting customer orders under D13. Keep supplier bills and payments linked without duplicating stock.

Proposed operating rules and acceptance checks:

- Preserve distinct purchase order, goods receipt, supplier bill and supplier payment records, with line-level references. Creating an order does not create physical stock; entering a bill for an existing receipt must not add it again.
- Allow multiple receipts against an order and record receipt date, supplier delivery reference, quantities, units/conversion snapshots, receiver and source order lines. Capture serials and piece/roll/slab measurements for applicable products.
- Distinguish physically received, accepted/sellable, held for inspection and rejected quantities. Only eligible accepted quantities enter available stock and automatic allocation. Detailed inspection/default acceptance rules remain open.
- Track cancelled outstanding quantities separately from received quantities. Define whether rejected or later returned goods reopen the supplier's fulfilment obligation; do not silently treat those events as cancellation or replacement commitments.
- Prevent duplicate receipt posting and protect outstanding quantities during concurrent receipt entry. Over-delivery tolerance and permission for exceptions remain open.
- Support purchase-unit to stock-base-unit conversion under D05. Record actual measured stock where variable dimensions/weights apply rather than relying on a fictitious fixed conversion.
- Example: an order for 100 receives 60 accepted units, leaving 40 outstanding. Receipt adds 60 once; those 60 become eligible for waiting-order allocation. A second accepted receipt of 40 completes the order and adds another 40. Recording the supplier's bill for these receipts adds no further stock.
- Test partial/exact receipts, repeated requests, concurrent receiving, units, serial duplicates, held/rejected goods, cancellation of the remaining quantity and supplier-bill entry after stock was received. Stock, purchase-order progress and supplier dues must each reconcile through their own records.

**Supplier bills across receipts — confirmed flexible matching**

Confirmed: allow one supplier bill per receipt or a combined bill covering several receipts from the same supplier, matching the supplier's actual document. Link billed quantities to the relevant receipt lines and prevent the same quantities being billed twice.

Proposed operating rules and acceptance checks:

- Retain supplier bill number/date and separate internal references. Select receipts within the same business and supplier; do not combine different suppliers' receipts into one bill.
- Maintain bill-line-to-receipt-line allocations with billed and unbilled quantities. Validate the total allocated against each receipt's eligible quantity atomically, including concurrent bill entry and retries.
- Show ordered, received, billed and paid information separately. Recording or correcting a bill must not post a second physical stock receipt or silently change measured received quantities.
- Flag repeated supplier document references for review. Exact uniqueness rules across supplier financial years, cancellations and corrected documents remain to be defined.
- Compare billed quantities/rates with purchase orders and receipts and expose variances. Tolerances, approval requirements and treatment of held/rejected goods remain open; do not silently accept every variance.
- Allocate supplier payments and advances through explicit links so combining receipts into a bill does not duplicate payments. Supplier payment-allocation defaults follow D32.
- Example: receipts of 60 and 40 units can be billed as separate bills for 60 and 40 or one bill for 100. After the 60-unit receipt is fully billed, it must not be included again in a new combined 100-unit bill unless the earlier bill is handled through an explicit correction process. Stock receipts remain 100 in either billing arrangement.
- Test both arrangements, cross-supplier selection, duplicate allocations, concurrent bill entry, duplicate document references, unit conversion, corrections and retained payment links. Bills received before goods and a bill split across part of a receipt remain open requirements.

**Supplier payments — confirmed default and manual allocation**

Confirmed: general supplier payments settle the oldest outstanding supplier bills first. Authorized users can manually select bills, and excess remains an unapplied advance paid to that supplier. A payment specifically designated for a bill or purchase order stays linked to that purpose.

Proposed operating rules and acceptance checks:

- Record one payment with supplier, amount, date, payment mode and reference, plus separate bill allocations. Allocations and unapplied advance must reconcile to the payment amount without duplicating the cash/bank outflow.
- Restrict allocations to eligible unpaid bills of the same supplier and business. Exclude cancelled and settled bills; treatment of opening payables and whether oldest means bill date or due date remain open.
- Preview the automatic allocation and permit manual changes only under a backend-enforced payment-allocation permission. Record the actor and allocation history; assignment and approval limits remain to be defined.
- Track an advance against a purchase order as an advance until allocated to eligible supplier bills. Linking it to an order does not create received stock or falsely mark a future bill as paid.
- Apply existing advances atomically and only once. Subsequent application is an allocation event, not a second supplier payment. Decide separately whether advance use is automatic or selected manually.
- Payment reversal or correction must restore the affected bill balances and advance availability through linked records. Rules for cancelled orders, advance refunds and external payment confirmation remain open.
- Example: bills outstanding for 1,000 and 500 receive a general payment of 1,200: allocate 1,000 to the older bill and 200 to the next, leaving 300 payable. A payment of 1,700 clears both and leaves a 200 supplier advance. A payment explicitly designated for another purchase order must not be swept into these bills.
- Test partial/exact/excess payments, authorized manual selection, cross-supplier attempts, concurrent allocations, retries, advance application and reversals. Supplier balances, bill balances and recorded cash/bank movements must reconcile.

**Purchase returns to suppliers — confirmed dispatch and settlement flow**

Confirmed: link returned goods to their original receipt and supplier bill where available, and record physical dispatch separately from financial settlement. Once the supplier accepts the return credit, reduce the original bill's unpaid balance first. Retain any remainder as supplier credit for future purchases or record a refund actually received. Keep pending/disputed claims visible without assuming supplier acceptance.

Proposed operating rules and acceptance checks:

- Maintain separate dispatch and claim statuses, with requested quantities/value, dispatched quantities, supplier-accepted value and settlement allocations. Store supplier acknowledgement/reference, decision date and recording user; detailed permissions remain open.
- Return only physically held, eligible quantities and verify serials/piece dimensions against the source records. Account for previous returns and concurrent dispatches. Reserved customer stock requires explicit resolution before supplier dispatch.
- Record physical stock leaving once on actual dispatch. Filing a claim or recording supplier credit/refund must not deduct it again. A rejected claim does not automatically restore physical stock; goods must actually return and be received if sent back.
- Do not reduce supplier payables merely because a claim is submitted. Apply accepted credit once, using the bill's current unpaid balance and keeping credit allocation distinct from cash payments.
- Example: original bill 1,000, paid 600, unpaid 400. Supplier accepts return credit of 700: settle 400 payable and retain 300 supplier credit or track the agreed refund until it is received. While the claim is pending, its requested value does not clear the 400 payable.
- A promised refund remains pending until receipt is recorded. Never both spend the same supplier credit and record it as refunded. Record partial acceptance, deductions and disputed remainder separately rather than silently replacing the requested claim value.
- Preserve source links when the original supplier bill covers multiple receipts. Unbilled returns, supplier replacements, freight charges, tax corrections and whether returned quantities reopen the purchase order remain separate decisions.
- Test partial returns, partial acceptance, unpaid/partly paid/fully paid bills, claim rejection, actual goods re-receipt, duplicate dispatch/settlement requests, concurrent payments and refund receipt. Reconcile physical stock, supplier payable, usable supplier credit and pending claims independently.

**Daily cashbook and closing — confirmed launch scope**

Confirmed: record opening cash, cash sales/collections, customer cash advances, refunds, supplier cash payments, cash expenses, owner cash added/withdrawn and cash deposits/withdrawals to/from bank. Calculate expected closing cash, enter physically counted cash, and record any difference with a reason for owner review. Keep UPI/card/bank movements separate from physical cash.

Proposed operating rules and acceptance checks:

- Calculate expected cash as opening cash plus actual cash inflows minus actual cash outflows. Credit sales, invoice totals, unpaid expenses, applied advances and non-cash credits must not be mistaken for new cash movements.
- Derive entries from linked payment/refund/expense/transfer records. Record manual cash movements with category, actor, time and reason; prevent a source event from being posted twice.
- For split payments, only the cash portion affects the physical drawer. Keep UPI/card/bank amounts visible separately; reconciliation against actual provider/bank settlements is a distinct, still-open requirement.
- Treat cash deposits to bank as transfers, not expenses, and bank withdrawals to cash as transfers, not sales. Supplier refunds actually received in cash increase cash; pending refunds do not.
- Save a closing snapshot with period, opening cash, inflows/outflows, expected cash, counted cash, variance, explanation, submitting staff member and owner-review status. Closing cut-off, denomination entry and approval roles remain open.
- A difference does not silently become a sale or expense. Owner review must determine the correction or adjustment, preserving the original closing evidence. Closing locks and owner-only reopening/correction authorization follow D36; backdated entries and next-day opening carry-forward require further rules.
- Example: opening 1,000 plus cash receipts 5,000 minus cash expenses 500, supplier payment 1,500, refund 200 and bank deposit 2,000 gives expected cash 1,800. Counting 1,750 records a shortage of 50. A separate UPI receipt of 3,000 does not change that expected drawer cash.
- Test split payments, credit sales, cash advances applied later, transfers, refunds, reversed payments, duplicate events, closing differences and concurrent entries. Offline closing must clearly identify unsynced transactions; finalization rules remain open.

**Counters and shifts — confirmed single-store flexibility**

Confirmed: one shared cash drawer is the default. Larger stores can enable separate billing counters and cashier shifts with their own opening cash, handovers and closings. This does not introduce multiple stores or locations.

Proposed operating rules and acceptance checks:

- Distinguish a device, a billing counter, a physical cash drawer and a cashier shift. Attribute each cash movement to exactly one drawer and active shift/session; multiple devices using a shared drawer must not create duplicate drawer balances.
- Keep cashier attribution on every transaction even in shared-drawer mode. Define who may open, use, hand over and close each drawer; counter assignment and staff permissions remain open.
- Maintain a store-wide summary across drawers without counting internal transfers as external income or expense. A transfer must have linked debit/credit entries and an explicit in-transit state if handover is not completed immediately.
- At shift handover, record expected cash, actual counted cash, retained/transferred float, outgoing and incoming staff and any discrepancy. Do not carry forward an unexplained difference as if it were a sale or silently rewrite the previous closing.
- Shift boundaries need not equal calendar-day boundaries. Define business-day cut-off and midnight handling so the same cash event is included once in both shift and daily reporting.
- All counters share the store's inventory, customer balances and reservations. Enforce stock/serial/credit concurrency across counters and use unique document identifiers; separate drawers do not imply separate stock ownership.
- Example: drawer A holds 1,000 and drawer B holds 500. An actual transfer of 200 from A to B leaves 800 and 700, while store cash remains 1,500. A shift handover within A changes responsibility for its cash, not store income.
- Test the shared default, separate counters, successive shifts, internal cash transfers, interrupted handovers, concurrent sales, duplicate event retries and combined daily totals. Offline cross-device reconciliation and unresolved-shift closing remain open.

**Closed cash periods and corrections — confirmed owner control**

Confirmed: lock cash closings against ordinary staff edits when submitted. Only the owner may reopen a closing or authorize a correction. Record the reason and preserve the original history.

Proposed operating rules and acceptance checks:

- Preserve each submitted snapshot with drawer/shift, period, submitting user, expected cash, counted cash, variance and submission time. Pending owner review must not make the submitted record editable by ordinary staff.
- Enforce locks on the backend, including indirect changes to underlying payments, refunds, expenses and transfers. An ordinary staff member cannot bypass a locked closing by editing a source record through another screen or API.
- Link owner authorization to a specific closing and correction scope. Record before/after values, owner, acting user, reason and time. Ordinary staff must not gain unrestricted historical editing rights merely because one correction was authorized.
- Retain prior closing versions when reopening and resubmitting. Define whether staff may execute a narrowly authorized correction or the owner performs it directly; authorization remains owner-only in either case.
- Later receipts and refunds should create new dated, linked movements rather than silently rewrite a prior closing. Distinguish genuinely new cash movements from correction of incorrectly recorded historical data to avoid creating fictitious cash flow.
- Show any effect on subsequent opening balances and summaries. Do not silently revise later locked closings; those require explicit review and reconciliation. Detailed carry-forward rules remain open.
- Test staff edit attempts on both the closing and source records, owner reopening with a reason, scoped correction, repeated submissions, concurrent transactions and immutable access to the original snapshot. Offline submissions and late-arriving transactions require a defined provisional/final policy.

**Repair estimates and customer approval — confirmed workflow**

Confirmed: prepare a parts-and-labour estimate for mobile repair and car/bike garage jobs, record customer approval before beginning repair work, and obtain renewed approval for additional work or charges beyond the approved estimate.

Proposed operating rules and acceptance checks:

- Link the estimate to the customer, job card and identified device/vehicle. Itemize proposed parts, labour, quantities, prices, discounts and applicable charges so the approved scope and total are explicit.
- Version estimates and preserve the version approved by the customer. Record the approving customer/contact, approval scope, date/time, channel, evidence/reference and recording staff member. Supported channels and required evidence remain open; a sent message or unanswered request is not approval.
- Separate customer consent from internal owner approvals. Customer approval does not waive below-cost, credit-limit or staff-permission rules; owner approval alone does not establish customer consent to extra work.
- Keep unapproved repair work pending. Diagnostic/inspection work and its charges need separately defined consent rules and must not be assumed authorized merely because a job card exists.
- For additional work or increased charges, create a revised estimate and request renewed approval before performing the added work. Preserve already-approved scope and actual work history. Rules for partial approvals, substitutions and cancellations remain open.
- Track actual parts and labour against approved scope. Final billing must not silently include unapproved extras, and invoice generation must not deduct parts twice if they were already consumed through the job workflow.
- Example: the customer approves parts and labour totalling 2,000. A newly identified 500 repair requires approval of the revised 2,500 scope before that extra work starts. An added task also needs approval if the total stays at 2,000; the requirement covers scope as well as amount.
- Test initial approval, rejection, revised estimates, stale approval responses, added work with unchanged total, unauthorized status changes and final invoice reconciliation. Offline approval evidence, diagnostic fees, deposits and warranty/no-charge jobs require separate rules.

**Repair approval evidence — confirmed (D38)**

Record in-person or phone approval with the customer's name, the approved estimate version, time, staff member and notes. Staff may attach customer confirmation evidence, such as a WhatsApp reply screenshot or a photo of a signed job sheet. Label these records "staff-recorded", not "digitally verified customer approval". Automated WhatsApp integration and customer approval links are outside launch scope and would need a separate decision.

Acceptance checks:

- An approval record cannot exist without an estimate version; approving version 2 does not approve version 3.
- Attachments are stored against the job card under the business's tenant boundary and are visible only to that business and platform support.
- Editing an estimate after approval creates a new version with status "awaiting approval"; the earlier approval remains on record for its own version.

**Proposed defaults for open details**

These defaults close the details that the confirmed sections leave open. Each stands unless the owner changes it during review. The *Section* column names the confirmed section the default belongs to.

*Pricing, discounts and approvals (D14–D19)*

| ID | Section | Proposed default |
|---|---|---|
| PD01 | Cost basis | Weighted average cost per stock base unit, recalculated on each accepted purchase receipt. It excludes recoverable GST input tax for GST-registered businesses and includes it for non-GST businesses. |
| PD02 | Missing cost | If a product has no recorded cost, the below-cost check cannot run. The sale proceeds, and the owner sees a "cost missing" warning on the product and in a daily exceptions list. |
| PD03 | Service lines | Service and labour lines are excluded from the below-cost check unless the owner sets a cost for that service. |
| PD04 | Below-cost comparison | Compare effective line price (after allocating bill-level discount pro rata by line value) with cost, both per stock base unit and both excluding GST. |
| PD05 | Wholesale eligibility | A wholesale price applies when the customer is marked "wholesale" or the line quantity reaches the product's tier minimum. Tiers are evaluated per product per invoice, in the stock base unit. |
| PD06 | Order rate lock | For R2 sales orders, the rate is fixed at order confirmation and partial deliveries invoice at that rate. |
| PD07 | Discount limit unit | Staff discount limits are a percentage, per staff member, measured as the total reduction from the default price source (D15) on the invoice. This includes negotiated price changes, line discounts and bill discounts combined, so smaller repeated discounts or a price change cannot bypass the cap. |
| PD08 | Default staff limit | New staff have a 0% discount limit and no price-edit permission until the owner grants them. |
| PD09 | Discount reason | A reason is optional within the limit and mandatory for any owner-approved over-limit discount. |
| PD10 | Over-limit request | A staff discount above their limit goes through the owner approval inbox, like a below-cost sale. |
| PD11 | Approval expiry | A pending approval request expires at the end of the business day (midnight, Asia/Kolkata) or after 12 hours, whichever comes first. An expired request must be resubmitted. |
| PD12 | Stock holds | Pending drafts do not hold stock. Availability is rechecked at finalization. |
| PD13 | Approval notification | Push notification to the owner's signed-in devices plus an in-app inbox badge. The inbox is authoritative; the push is best effort. |
| PD14 | Same-device approval | Not supported at launch. The owner approves only from their own signed-in app, as D18 requires. |
| PD15 | One review screen | When a sale needs several exceptions (below cost, credit limit, overdue), the owner sees one request listing each exception with its own approve checkbox. Approving the request requires every listed exception to be ticked. |

*Credit, overdue and payments (D24–D26)*

| ID | Section | Proposed default |
|---|---|---|
| PD16 | Credit exposure | Exposure = unpaid invoice balances + opening dues + delivered-but-uninvoiced value (R2) − unapplied advances and customer credits. Undelivered orders are excluded. |
| PD17 | New-customer limit | A store-level default credit limit applies to new customers; its initial value is 0, so any credit sale needs owner approval until the owner sets a limit. Each customer can be given a specific amount or explicitly marked unlimited. |
| PD18 | Existing customers | Existing customers whose limit is currently empty (meaning "no limit" in migration 0013) are migrated to "unlimited" explicitly, so current shops see no behaviour change. |
| PD19 | Payment terms | Store default is 30 days from invoice date. Staff with credit-sale permission may shorten or extend the due date on a new invoice; changing the due date of an issued invoice is owner-only. |
| PD20 | Overdue calculation | An invoice is overdue once its due date has ended in Asia/Kolkata time plus the store's grace days (default 0). Opening dues are due on the opening-balance date plus the store's payment terms. Disputed amounts are not modelled at launch. |
| PD21 | "Oldest" | Oldest means earliest invoice date (or bill date for suppliers), with document number as tie-breaker. Opening dues come before all invoices. |
| PD22 | Advances | Unapplied advances are applied manually: the POS prompts "apply advance of ₹X?" when the customer has one. They are never applied automatically. |
| PD23 | Receipt reversal | A receipt is reversed by a linked reversal record with a mandatory reason; allocations are restored. Receipts are never deleted. Reversal is owner-only. |
| PD24 | Offline credit | An offline credit sale is allowed only if the customer's cached snapshot shows available credit and no overdue balance. It is rechecked on sync; if it fails then, it is flagged for owner review, because the goods have already left. |

*Returns and exchanges (D27–D29)*

| ID | Section | Proposed default |
|---|---|---|
| PD25 | Return window | Store setting, default 30 days from invoice date. The owner can accept a return outside the window with a reason. |
| PD26 | Return valuation | Original line price after pro-rata allocation of the bill discount, rounded to paise. Invoice round-off is not refunded. GST is reversed proportionally on a credit note. |
| PD27 | Cut-piece returns | Not accepted by default. The owner can allow them per product; the actual returned dimensions are recorded (D28). |
| PD28 | Walk-in returns | Without an identified customer, the remaining return credit can only be refunded, not kept as customer credit. |
| PD29 | Inspection permission | Staff with return permission classify returned goods. Moving goods from damaged/awaiting inspection to sellable requires stock-management permission. |
| PD30 | Exchange rules | Same window as returns, no price guarantee: the replacement is priced under D14–D16 at the time of exchange. |

*Orders, delivery and reservations (D08–D13, R2)*

| ID | Section | Proposed default |
|---|---|---|
| PD31 | Combined invoice grouping | A combined invoice may include deliveries from several orders of the same customer, all within the same GST tax period. |
| PD32 | Issued-invoice correction | Issued invoices are corrected by a credit note and a new invoice, never by editing. |
| PD33 | Advance allocation | An order advance is allocated to that order's invoices oldest first, capped at each invoice's amount; the remainder stays visible on the order. |
| PD34 | Offline orders | Order confirmation, reservation, delivery and allocation require a connection. They are not available offline. |
| PD35 | Store default mode | The owner can set the store default to per-delivery (the D10 default) or combined invoicing. |
| PD36 | Serial and cut reservations | Reservations hold quantities, not specific items. A serial is chosen at delivery. For cut goods, a reservation is accepted only if a suitable continuous source piece exists; the specific piece is chosen at cutting. |
| PD37 | Increased order quantity | Quantity added to an existing order joins the replenishment queue with the time of the increase. The original quantity keeps its place. |
| PD38 | Manual priority duration | A manual priority change stays until changed again or the order is completed or cancelled. |

*Cut pieces and remnants (D20–D23)*

| ID | Section | Proposed default |
|---|---|---|
| PD39 | Suitability | A source piece is suitable if it has the same product and variant, is available and unreserved, and its length is at least the cut plus the product's cutting allowance. |
| PD40 | Cutting allowance | Per-product setting, default 0. |
| PD41 | Point of cutting | The cut is recorded when the sale or delivery is finalized, in the same transaction that deducts stock. |
| PD42 | Remnant threshold | Per-product minimum reusable length, default 0 (every leftover suggested as reusable) until the owner sets it. |
| PD43 | Reclassification permission | Stock-management permission is required, with a mandatory reason. |
| PD44 | Cutting charge | Optional flat charge per cut, configured per product. It is billed as a separate service line, once per cut. |
| PD45 | Full-piece billing (R2) | Requires price-edit permission. Customer agreement is recorded with a confirmation tick, the staff member's name and time. |
| PD46 | Customer-owned remnants (R2) | Uncollected material triggers a reminder after 90 days. It is never automatically converted to shop stock or scrap. Transfer to shop ownership is at zero value by default and needs a reason and customer agreement. |

*Purchasing (D30–D33, R2)*

| ID | Section | Proposed default |
|---|---|---|
| PD47 | Over-delivery | Receiving more than the outstanding quantity is blocked. The owner may accept the excess, which is then added to the order. |
| PD48 | Inspection on receipt | Received goods are accepted as sellable by default. Staff can mark quantities held or rejected on the receipt. |
| PD49 | Rejected goods | Rejected quantities do not reopen the purchase order unless the user marks "replacement expected". |
| PD50 | Duplicate supplier bill number | The same bill number from the same supplier within one financial year is blocked; the owner can override with a reason. |
| PD51 | Price variances | Differences between order, receipt and bill rates are flagged on the bill and in a variance report. They are not blocked. |
| PD52 | Supplier advances | Applied to bills manually, never automatically. |

*Cashbook and closing (D34–D36)*

| ID | Section | Proposed default |
|---|---|---|
| PD53 | Business day | Midnight to midnight, Asia/Kolkata, configurable per store. |
| PD54 | Who closes | Staff with cash-closing permission submit the closing; the owner reviews it. |
| PD55 | Denominations | Denomination entry is optional; only the total counted cash is required. |
| PD56 | Carry-forward | The next day's opening cash is the previous closing's counted cash, not its expected cash. |
| PD57 | Late entries | A cash movement dated inside a locked period is refused. It must be recorded in the current period with a reference to the original date. |
| PD58 | Offline closing | Closing requires a connection and is refused while unsynced transactions exist on that device. |

*Repairs (D37, D38)*

| ID | Section | Proposed default |
|---|---|---|
| PD59 | Diagnostic fee | Optional fixed fee per service type. Customer consent to it is recorded at intake; the fee is billable even if the repair estimate is rejected. |
| PD60 | Deposits | Recorded as a job-card advance (already in the job card schema) and applied to the final invoice. |
| PD61 | Partial approval | The customer may approve a subset of estimate lines; only approved lines can be worked on and billed. |
| PD62 | Warranty jobs | Zero-price lines are allowed with a warranty reference to the original job or invoice. |
| PD63 | Parts consumption | Parts leave stock when marked as used on the job card; the final invoice references them without a second deduction. |
| PD64 | Vehicle fields | Registration number (required for vehicle jobs), make, model, odometer reading at intake, optional chassis/VIN, fuel level and a photo of the vehicle's condition at intake. |

**Roles and permissions — proposed default**

There are three roles:

- **Platform admin:** SOFTRAXA staff, using the admin panel.
- **Owner:** one per business.
- **Staff:** with individually granted permissions.

Every permission is checked in the database (row-level security and RPCs) through a single permission helper; the app only mirrors the result to show or hide controls. Revoking a permission takes effect on the next request, including on screens already open.

| Permission | Owner | Staff default | Notes |
|---|---|---|---|
| Create sales invoices | ✅ | On | Includes cash, UPI, card and split payments |
| Credit sales | ✅ | Off | Within limits; exceptions need owner approval |
| Edit selling price (negotiated) | ✅ | Off | Subject to the discount limit (PD07) |
| Apply discount | ✅ | Off | Up to the owner-set percentage limit |
| View cost and profit | ✅ | Off | Hides cost, margin and profit reports in the database, not just on screen |
| Manage products and price lists | ✅ | Off | |
| Manage stock (adjustments, reclassification) | ✅ | Off | |
| Purchases and receipts | ✅ | Off | |
| Record customer and supplier payments | ✅ | Off | Automatic (FIFO) allocation only |
| Manual payment allocation | ✅ | Off | |
| Returns and exchanges | ✅ | Off | Refund payout also requires the refund permission |
| Issue refunds | ✅ | Off | |
| Job cards | ✅ | On | |
| Reports | ✅ | Off | Sales reports without cost unless "view cost and profit" is also granted |
| Cash closing | ✅ | Off | Submit only; reopening is owner-only (D36) |
| Reservation override (R2) | ✅ | Off | D11 |
| Invoicing override (R2) | ✅ | Off | D11 |
| Approve exceptions (below cost, credit, overdue) | ✅ | — | Cannot be delegated at launch |
| Credit limits, staff permissions, business settings, subscription | ✅ | — | Owner-only at launch; delegating staff management is future scope |

Platform admins act only through the admin panel's audited routes. Every permission grant, revocation, approval, override and reopening is written to the audit log with the actor, time and reason.

**GST and tax — confirmed scope (D40), proposed rules**

Proposed requirements:

- **Registration data:** the business's GSTIN, legal name and state; each customer's and supplier's optional GSTIN and state. GSTIN format and check digit are validated on entry.
- **Document types:** tax invoice for GST-registered businesses; bill of supply for composition dealers and exempt supplies (composition is added as a tax preference); cash memo and estimate remain non-tax documents.
- **Place of supply:** the customer's state for B2B and delivered sales, and the store's state for counter sales. Intra-state supply shows CGST + SGST; inter-state supply shows IGST. The split is stored per line.
- **HSN/SAC:** mandatory on GST products and services, with the number of digits required by the business's turnover band (the owner declares the band during setup).
- **Numbering:** a separate invoice series for each financial year (April–March), unique, sequential and at most 16 characters. Credit notes use their own series.
- **Credit notes:** every accepted sale return on a tax invoice issues a credit note linked to the original invoice, reversing GST proportionally (PD26). Supplier debit/credit notes are recorded against purchase returns.
- **Reports:** GSTR-1 export by section (B2B, B2CL, B2CS, credit/debit notes, HSN summary, document summary); GSTR-3B summary (outward tax, eligible input tax credit from purchases); purchase register; all as Excel/CSV.
- **Out of scope at launch:** e-invoice (IRN) and e-way bill generation. Onboarding must ask about annual turnover. A business above the e-invoicing threshold is not onboarded until R3 delivers that integration.
- **Legal sign-off:** a chartered accountant reviews the invoice format, credit note format, numbering and GSTR export mapping before R1 release. Tax rules change; the review is repeated at least once a year.

Acceptance examples:

- A Maharashtra shop selling to a Karnataka-registered customer shows IGST.
- The same shop selling at the counter shows CGST 9% + SGST 9% on an 18% item.
- A partial return of a two-line invoice produces a credit note with proportionally reversed tax, and it appears in the next GSTR-1 export under credit notes.

**Offline operation — proposed default**

Offline support is a billing fallback, not offline-first operation.

| Works offline (R1) | Needs a connection |
|---|---|
| POS billing with cash, UPI, card and split payments | Returns, exchanges and refunds |
| Credit sales within the cached limit (PD24) | Purchases, receipts and supplier payments |
| Viewing cached products, prices, stock and customers | Customer payment collection and allocation |
| Saving below-cost or exception sales as pending drafts (D19) | Approvals, cash closing, reports, settings, job card updates, all R2 orders |

Rules:

- **Account isolation:** each signed-in user and business gets its own local database. Signing out keeps unsynced bills for their own account and never sends them under another account. Switching accounts never shows the previous account's data.
- **Cold start:** the app opens offline if the device's last successful sign-in context is under 72 hours old and the subscription was active then. Otherwise it shows a "connect to continue" screen.
- **Catalog cache:** the whole active catalog is downloaded in pages, then kept current with changes since the last sync. There is no 100-product limit, and deleted or deactivated products are removed from the cache.
- **Numbering:** offline bills get a provisional number and receive their final invoice number when synced. Printed offline bills show "provisional" until then.
- **Sync:** the server is authoritative, and every queued bill is submitted once (idempotent by local ID). A bill that fails a server check (for example insufficient stock or a credit exception) is kept and flagged for owner review, never silently dropped.
- **Warnings:** the app warns when any bill has been unsynced for more than 24 hours, and blocks further offline billing after 7 days without a sync.

Acceptance: sign in, sync more than 100 products, turn on airplane mode, restart the app, bill a product outside the first 100, reconnect, and confirm exactly one invoice and one stock deduction. Repeat with a second account on the same device and confirm neither account sees or submits the other's data.

**Platforms, hardware, printing, imports and exports — proposed default**

| Area | R1 support |
|---|---|
| Shop app | Android 8.0 or later on phones and tablets; Windows 10/11 desktop. iOS is not in launch scope. |
| Admin panel | Current Chrome and Edge, SOFTRAXA staff only. |
| Receipt printing | 58 mm and 80 mm ESC/POS Bluetooth thermal printers (Android); A4 and A5 invoices as PDF through the system print dialog (Android and Windows). A tested list of printer models is published before R1. USB thermal printing on Windows follows in R2. |
| Barcode scanning | Phone camera, plus USB and Bluetooth scanners working as keyboard input. Barcode label printing follows in R3. |
| Imports | Excel templates for products (already built), customers and suppliers with opening balances, and opening stock including serials. Imports validate everything before writing anything and show every rejected row. |
| Exports | Invoice PDF and sharing; every report as Excel/CSV; GSTR exports (D40); a full business data export for the owner at any time, including after subscription expiry. |
| Sharing and payments | Share invoices through the phone's share sheet and WhatsApp links (no WhatsApp API). Invoices show a UPI QR code for the business's UPI ID. Payment-gateway integration is out of scope. |

**Subscriptions and plans — proposed default**

- **Plan structure:** a 14-day free trial, then paid plans that differ by staff user limit and by modules (for example, R2 wholesale modules only on higher plans). Plan names, prices and limits: owner to set.
- **User limits:** an empty plan user limit means unlimited. No subscription or no plan means the owner only (fixes finding 14). Limits are checked when a staff member is added, with a lock so two simultaneous additions cannot exceed the limit.
- **Expiry:** after the end date, the business gets a 7-day grace period with full access and a renewal banner. After grace, the business is read-only: viewing, printing, exporting and recording payments received stay available; new invoices, purchases and stock changes are refused by the database.
- **Suspension:** a platform admin can suspend a business. Suspended businesses can only export their data and contact support.
- **Retention:** data is kept for 12 months after expiry. Deletion follows 30 days' notice to the owner and only after an export has been offered.
- **Server-side status:** subscription status is enforced in the database (fixes finding 16), and the owner cannot change their own business's active flag.

**Onboarding, data migration, training and support — proposed default**

- **Account creation:** self-signup with email verification (already built), or creation by a SOFTRAXA admin with an invitation link that lets the owner set their own password. The admin never chooses or emails the password (fixes finding 11).
- **Setup wizard:** business category, GST registration details and turnover band (D40), UPI ID, invoice settings and printer test. The category selects which modules and product fields are shown (for example IMEI for mobile shops, sizes for garments, cut pieces for hardware and electrical, vehicle fields for garages).
- **Migration from paper or other software:** Excel import of products, opening stock, customers and suppliers with opening balances. For pilot shops, SOFTRAXA staff do the first import with the owner.
- **Training:** the in-app walkthrough (already built), short video guides per category, and a one-hour onboarding call for every pilot shop.
- **Support:** in-app support tickets (already built) plus a published WhatsApp support number. Pilot response target is within 4 working hours; general response target is within 1 working day. Support staff access customer data only through audited admin tools.
- **Incident severity:**
  - Sev 1 (data loss, wrong stock or balances, security): response within 1 hour, owner informed the same day.
  - Sev 2 (billing blocked for a shop): response within 4 hours.
  - Sev 3 (everything else): next working day.

**Security, data protection and operations — proposed default**

- **Secrets:** no secrets in source control. The ImageKit private key is rotated and moved to server-side configuration; the repository is private; a secret-scanning check runs in CI.
- **Tenant isolation:** automated tests with two businesses and owner, staff and admin users call every table and RPC directly. They prove no cross-business read or write and no privilege escalation. These tests are a release gate.
- **Ledger integrity:** stock movements and payments are append-only for app users; corrections are compensating entries. A nightly job reconciles stored stock and balances against their ledgers, and reports mismatches to SOFTRAXA.
- **Environments:** separate Supabase projects for development, staging and production. Migrations are applied with the Supabase CLI and tracked; the duplicate 0026 and 0027 prefixes are renumbered before adoption. Every release first runs a clean replay of all migrations on staging.
- **CI:** Flutter analyze and tests, admin and website lint and build, migration replay and security tests on every change to the main branch.
- **Backups:** production uses daily backups with point-in-time recovery. A restore is tested into staging every month and before each release, and the result is recorded.
- **Monitoring:** crash reporting for the Android and Windows apps, error reporting for the admin panel and website, database and function log alerts, uptime checks, and an alert when the offline sync failure rate rises.
- **Push alerts:** the push-alert function requires a scheduler credential, accepts only the expected method, and deduplicates runs (fixes finding 12).
- **Data protection:** a privacy policy and terms of service meeting India's Digital Personal Data Protection Act 2023, reviewed by a lawyer before R1. Owners can export and request deletion of their data. Customer phone numbers are used only by the shop that recorded them.
- **Release distribution:** Android through Play Console internal testing, then closed testing for the pilot. Windows through a signed installer. Every release has a rollback plan: the previous app build stays available, and database changes are backward compatible for one release.

**Requirement-to-implementation map (checked 25 September 2026)**

Status against the current code. "Partial" means some building blocks exist but the confirmed rules are not met.

| Capability | Current state | Main gaps | Release |
|---|---|---|---|
| Tenant isolation and roles | RLS on all tables; owner/admin roles | Findings 1–3, 18: self-promotion to admin, cross-tenant references, unguarded plan RPCs, mutable stock ledger | R0 |
| Staff and permissions | Staff table, permission toggles and screen (uncommitted) | Not enforced in the database or the POS (finding 4); staff list blocked by RLS (13); user limit bug (14) | R0 |
| POS billing and invoices | Built: create_invoice RPC, split payments, auto round-off, edit and cancel | Price source snapshot; discount limits; serial ownership checks (15) | R0/R1 |
| GST invoicing and reports | GSTIN and state on business and parties, with GSTIN check-digit validation; place of supply and customer GSTIN kept per invoice; CGST/SGST/IGST split per line after the bill discount; credit notes for returns on tax invoices and debit notes for purchase returns (own series per financial year, PDF); GSTR-1 (B2B, B2CL, B2CS, CDNR, CDNUR, HSN B2B/B2C, documents), GSTR-3B summary and purchase register, on screen and as one Excel workbook (migrations 0036, 0040) | Bill of supply and composition preference; HSN mandatory by turnover band; financial-year invoice series (invoice numbers still share one running series); chartered accountant sign-off | R1 |
| Offline billing | Drift queue with idempotent local ID | Not isolated per account (5); no offline cold start and 100-product cache (6) | R0 |
| Pricing | Retail and MRP; single wholesale price and minimum quantity | Customer-specific prices, precedence, multi-tier pricing (R2), overrides and audit | R1/R2 |
| Approval inbox | None | New: below-cost, credit-limit and overdue exceptions | R1 |
| Credit and dues | Customer credit limit with explicit "unlimited" flag and store default limit for new customers (PD17/PD18, migration 0036); POS warning when exceeded; receipts with allocations (oldest first or chosen bills) and a preview; customer advances with their own ledger, applied only on request (PD22), refundable and reversible by the owner (PD23) (migration 0041) | Limit enforcement and approval, due dates, overdue checks | R1 |
| Returns and exchanges | Sale and purchase returns with aggregated quantity checks, locking and bill-first settlement (0038); GST credit/debit notes (0040); per-line condition with held-goods ledger, release needing stock permission (PD29); return window with owner override (PD25); exchanges as one linked, idempotent transaction (0042) | Cut-piece return dimensions (with the cut-piece rules, PD27); per-category return eligibility | R1 |
| Units | One secondary unit per product (migration 0020) | Conversion snapshots on documents; variable-measure goods (R2) | R1/R2 |
| Cut pieces | Piece tracking (available/consumed/scrap) and piece picker | Suggestion with allowance, lineage, thresholds, cutting charge; customer-owned remnants (R2); slabs (R3) | R1–R3 |
| Serials/IMEI | Serial table and bulk import helpers (uncommitted) | Import can resurrect sold serials; sale does not verify serial availability (15) | R0 |
| Job cards and repairs | Job cards, services, statuses including estimate/waiting approval, advance, location | Versioned estimates, D38 evidence and attachments, vehicle fields, parts consumption | R1 |
| Cashbook and closing | Expenses only | Entire D34–D36 cashbook | R1 |
| Sales orders, reservations, deliveries | None | Entire D08–D13 scope | R2 |
| Purchase orders and receipts | Direct purchase bills that add stock immediately | Orders, receipts, combined bills, supplier advances, return claims | R2 |
| Subscriptions and plans | Plans, feature flags, user limit, blocked screen | Server-side enforcement (16), grace and read-only rules | R0/R1 |
| Printing, scanning, import | Bluetooth thermal, PDF, camera scan, Excel product import | Customer/supplier/opening-balance imports; tested printer list | R1 |
| Auth and provisioning | Signup, email verification, admin client creation | Password reset (7), unchecked provisioning writes (10), email fallback (11) | R0 |
| Admin panel and website | Clients, plans, CRM, CMS | CMS publishing (17); website lint errors; contact form abuse protection | R0/R1 |
| Operations | None | CI, migration tracking, backups with restore tests, monitoring, push-alert authorization (12) | R0 |

**Release criteria — proposed default**

A release ships only when all of these hold. Evidence is recorded in the analysis report.

1. No open critical or high findings for the release's scope. Security and two-tenant tests pass.
2. Flutter analyze reports no warnings; all Flutter, admin and website tests, lint and builds pass; migrations replay cleanly on an empty database.
3. Every requirement in the release has its acceptance checks from this document automated or recorded as manually verified, with the tester and date.
4. The chartered accountant's GST sign-off (R1) and the lawyer's privacy review (R1) are complete.
5. A backup restore test has passed within the last 30 days.
6. The offline acceptance test and the printer list test pass on real Android and Windows devices.

**Pilot — proposed default**

- **Cohort:** 5–10 shops across at least three R1 categories, including at least one repair shop and one hardware or electrical shop with cut goods. Pilot shops receive the pilot period free in exchange for weekly feedback.
- **Duration:** 4 weeks after the last pilot shop goes live.
- **Exit criteria:**
  - No Sev 1 incidents in the final two weeks.
  - The nightly stock and balance reconciliation shows zero unexplained mismatches.
  - At least 99.5% of app sessions are crash-free.
  - Every pilot shop completes daily billing and cash closing on Dukania without paper backup for the final two weeks.
- **Decision:** after the pilot, the owner decides on general availability for R1 categories and on the start of R2.

**Owner review checklist**

To finalize this specification, the owner:

1. Reviews PD01–PD64 and the defaults in the sections above; for each one they disagree with, records the replacement as a new decision.
2. Sets plan names, prices, user limits and module packaging.
3. Sets target dates for R0, R1 and the pilot.
4. Names the chartered accountant and lawyer for the R1 reviews.
5. Confirms the pilot shops.

**Launch-readiness constraint**

The 21 September review found critical profile privilege escalation and cross-business stock-write risks, as well as gaps in permissions, offline isolation, returns and accounting, password recovery and provisioning. A recheck on 25 September 2026 confirmed that no source code had changed and that these findings still apply. It also found that the ImageKit private key is hardcoded in migration 0012 of a publicly readable repository. All of this is release R0 and must be corrected and verified before any real customer data is entered.

Current test results (25 September 2026):

- Flutter tests: all 73 pass after a dependency refresh.
- Flutter analyze: one warning and five informational issues.
- Admin: lint (one warning) and type-check pass.
- Website: type-check passes; lint fails with 32 errors and 25 warnings.

Results must be refreshed after implementation changes.
