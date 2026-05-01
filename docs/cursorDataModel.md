# Cursor Data Model

Purpose: explain the `bps` data model in plain English so developers can understand structure and relationships without reading SQL.

> Assumption note: most schema scripts create tables with unqualified names and rely on `search_path` (intended `bps, public`). This document treats those objects as `bps` tables. One table (`bps.fnd_contacts`) is explicitly schema-qualified in SQL.

---

## 1) Table Overview (Grouped)

## Foundation / Multi-tenant Core

- `fnd_tenants`: tenant master; defines each business tenant and tenant-level flags (including audit enablement).
- `fnd_users`: application users tied to auth identities and scoped to a tenant.
- `fnd_user_tenants`: user-to-tenant membership bridge (many-to-many), including whether customer access is restricted.
- `fnd_user_customers`: optional user-to-customer access bridge for restricted users.
- `fnd_customers`: customer master per tenant, including hierarchical parent-child customer structure.
- `fnd_audit_log`: centralized change history table populated by audit triggers.
- `fnd_currencies`: global ISO currency catalog used by price books.

## Contacts / People

- `fnd_people`: person/contact identity records within a tenant.
- `fnd_contact_points`: links people to entities and contact labels/primary flags.
- `fnd_contacts`: alternate/legacy contact master table (explicitly created as `bps.fnd_contacts`).

## Product / Catalog / Pricing

- `fnd_items`: generic item catalog (tenant scoped).
- `bps_items`: bakery-specific 1:1 extension of `fnd_items`.
- `fnd_item_bom`: bill-of-materials/recipe structure linking parent items to component items.
- `fnd_pricebooks`: named price lists per tenant.
- `fnd_pricebook_items`: item-level prices inside each price book.
- `fnd_customer_pricebooks`: customer-to-pricebook assignments with effective dates and assignment type.

## Order Management (`om_`)

- `om_orders`: sales order headers.
- `om_order_lines`: line items within orders.
- `om_order_shipments`: shipment/fulfillment events (append-only event-style records).

## Accounts Receivable (`ar_`)

- `ar_transactions`: receivable document headers (invoices, credits, etc.).
- `ar_transaction_lines`: line-level detail for AR documents.
- `ar_payments`: payment headers (cash/check/ACH/etc.).
- `ar_payment_applications`: applies payments to AR transactions (supports partial application over time).

---

## 2) Key Tables (Detailed)

## `fnd_tenants`

What it represents:
- The top-level business boundary for almost all transactional data.

Important columns:
- `tenant_id` (PK): tenant identity key.
- `tenant_name`: display/business name.
- `plan`: tenant plan tier (`STARTER`, `PRO`, `ENTERPRISE`).
- `is_active`: soft active flag.
- `is_audit_log_enabled`: enables/disables tenant-level audit writes.

How it is used:
- Most tables carry `tenant_id` and point back to `fnd_tenants`.
- Tenant scoping and RLS behavior are anchored on this ID.

---

## `fnd_users`

What it represents:
- Application users with tenant context and auth linkage.

Important columns:
- `user_id` (PK): internal app user identifier.
- `tenant_id` (FK to `fnd_tenants`): default tenant context for the user row.
- `auth_user_id` (UUID): maps to auth identity.
- `is_active`, `deleted_at`: lifecycle flags.
- `can_debug`: permission-style flag for debug tooling.

How it is used:
- User context resolution in RPC/functions.
- Relationship source for user-tenant membership and customer access control.

---

## `fnd_customers`

What it represents:
- Tenant-scoped customer master, including account/site/location hierarchy.

Important columns:
- `customer_id` (PK): internal customer identity.
- `tenant_id` (FK to `fnd_tenants`): tenant partition key.
- `customer_parent_id` (self-FK): hierarchical parent.
- `customer_name`, `customer_number`, `customer_type`: core business identity.
- Operational flags (examples): `is_active`, `is_standing_order`, `is_returns_allowed`, invoice/cost display flags.
- `legacy_id`: legacy-system mapping field.

How it is used:
- Customer selection, order ownership, AR ownership.
- Hierarchical UIs (parent-child display/selection).

---

## `om_orders`

What it represents:
- Sales order header records.

Important columns:
- `order_id` (PK).
- `tenant_id` (FK to `fnd_tenants`).
- `customer_id` (FK to `fnd_customers`, nullable for some legacy cases).
- `order_number` (unique per tenant).
- `order_date`, `delivery_date`, `delivery_window`.
- Financial rollup fields: `quantity`, `amount`, `discount_amount`.
- `snapshot_data` (JSONB): captured context from source flow.

How it is used:
- Parent record for order lines and shipment events.
- Main operational record for order lifecycle.

---

## `om_order_lines`

What it represents:
- Product-level rows belonging to an order.

Important columns:
- `order_line_id` (PK).
- `order_id` (FK to `om_orders`).
- `item_id` (FK to `fnd_items`, nullable).
- `quantity`, `unit_price`, `extended_amount`, `unit_discount`.
- `fulfilled_quantity`: fulfillment accumulation field.
- `tenant_id` for scoping.

How it is used:
- Drives fulfillment/shipment and downstream AR line generation.

---

## `ar_payments`

What it represents:
- Payment receipts from customers.

