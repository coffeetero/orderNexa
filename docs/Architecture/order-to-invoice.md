# Order to production, packaging, labels and delivery (spec, draft for approval)

Status: **Phases 1-4 built locally** (Phase 1 on branch bps-order-runs; Phases 2-4 on bps-order-to-invoice). Nothing is applied to the cloud. Scope: order entry through delivery confirmation and AR recognition.
Out of scope: standing orders, inventory (usage, spoilage, consumables), payments.

## Flow

```
Order entry ──► cutoff_at ──► Process run ──► print Baker's Sheet / Packaging / Labels / Delivery ──► ship ──► AR
om_orders       run LOCKED    drafts built      each print is its own action                         confirm   recognised
```

One layer per job; each points back at the previous one and never edits it.

| Layer | Tables | Owns |
|---|---|---|
| Demand | `om_orders`, `om_order_lines` | what customers asked for |
| Production | `om_production_runs` (new) | a production date + code, its cutoff, print times |
| Fulfilment | `om_shipments` (new header), `om_shipment_lines` (renamed from `om_order_shipments`) | how and when goods physically move |
| Billing | `ar_transactions`, `ar_transaction_lines` | the invoice and what counts as owed |

## Customer roles (from the existing tree)

`fnd_customers.customer_type` is ACCOUNT, DEPARTMENT or SITE, linked by `customer_parent_id`. No new tables.

| Type | Orders | Invoice | Statement |
|---|---|---|---|
| ACCOUNT | yes | always | always |
| DEPARTMENT | yes | only if `is_invoice_required` | never (a paying department becomes an ACCOUNT) |
| SITE | yes | never | never |

- **Invoice owner** of an order = nearest ancestor-or-self that is an ACCOUNT or an invoiced DEPARTMENT.
- **Statement owner** = nearest ACCOUNT ancestor-or-self.
- Orders keep the ordering site or department as `customer_id`; the invoice's `customer_id` is the owner.

## Schema changes

All tables involved are empty or tiny in the local data (0 shipments, 0 AR, 5 orders), so restructuring is cheap now.

**New**
- `om_production_runs`: `production_run_id`, `tenant_id`, `production_date`, `production_code`, `delivery_date`, `cutoff_at`, `status` (OPEN, LOCKED, PROCESSED, CLOSED), `processed_at/by`, `baker_sheet_printed_at`, `packaging_printed_at`, `labels_printed_at`, `delivery_printed_at`, audit columns. Unique on (`tenant_id`, `production_date`, `production_code`).
- `om_production_codes` (per-tenant settings for the existing `PRODUCTIONCODE` valueset: MORNING, LUNCH, DINNER, SPECIAL1, SPECIAL2): `tenant_id`, `production_code`, `cutoff_time`, `cutoff_days_before`, `delivery_days_after`, `is_active`.
- `om_delivery_methods` (table-driven per tenant): `tenant_id`, `delivery_method_code`, `name`, `is_own_fleet`, `requires_tracking`, `is_active`. Examples: OWN_TRUCK, CARRIER, COURIER, PICKUP.
- `om_shipments` (header): `shipment_id`, `tenant_id`, `production_run_id`, `ship_to_customer_id`, `delivery_date`, `delivery_method_code`, `carrier`, `tracking_reference`, `route`, `delivery_cost`, `status` (PLANNED, SHIPPED, DELIVERED, CANCELLED), `shipped_at/by`.

**Changed**
- `om_order_shipments` becomes `om_shipment_lines`: add `shipment_id`; drop the per-line columns that move to the header (`delivery_type`, `delivery_reference`, `ship_*_location_id`, `production_*`).
- `om_orders`: add `production_run_id` (found or created on first order for a date + code). `production_date` and `production_code` stay.
- `fnd_customers`: add `cutoff_extra_minutes` and `delivery_method_code`. Both inherit down the tree (nearest ancestor-or-self with a value).
- `om_orders`: also `delivery_charge` NUMERIC(12,2) NOT NULL DEFAULT 0, entered with the order (always starts at 0).
- `ar_transactions`: add `production_run_id`; status DRAFT, ISSUED, VOID; unique on (owner, run, type INV).
- `ar_transaction_lines`: `order_shipment_id` becomes `shipment_line_id`; `source_type` gains DELIVERY_CHARGE (no item, no shipment line).
- `fnd_tenant_sequences`: new `invoice_number` sequence per tenant (`requires_gapless` per tenant).
- Tenant option `ar_recognition`: SHIPMENT (default) or INVOICE (for COD-style tenants). Location to decide (column on `fnd_tenants`).

