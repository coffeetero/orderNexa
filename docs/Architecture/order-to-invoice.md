# Order to production, packaging, labels and delivery (spec, draft for approval)

Status: **Phase 1 built locally (branch bps-order-runs); later phases are proposals.** Scope: order entry through delivery confirmation and AR recognition.
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
