# Product Requirements Document

## Inventory Management System for Local Indian Shops

## 1. Product Overview

This product is a **mobile-first inventory, billing, and stock management system** for local Indian shops. The first target customers are **mobile shops, garment shops, and hardware shops** in Odisha, with the future goal of expanding across India.

The system will help shop owners manage products, stock, billing, GST invoices, purchases, expenses, customers, suppliers, barcode scanning, and business reports from a simple Flutter mobile app. A web-based admin panel will be used by the software owner to manage clients, subscriptions, plans, and feature access.

## 2. Technology Direction

The product will use:

* **Flutter** for the customer mobile app
* **Next.js + shadcn/ui** for the customer web panel and main admin panel later
* **Supabase** for backend, authentication, storage, and data management

The first build priority is the **Flutter mobile app**.

## 3. Target Customers

The first target customers are:

* Mobile shops
* Garment shops
* Hardware shops

Initial selling focus will be **low-cost local Odisha shops**, then later the product can expand to other Indian cities and shop categories.

## 4. Business Model

The product will support two selling models:

1. **Subscription model**

   * Monthly or yearly plans
   * Manual payment collection in V1

2. **Custom sale model**

   * Custom pricing for individual shops
   * Special feature access or setup based on client requirement

## 5. Product Goals

The main goal is to help shop owners:

* Create bills quickly
* Manage inventory accurately
* Track stock in/out
* Generate GST and non-GST invoices
* Scan barcodes using mobile camera or external scanner
* Track purchases, suppliers, customers, and dues
* Manage daily expenses
* Import products using Excel
* View simple business reports
* Continue billing during internet issues using basic offline billing

## 6. V1 Scope

V1 will focus on the core features needed to sell the product to local shops.

### Included in V1

* Email/password login
* Client self-signup and admin-created account
* Business profile setup
* Product management
* Product variants
* Barcode scanning
* POS/billing system
* GST billing
* PDF invoice
* Thermal printer support
* A4 invoice support
* Purchase management
* Stock management
* Customer management
* Supplier management
* Expense tracking
* Excel product import
* Basic offline billing with sync later
* Simple reports
* Manual subscription/payment record for admin
* Main admin panel for client and plan management

### Not Included in V1

* AI command entry
* Multi-branch management
* Staff login
* Automated WhatsApp reminders
* Full accounting system
* Payroll
* E-commerce integration
* Advanced CRM
* Manufacturing module

## 7. Customer Mobile App Requirements

## 7.1 Authentication

Shop owners will log in using:

* Email
* Password

V1 will support two onboarding methods:

* Client can sign up themselves
* Admin can create the client account manually from the admin panel

## 7.2 Business Setup

During setup, the shop owner should be able to enter:

* Business name
* Owner name
* Business type
* Phone number
* Email
* Business address
* GST number
* Logo
* Invoice prefix
* Tax preference

## 7.3 Dashboard

The dashboard should show:

* Today’s sales
* Today’s profit
* Total stock value
* Low stock products
* Out-of-stock products
* Customer due amount
* Supplier due amount
* Recent invoices
* Quick action buttons:

  * New Bill
  * Add Product
  * Add Purchase
  * Scan Barcode

## 7.4 Product Management

Users should be able to:

* Add products
* Edit products
* Delete or deactivate products
* Add product image
* Add SKU/product code
* Add barcode
* Add category
* Add brand
* Add unit
* Add purchase price
* Add selling price
* Add MRP
* Add GST percentage
* Add opening stock
* Add low stock alert quantity

## 7.5 Product Variants

V1 must support product variants.

For mobile shops:

* Brand
* Model
* RAM/storage
* Color
* IMEI/serial number
* Warranty period

For garment shops:

* Size
* Color
* Fabric/material
* Gender/category
* Design/code

For hardware shops:

* Unit type
* Weight/length/quantity
* Brand
* Material type
* Bulk pricing support

## 7.6 Excel Product Import

V1 should allow shop owners to upload products in bulk using Excel.

The system should support:

* Downloadable Excel sample format
* Product import
* Error validation
* Duplicate product checking
* Barcode import
* Stock import
* Price import
* GST import

## 7.7 POS / Billing

The POS screen is a must-have V1 feature.

Billing screen should include:

* Product search
* Barcode scan
* Add product to cart
* Quantity update
* Price edit permission for owner
* Discount
* GST calculation
* Customer selection
* Payment mode selection
* Paid, partial, and unpaid billing
* Invoice generation
* Stock deduction after sale

Supported payment modes:

* Cash
* UPI
* Card
* Credit/due
* Partial payment

## 7.8 Invoice Support

V1 should support:

* PDF invoice
* Thermal printer invoice
* A4 invoice
* GST invoice
* Non-GST invoice
* Simple cash memo
* Estimate/quotation

Invoice should include:

* Business name
* Logo
* Address
* GST number
* Invoice number
* Invoice date
* Customer details
* Product details
* Quantity
* Price
* Discount
* GST
* Total amount
* Paid amount
* Due amount
* Payment mode

## 7.9 Barcode Support

V1 must support:

* Mobile camera barcode scanning
* External barcode scanner support

Barcode flow:

1. User scans barcode
2. Product is searched automatically
3. If product exists, it is added to bill
4. If product does not exist, user can add a new product
5. Barcode is saved with the product

## 7.10 Offline Billing

V1 should support basic offline billing.

When internet is unavailable:

* User can create bills
* Bills are saved locally
* Products can be searched from cached data
* Bills are marked as pending sync
* Bills sync when internet returns
* Duplicate invoice number issues should be prevented

Offline support in V1 is only for billing, not the full system.

## 7.11 Stock Management

The system should automatically update stock based on business activity.

Stock should increase when:

* Purchase is added
* Sale return is added
* Manual stock adjustment is made

Stock should decrease when:

* Sale is created
* Purchase return is added
* Damaged/lost stock is recorded
* Manual stock adjustment is made

Stock features:

* Current stock
* Low stock alert
* Out-of-stock alert
* Manual stock adjustment
* Damaged/lost stock entry
* Stock movement history

## 7.12 Purchase Management

Users should be able to:

* Add purchase bills
* Select supplier
* Add purchased products
* Add quantity
* Add purchase price
* Add GST
* Add discount
* Add extra charges
* Mark payment as paid, partial, or unpaid
* Track supplier dues
* Record purchase returns

## 7.13 Customer Management

Users should be able to:

* Add customers
* Save phone number
* Save address
* View purchase history
* View due amount
* Record due payments
* View customer ledger

Automated WhatsApp due reminder is not required in V1.

## 7.14 Supplier Management

Users should be able to:

* Add suppliers
* Save supplier phone number
* Save address
* View purchase history
* Track supplier pending payments
* Record supplier payment
* View supplier ledger

## 7.15 Expense Management

V1 must include expense tracking.

Users should be able to:

* Add daily expenses
* Select expense category
* Add amount
* Add note
* Add date
* View expense report

Example expense categories:

* Rent
* Salary
* Electricity
* Transport
* Packaging
* Repair
* Miscellaneous

## 7.16 Reports

V1 should include simple and useful reports.

Reports required:

* Today sales report
* Monthly sales report
* Product-wise sales report
* Stock report
* Low stock report
* Profit report
* Customer due report
* Supplier due report
* Purchase report
* Expense report
* GST report

Reports should support:

* Date filter
* PDF export
* Excel/CSV export later

## 8. Main Admin Panel Requirements

The main admin panel will be used by the software owner/team.

## 8.1 Admin Dashboard

Admin dashboard should show:

* Total clients
* Active clients
* Trial clients
* Expired clients
* Monthly revenue
* New clients this month
* Plan-wise clients
* Payment status overview

## 8.2 Client Management

Admin should be able to:

* Create client account
* Edit client account
* View business details
* View owner details
* Set business type
* Activate/suspend client
* Assign subscription plan
* Set subscription expiry date
* View client usage

## 8.3 Plan Management

Admin should be able to create and manage plans.

Plan settings may include:

* Plan name
* Monthly price
* Yearly price
* Product limit
* Invoice limit
* Feature access
* Subscription duration
* Custom plan option

## 8.4 Subscription Management

V1 will support manual subscription/payment management.

Admin should be able to:

* Add payment record manually
* Set payment date
* Set renewal date
* Extend subscription
* Mark client as paid/unpaid
* Suspend expired clients
* Add grace period if needed

Online payment gateway is not required in V1.

## 8.5 Feature Control

Admin should be able to enable or disable features per client.

Feature controls:

* GST billing
* Barcode scanning
* Excel import
* Reports
* PDF invoice
* Thermal print
* A4 print
* Offline billing
* Expense module

## 8.6 Support Management

Admin panel should have a simple support system.

Features:

* View client issues
* Change issue status
* Add internal note
* Mark issue as resolved

## 8.7 Audit Logs

The system should track important activities, such as:

* Login activity
* Product created/updated/deleted
* Invoice created
* Stock adjusted
* Purchase added
* Payment updated
* Subscription changed

## 9. User Roles

V1 customer side will mainly support:

### Shop Owner

The shop owner has full access to all customer app features.

Staff login is not required in V1 and can be added later.

### Main Admin

The main admin manages all clients, plans, payments, subscriptions, and feature access.

## 10. Future Scope

After V1, the following features can be added:

* Staff login and permissions
* Multi-branch management
* Automated WhatsApp reminders
* Razorpay payment integration
* AI billing command entry
* Advanced accounting
* Loyalty points
* CRM/follow-up system
* E-commerce integration
* Desktop billing app
* Advanced analytics
* Regional languages: Hindi and Odia

## 11. Success Criteria

V1 will be considered successful if:

* Shop owners can create bills quickly
* Stock updates correctly after sales and purchases
* GST invoices work properly
* Barcode billing works from camera and external scanner
* Offline billing works during internet failure
* Excel product import reduces setup time
* Owners can track dues, purchases, expenses, and reports
* Admin can manage clients, plans, and manual payments
* Product is simple enough for local Odisha shop owners to use without heavy training

## 12. Final V1 Positioning

The product should be positioned as:

**A simple and affordable GST billing, inventory, barcode, and stock management app for Indian mobile shops, garment shops, and hardware shops.**

The first version should focus on speed, simplicity, billing accuracy, stock accuracy, and local shop usability.

































# Product Requirements Document

## Phase 2 — Product + Service Management Module

## 1. Phase 2 Objective

Phase 2 will expand the inventory management system from a simple billing and stock app into a **complete product + service business management system**.

The main goal is to support shops that sell physical products and also provide services, such as:

* Mobile shops that sell phones/accessories and also repair phones
* Electronics shops that sell items and provide repair/service
* Hardware shops that sell materials and provide installation/labor
* Garment shops that sell clothes and provide alteration/stitching services

Phase 2 should help these shops manage service orders, repair jobs, spare parts, labor charges, customer approvals, delivery status, warranty, and final billing.

## 2. Phase 2 Positioning

Phase 2 product positioning:

**A complete billing, inventory, and service management app for Indian shops that sell products and provide repair or service work.**

Example pitch:

“Now you can manage product sales, repair jobs, spare parts, labor charges, customer dues, GST invoices, and service status from one app.”

## 3. Phase 2 Main Modules

Phase 2 should include these major modules:

1. Service Catalog
2. Job Card / Service Order
3. Repair Intake Flow
4. Service Status Tracking
5. Spare Parts Usage
6. Labor Charges
7. Estimate to Invoice Flow
8. Product + Service Combined Billing
9. Advance Payment / Deposit
10. Service Delivery & Closure
11. Warranty Management
12. Service History
13. Party Ledger Upgrade
14. Cashbook
15. Quotation / Estimate Upgrade
16. Purchase Order
17. Delivery Challan
18. Advanced Reports
19. Admin Feature Control for Service Module

## 4. User Types

Phase 2 will mainly support:

### Shop Owner

The shop owner manages products, services, repair jobs, billing, reports, and customer payments.