**Dropped idea:** `fnd_customer_departments` (the existing hierarchy covers it) and a per-order production table (a run plus a report query covers it).

## Statuses

| Object | Flow | Rule |
|---|---|---|
| Run | OPEN, LOCKED, PROCESSED, CLOSED | LOCKED at `cutoff_at` (customers cannot enter or change). PROCESSED by "Process run". CLOSED by staff once deliveries are confirmed. |
| Invoice | DRAFT, ISSUED, VOID | Number assigned at the first **Packaging** print (the invoice) and locked from then on. Later edits update the same invoice and reprint with the same number. Gapless tenants void and reissue instead; voided rows are never deleted. |
| Shipment | PLANNED, SHIPPED, DELIVERED, CANCELLED | Created PLANNED at processing. SHIPPED confirms actual quantities. |

## Cutoff

- `cutoff_at` is computed when the run is created from `om_production_codes`, and can be edited per run (holidays, special runs).
- A customer's effective cutoff is `cutoff_at` plus their inherited `cutoff_extra_minutes`.
- Enforced in the order save function and API for customer callers; staff are exempt.
- Staff changes after the cutoff flow to invoice drafts and labels; the Baker's Sheet shows "changed since print" (orders updated after `baker_sheet_printed_at`) so the bakery decides whether to reprint.

## Process run (one function, idempotent until Packaging is printed)

1. Require run status LOCKED (or OPEN with staff override); set PROCESSED.
2. For each order, resolve the invoice owner; create or update one DRAFT invoice per (owner, run) with lines grouped by ordering site or department and order number.
3. Create shipments per (run, ordering customer, delivery method) with PLANNED lines. The delivery method comes from the customer default (inherited).
4. No printing, no numbering, no AR effect.

## Reports (four separate prints, each stamps its `*_printed_at`)

- **Baker's Sheet:** run totals by item, grouped by category and dough.
- **Packaging:** one invoice per page group, listing each ordering site or department and order number. Assigns and locks invoice numbers on first print.
- **Labels:** per order line or site, showing customer, site, order number, item and quantity (no invoice number).
- **Delivery:** OWN_FLEET shipments for the delivery date, by route and stop, with invoice numbers.

## Shipping and AR

- Delivery confirmation sets shipped quantities and, for carrier or courier shipments, the reference and cost.
- Cost and charge are separate: `delivery_cost` is what the bakery pays (a UPS bill, an Uber fare) and may be empty for own-truck runs; the charge billed to the customer is `om_orders.delivery_charge`, entered with the order.
- A non-zero order delivery charge is added to the invoice as a DELIVERY_CHARGE line.
- With `ar_recognition = SHIPMENT`, an invoice line counts toward the customer's balance once its shipment is SHIPPED. Mixed shipments therefore recognise line by line. With INVOICE, it counts from ISSUED.
- Shortages found later (for example "missing 14 rolls") are corrected by a credit memo that references the invoice line. Staff find the invoice or order by entering either number.

## Build phases (each verified before the next)

Rule: every computation (dates, cutoffs, totals, validation) lives in `bps.*` database functions; the API and website only pass inputs and display results.

1. Schema, production code and delivery method settings, run creation on demand, cutoff enforcement. Verify: SQL tests and unit tests for cutoff and role resolution.
2. Process run function, invoice drafts, planned shipments. Verify: SQL tests including the Chase example (account, department, sites).
3. The four reports. Verify: print views checked in the browser at 1920x1080 and iPad widths.
4. Delivery confirmation, delivery charge, AR recognition, credit memo link, lookup by invoice or order number.

## Open items

- COD-style tenants: does `ar_recognition = INVOICE` cover them, or is "at order entry" a third option?
- Where tenant-level options live (`fnd_tenants` column or a settings table).
- Print technology: HTML print pages through the browser (assumed).

## As built (differences and decisions recorded during the build)

- **Customer types:** an ACCOUNT or DEPARTMENT order is stored under that customer's own `customer_id` (own order number).
  Only a SITE order is stored under its parent customer, with the site name as the default `department_event` (overridable).
  `department_event` now defaults to the selected customer's own name (the old `ORDER` default is gone).
  Invoice owner = nearest ancestor-or-self that is an ACCOUNT or a DEPARTMENT with `is_invoice_required`.
  The statement owner is the nearest ACCOUNT; `ar_customer_balance_get` rolls up everything beneath a paying customer
  that is not itself an ACCOUNT.