Important columns:
- `ar_payment_id` (PK).
- `tenant_id` (FK), `customer_id` (FK).
- `payment_date`, `amount`.
- `payment_method`, `payment_number`, `reference_number`.
- `legacy_ar_trn_id` for legacy linkage.

How it is used:
- Payment headers are later applied to invoices/documents via `ar_payment_applications`.

---

## `ar_transactions`

What it represents:
- Accounts receivable document headers (invoice/credit/etc.).

Important columns:
- `ar_transaction_id` (PK).
- `tenant_id`, `customer_id` (FKs).
- `transaction_type`, `document_number`, `transaction_date`, `due_date`.
- `amount` and `status` (`OPEN`, `PARTIAL`, `CLOSED`, `CANCELLED`).

How it is used:
- Financial document anchor for AR lines and payment applications.

---

## 3) Relationships (Plain English)

## Core one-to-many

- A tenant has many users (`fnd_tenants` -> `fnd_users`).
- A tenant has many customers (`fnd_tenants` -> `fnd_customers`).
- A tenant has many orders (`fnd_tenants` -> `om_orders`).
- A customer has many orders (`fnd_customers` -> `om_orders`).
- An order has many order lines (`om_orders` -> `om_order_lines`).
- An order (or line) can have many shipment events (`om_orders`/`om_order_lines` -> `om_order_shipments`).
- A customer has many AR transactions (`fnd_customers` -> `ar_transactions`).
- A customer has many payments (`fnd_customers` -> `ar_payments`).
- A payment can be applied in many pieces (`ar_payments` -> `ar_payment_applications`).
- An AR transaction can receive many applications (`ar_transactions` -> `ar_payment_applications`).

## Many-to-many via link tables

- Users to tenants: `fnd_user_tenants`.
  - Meaning: a user can access 0..N tenants; a tenant can have 0..N users.
- Users to customers (within tenant): `fnd_user_customers`.
  - Meaning: when user access is customer-restricted, this table grants customer-level permissions.
- Customers to pricebooks: `fnd_customer_pricebooks`.
  - Meaning: customer pricing is assigned through dated associations, not direct price columns on customer.

## Product/pricing relationships

- An item can have one bakery extension row (`fnd_items` <-> `bps_items`, effectively 1:1).
- A pricebook has many price rows (`fnd_pricebooks` -> `fnd_pricebook_items`).
- An item can appear in many pricebooks (through `fnd_pricebook_items`).
- A parent item can have many BOM component rows (`fnd_item_bom` self-references `fnd_items`).

---

## 4) Hierarchies

## Customer hierarchy (`fnd_customers.customer_parent_id`)

- Customers can form a tree (for example: account -> site -> location).
- Root customers have `customer_parent_id = NULL`.
- Child customers reference a parent `customer_id` in the same table.
- This hierarchy is used by customer picker/navigation flows and for structured customer management.

## Item composition hierarchy (`fnd_item_bom`)

- `fnd_item_bom` stores parent-item to component-item links.
- Each row describes one component quantity in a recipe/BOM.
- This models production composition rather than customer/account structure.

---

## 5) Data Flow (Business Level)

## Tenant -> Customer -> Order -> Payment flow

1. Tenant context is established (`fnd_tenants`, user memberships).
2. Customers are maintained per tenant (`fnd_customers`), optionally in hierarchy.
3. Orders are created for customers (`om_orders` + `om_order_lines`).
4. Fulfillment events are tracked (`om_order_shipments`).
5. AR documents are stored (`ar_transactions` + optional `ar_transaction_lines`).
6. Payments are received (`ar_payments`).
7. Payments are applied to AR documents (`ar_payment_applications`), enabling partial and multi-step settlement.

## Pricing side flow

1. Items are defined (`fnd_items`) and optionally extended (`bps_items`).
2. Pricebooks are defined (`fnd_pricebooks`).
3. Price rows are defined per item (`fnd_pricebook_items`).
4. Pricebooks are assigned to customers with effective dates (`fnd_customer_pricebooks`).

---

## 6) Security Context (High Level)

- `tenant_id` is the primary data-partition key across business tables.
- Access control is tenant-first: users are associated to tenants through `fnd_user_tenants`.
- For users flagged as customer-restricted, `fnd_user_customers` further narrows accessible customers.
- RLS policies (defined per table) enforce tenant/customer scoping at query time.
- Audit capture is centralized in `fnd_audit_log`, with tenant-aware filtering/visibility.

---

## 7) Naming Patterns

- `fnd_`: foundation/shared domain entities (tenants, users, customers, items, currencies, audit, mappings).
- `om_`: order management domain (orders, order lines, shipments).
- `ar_`: accounts receivable domain (AR documents, payments, applications, AR lines).
- `bps_`: bakery/business-specific extensions layered on foundation tables (example: `bps_items`).

---

## Quick Mental Model

- Think of `fnd_tenants` as the top boundary.
- `fnd_users` + `fnd_user_tenants` + `fnd_user_customers` define who can see what.
- `fnd_customers` defines who business is done with.
- `om_*` tracks what was ordered and shipped.
- `ar_*` tracks what was billed and paid.
- `fnd_*`/`bps_*` product + pricing tables determine what can be sold and at what price.