### Customer

The customer gives a product for repair/service or buys products/services from the shop.

### Technician Name Field

Staff login is not required in Phase 2, but the app should allow the owner to select or type a technician name for repair tracking.

Full staff login and technician accounts can be added in a later phase.

## 5. Service Catalog

The shop owner should be able to create a list of services.

### Service Fields

Each service should include:

* Service name
* Service category
* Service price
* GST/SAC tax setting
* Estimated time
* Warranty period, if applicable
* Description
* Active/inactive status

### Example Services for Mobile Shops

* Display replacement
* Battery replacement
* Charging port repair
* Speaker repair
* Software update
* Data backup
* Tempered glass fitting
* Back cover fitting

### Example Services for Hardware Shops

* Installation charge
* Fitting charge
* Site visit charge
* Cutting charge
* Repair labor
* Delivery charge

### Example Services for Garment Shops

* Alteration
* Stitching
* Size adjustment
* Zip replacement
* Fall/pico service
* Custom fitting

## 6. Job Card / Service Order

The job card is the most important Phase 2 feature.

A job card is created when a customer gives an item for repair or service.

### Job Card Fields

The job card should include:

* Job card number
* Customer name
* Customer phone number
* Customer address
* Device/product/item name
* Brand
* Model
* IMEI/serial number, if applicable
* Problem/issue description
* Item condition at receiving time
* Accessories received
* Photos of item condition
* Estimated repair cost
* Advance payment
* Expected delivery date
* Technician name
* Job status
* Customer note
* Internal note
* Terms and conditions

### Important Privacy Rule

The app should avoid storing customer passwords or phone lock patterns by default. If absolutely required, the field should be optional, masked, and clearly marked as sensitive.

## 7. Repair Intake Flow

The repair/service intake flow should be simple.

### Flow

1. Select or create customer
2. Enter device/item details
3. Add issue/problem
4. Add photos, optional
5. Add estimated cost
6. Add advance payment, optional
7. Select expected delivery date
8. Create job card
9. Print/share job receipt

### Job Receipt Should Include

* Job card number
* Customer details
* Device/item details
* Issue description
* Estimated cost
* Advance paid
* Expected delivery date
* Shop contact details
* Terms and conditions

## 8. Service Status Tracking

Each job card should have a clear status.

### Recommended Statuses

* Received
* Checking
* Estimate Given
* Waiting for Customer Approval
* In Progress
* Waiting for Spare Parts
* Ready for Delivery
* Delivered
* Cancelled
* Returned Without Repair

### Status Features

The shop owner should be able to:

* Update job status
* Add internal note
* Add customer-visible note
* View status history
* Filter jobs by status

## 9. Customer Approval Flow

Some repair jobs need customer approval before work starts.

### Features

* Create estimate
* Mark estimate as approved or rejected
* Add approval date
* Add approval note
* Convert approved estimate into active job
* Convert completed job into invoice

This is useful when repair cost is uncertain.

## 10. Spare Parts Usage

Repair jobs often use spare parts from inventory.

### Features

The owner should be able to add products/spare parts to a job card.

Example:

* Display
* Battery
* Charging port
* Speaker
* Camera module
* Screws
* Wire
* Adapter
* Small hardware parts

### Stock Behavior

When spare parts are used in a job:

* Stock should reduce automatically
* Spare part cost should be added to job cost
* Spare part selling price should be added to customer bill
* Job profit should calculate product margin + service/labor margin

## 11. Labor Charges

The system should support labor/service charges separately from product charges.

### Labor Charge Features

* Add labor charge
* Add technician charge
* Add diagnosis charge
* Add installation charge
* Add service charge
* Add discount
* Apply GST if needed

This allows one bill to include both physical products and services.

## 12. Product + Service Combined Billing

This is a core Phase 2 feature.

The billing system should allow:

* Product-only invoice
* Service-only invoice
* Product + service invoice

### Example Invoice

Customer: Ramesh
Service: Mobile display replacement — ₹500 labor
Product: Samsung A50 display — ₹1,800
GST: As applicable
Total: ₹2,300 + GST