- **Statuses:** ar_transactions uses the existing OPEN/PARTIAL/CLOSED/CANCELLED plus DRAFT (no number yet); CANCELLED is void.
  A DRAFT invoice is numbered (`invoice_number` sequence) and becomes OPEN at the first Packaging print.
- **Process run:** `om_production_runs_process` (Production > Process Run). Re-runnable until a delivery has shipped.
  Zero-quantity order lines are neither shipped nor billed.
- **Reports** (PDF, `pdf-lib`): Baker's Report, Packing Labels (4"x2"), Packaging List (invoice, one page set per copy in
  `fnd_customers.invoice_copy_count`), Route Delivery Report (own-fleet only). Run pickers use a from/to production date and
  code; Labels and Packaging list customers with unchecked boxes and a select-all header. `is_cost_on_invoice` is not used:
  every customer's invoice shows prices. Printing stamps `*_printed_at` on the runs.
- **Delivery confirmation** (Production > Confirm Deliveries): shipped quantities per line (default planned, never above
  planned), carrier/tracking/route/cost; carrier methods need tracking. Rolls up to `om_order_lines.fulfilled_quantity`.
- **AR recognition:** a line counts toward the balance at shipped quantity x unit price once its shipment is SHIPPED or
  DELIVERED; the delivery-charge line counts once any item of that order shipped. The invoice document itself is not
  changed after printing.
- **Credits** (Financials > Enter Credits): lookup by invoice or order number; a numbered CM document (`credit_memo_number`)
  with negative ADJUSTMENT lines, capped at the delivered quantity less earlier credits.
- **Numbering settings:** order, invoice, shipment and credit memo sequences are editable in Admin > Application Settings.
- **Not done:** customer-portal ordering UI, standing-order rework, COD recognition at order entry, emailing or texting
  invoices, dot-matrix output formats, inventory/spoilage, statements, and the cloud migrations.

## Pricing books
A customer account is assigned one or more pricing books (`fnd_customer_pricebooks`: type Default / Seasonal / Promotional / Introductory, from/to dates, active flag, status Draft / Pending Approval / Approved / Archived, and a precedence that is the table order on the customer's Pricing tab). An assignment prices an order only when it is active, Approved, its book is active and the order's **delivery date** (production date + the production code's delivery days) is inside its dates. Eligible books are tried in precedence order, item by item (`fnd_item_prices_map`): an item missing from the first book falls through to the next. Only a user with Approve rights on pricing may set an assignment to Approved (trigger guard).
- Order entry (`om_items_get_v2`) returns each item's price and `in_pricebook`; staff adding an item no book prices are asked "Item does not exist ... add anyway?", then type a price or leave 0 (the line is saved with `is_unpriced = true`). `om_orders_save` enforces the same for customer users: an unpriced item is rejected and prices cannot be changed (a customer's unchanged existing line keeps the price it was entered with).
- A book can be made for one customer (`fnd_pricebooks.owner_customer_id`) and still be assigned to other accounts. Books are managed at Inventory > Pricing Books; assignment stays on the Customer Pricing tab, which warns when a Default above a seasonal/promotional/introductory book will win by its order.
- The dashboard To-Do's card (`fnd_todos_get`, approvers only) lists assignments that start within 14 days (or have started) but are not yet active and Approved.
- Quantity price breaks (`min_quantity`) are not applied yet. Migration: `add_pricing_books.sql` (after `add_dashboard_cards.sql`); test: `database/tests/pricing_books_test.sql`.

### Pricing book status, dates and disabling (add_pricebook_status_and_disable.sql)
- A book has its own status (Draft, Scheduled, Approved), From/To dates, notes, creator and approver. Status is informational for now; pricing still uses the book's Active flag and the assignment's own status and dates. New assignments on the customer Pricing tab default to the book's dates and may be overridden.
- Only a pricing approver can set a book to Approved (the approver and time are recorded). Disabling a book records who and when; enabling clears it.
- Copy As New is a screen action: it opens a new unsaved book with the items and prices, status Draft, not active.
- `fnd_pricebooks.last_used_date` is the latest production date of an order by a customer the book is assigned to (sites and departments count toward their account). It is stored and refreshed by `fnd_pricebooks_last_used_refresh(tenant)`, meant for the nightly health check, so the list never scans orders.
- Company setting `fnd_tenants.pricebook_unused_years` (Application Settings > Pricing) is read by the future "book not used" health check (docs/backlog.md).