This is important for mobile repairing shops because every repair may include both spare parts and labor.

## 13. Advance Payment / Deposit

Repair shops often collect advance payment.

### Features

* Add advance payment while creating job card
* Show advance in job card
* Deduct advance from final invoice
* Show balance due
* Support cash, UPI, card, and other payment modes

### Example

Estimated repair cost: ₹3,000
Advance paid: ₹500
Final payable: ₹2,500

## 14. Service Delivery & Closure

When the repair or service is complete, the owner should close the job.

### Closure Flow

1. Mark job as ready
2. Generate final bill
3. Apply advance payment
4. Collect remaining payment
5. Mark as delivered
6. Print/share final invoice

### Final Delivery Receipt Should Include

* Job card number
* Invoice number
* Service details
* Parts used
* Labor charges
* Warranty terms
* Paid amount
* Due amount
* Delivery date

## 15. Warranty Management

Warranty is very important for repair shops and mobile shops.

### Warranty Features

* Warranty on product sale
* Warranty on repair/service
* Warranty period
* Warranty start date
* Warranty end date
* Warranty terms
* Warranty claim record
* Search by customer, invoice, IMEI, or serial number

### Example

Display replacement warranty: 30 days
Battery replacement warranty: 3 months
New phone warranty: 1 year company warranty

## 16. Service History

The system should store customer-wise service history.

### Features

* Customer repair history
* Device-wise service history
* IMEI/serial-wise history
* Previous issues
* Previous parts used
* Previous warranty claims
* Previous payments

This is very useful when a customer returns with the same device again.

## 17. IMEI / Serial Number Upgrade

Since mobile shops are one of the first target customers, Phase 2 should strengthen IMEI/serial tracking.

### Features

* Add IMEI/serial number for product sale
* Add IMEI/serial number for repair job
* Search invoice by IMEI
* Search job card by IMEI
* Track warranty by IMEI
* Prevent duplicate IMEI entry

## 18. Estimate / Quotation Upgrade

Phase 2 should improve the estimate feature.

### Features

* Create estimate
* Estimate for products
* Estimate for services
* Estimate for product + service
* Convert estimate to job card
* Convert estimate to invoice
* Estimate status:

  * Draft
  * Sent
  * Approved
  * Rejected
  * Converted

This is useful for hardware, repair, and B2B customers.

## 19. Purchase Order

Phase 2 should include purchase order management.

### Features

* Create purchase order
* Select supplier
* Add required products
* Add expected delivery date
* Mark order as sent
* Convert purchase order to purchase bill
* Track pending quantity

This helps shops order stock before they run out.

## 20. Delivery Challan

Delivery challan should be added in Phase 2 or Phase 2.5.

### Features

* Create delivery challan
* Send goods without final invoice
* Convert challan to invoice
* Track delivered items
* Track pending billing

This is useful for hardware shops and B2B supply customers.

## 21. Party Ledger Upgrade

Customer and supplier ledger should become stronger in Phase 2.

### Features

* Customer opening balance
* Supplier opening balance
* Receivable report
* Payable report
* Payment received
* Payment paid
* Customer statement PDF
* Supplier statement PDF

## 22. Cashbook

Cashbook should be added in Phase 2 because local shops need simple cash tracking.

### Features

* Opening cash
* Cash in
* Cash out
* Closing cash
* Daily cash summary
* Cash sales
* Cash expenses
* Cash received from customer
* Cash paid to supplier

## 23. Advanced Reports

Phase 2 reports should include:

* Service job report
* Pending repair report
* Completed repair report
* Technician-wise job report, without login
* Spare parts used report
* Service profit report
* Product + service sales report
* Warranty report
* Estimate conversion report
* Cashbook report
* Party ledger report
* Purchase order report
* Delivery challan report

## 24. Notifications

V1 does not need automated WhatsApp reminders, but Phase 2 should support basic in-app notifications.

### In-App Notifications

* Job pending
* Job delivery due today
* Waiting for customer approval
* Waiting for spare parts
* Warranty ending soon
* Low stock for spare parts

Manual WhatsApp sharing can be added, but automated WhatsApp reminders should remain a later feature.

## 25. Admin Panel Phase 2 Requirements

The main admin panel should allow the software owner to control Phase 2 features.

### Admin Controls

Admin should be able to enable or disable:

* Service module
* Job card module
* Warranty module
* Purchase order module
* Delivery challan module
* Cashbook module
* Advanced ledger
* Advanced reports

### Plan-Based Feature Control

Example:

Starter Plan:

* Billing
* Inventory
* GST
* Basic reports

Standard Plan:

* Everything in Starter
* Job card
* Service billing
* Warranty
* Cashbook

Pro Plan:

* Everything in Standard
* Purchase order
* Delivery challan
* Advanced reports
* IMEI/serial tracking

## 26. Phase 2 User Flow Example — Mobile Repair Shop

### Scenario

A customer comes to repair a phone display.

### Flow

1. Owner opens “New Job Card”
2. Selects customer or adds new customer
3. Enters device: Samsung A50
4. Adds IMEI/serial number
5. Adds issue: Display broken
6. Adds estimated cost: ₹2,300
7. Adds advance: ₹500
8. Status becomes “Received”
9. Owner adds spare part: Samsung A50 display
10. Stock reduces automatically
11. Owner adds labor charge: ₹500
12. Job status becomes “Ready for Delivery”
13. Final invoice is generated
14. Advance is deducted
15. Customer pays remaining amount
16. Job is marked as “Delivered”
17. Warranty is created for 30 days

## 27. Phase 2 User Flow Example — Hardware Shop

### Scenario

A customer buys plumbing items and also asks for installation.

### Flow

1. Owner creates product + service bill
2. Adds PVC pipe, joints, and fittings
3. Adds installation service charge
4. Adds delivery charge if needed
5. Applies GST
6. Generates invoice
7. Stock reduces automatically
8. Customer pays partial amount
9. Remaining amount goes to customer ledger

## 28. Phase 2 User Flow Example — Garment Shop

### Scenario

A customer buys a pant and requests alteration.

### Flow

1. Owner creates sale invoice
2. Adds pant as product
3. Adds alteration service
4. Adds expected delivery date
5. Marks alteration status as pending
6. When completed, marks as ready
7. Customer collects item
8. Invoice and service history remain saved

## 29. What Should Not Be Added in Phase 2

To avoid overcomplication, do not add these yet:

* Multi-branch
* Full staff login
* Technician mobile app
* Automated WhatsApp messages
* AI billing
* Full accounting like Tally
* Payroll
* E-way bill
* E-invoice
* Loyalty points
* E-commerce integration

These can come in later phases.

## 30. Phase 2 Success Criteria

Phase 2 will be successful if:

* A shop can manage product sales and services in one system
* A mobile repair shop can create job cards and track repair status
* Spare parts used in repair reduce stock automatically
* Labor and product charges can appear in one invoice
* Advance payment can be adjusted in final bill
* Warranty can be tracked by customer, invoice, or IMEI
* Customers’ product purchase and service history are saved
* Shop owners can view pending jobs, completed jobs, and service profit
* Admin can enable or disable service features based on plan

## 31. Final Phase 2 Priority List

Build Phase 2 in this order:

1. Service catalog
2. Job card/service order
3. Product + service billing
4. Advance payment
5. Spare parts usage from inventory
6. Repair/service status tracking
7. Final delivery and job closure
8. Warranty management
9. Service history
10. IMEI/serial tracking upgrade
11. Estimate to job card/invoice
12. Party ledger upgrade
13. Cashbook
14. Purchase order
15. Delivery challan
16. Advanced reports

## 32. Final Recommendation

Phase 2 should not become a full accounting system. It should focus on one clear upgrade:

**Make the app perfect for shops that sell products and also provide services.**

The most important Phase 2 module is:

**Job Card + Product/Spare Parts + Labor Charges + Final Invoice + Warranty.**

This single module can make the product much more valuable for mobile repair shops, electronics shops, hardware shops, and garment alteration shops.

