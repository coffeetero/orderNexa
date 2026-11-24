# Backlog

## 1. Health Checks (daily consistency checker)

Status: first release built (see docs/Architecture/health-checks.md): two tables, 11 checks, runner, Health Checks page, heart icon, nightly function for pg_cron. Still to do: notifications (email/text by role) and the Troubleshooter roles, the Production Run block on open Errors, customer-side findings, the remaining checks (banking/credit card, invoice vs shipment lines, overlapping approved books, production codes without delivery days). The design below is the original; the new column names on fnd_roles were not added.

### Scheduling
- `pg_cron` 1.6.4 and `pg_net` are available in the Supabase database but not installed (`CREATE EXTENSION pg_cron`).
- One hourly job calls the runner. The runner picks companies where it is 00:xx in the company time zone and no scheduled run has happened that local day.
- Cloud: enable the extension and create the job there. Locally, test by calling the runner directly.

### Tables (2)
1. `fnd_health_checks`: one row per company per check, seeded from the check list.
   - `tenant_id`, `check_code`, `name`, `category` (Setup / Data), `description`, `runs_before_production`, `is_enabled`, `last_run_at`, `last_warnings`, `last_errors`.
2. `fnd_health_log`: one row per finding, `type` column = Information / Warning / Error.
   - `log_id`, `tenant_id`, `check_code`, `type`, `trigger` (Scheduled / Manual / Production Run), `found_at`, `findings` (what is wrong), `remediation` (how to fix), `record_type`, `record_id`, `customer_id` (nullable, for scope), `fixed_at`, `fixed_by`.
   - A re-run that no longer finds an item closes it (`fixed_at` set, `fixed_by` null = fixed automatically). A person can also mark it fixed.

### Roles and notification
- New roles: **Data Troubleshooter**, **Setup Troubleshooter**. Everyone holding the role is notified.
- Proposed new columns on `fnd_roles`: `notify_email`, `notify_sms` (the role decides the channels).
- New areas: `admin.health` (view, run, enable) and `portal.health` (customer users, own accounts only).
- Email and text need a sender, so the first release is in-app only; same role flags used later.

### Behavior
- Heart icon in the top bar: grey = never run, green = clean, yellow = warnings only, red blinking = errors.
- Click opens a Health card on the dashboard.
- Admin → Health Checks page: Enabled checkbox, Check, Last run, Warnings, Errors, Run button; Run all at top; grouped Setup / Data; badge on checks that run before a Production Run.
- Only an admin can disable a check (checker logic bug or slowness).
- Production Run reads the log: any open Error from a `runs_before_production` check blocks the run until fixed (re-run clears it). Warnings do not block.
- Customer users see findings for their own accounts.
- Computations in database functions, one per check; a new check is one function plus one catalog entry.

### Severity examples
- Information: shown on the dashboard, never changes the heart colour. A finding can be one summary row with a count and a link, e.g. "Found 3 Price Books not used in over 2 years" linking to the Pricing Books page (Stale filter).
- Error: order entered for a customer with no pricing book.
- Warning: customer with no contact information.

### Starter checks
- Orders: missing price, customer or delivery date.
- Pricing: no Default book assigned; overlapping approved books.
- Users: user with no role.
- Production: production codes without delivery days.
- Invoices: lines that do not match shipments.
- Payments: applied for more than the invoice.
- Customers: no account owner.
- Contacts: no contact information, no billing contact.
- Addresses: missing or incomplete bill-to or ship-to.
- Banking / credit card: payment method missing, expired or incomplete.

## 2. To be fixed log

### Pricing Books page (done except the health check)
- Title "Pricing Books" at the top of the list.
- Below it a checkbox "Include Disabled". Default shows active books only; disabled books are shown shaded when checked (so similar names can be compared).
- Track when and who disabled a book (proposed new columns `fnd_pricebooks.disabled_at`, `disabled_by`; need approval).
- Buttons: "+ New" always; "Copy As New" enabled only when a book is selected.
- Items grouped by category.

### Health check (links to item 1)
- Pricing: nightly, `fnd_pricebooks_last_used_refresh(tenant)` refreshes `fnd_pricebooks.last_used_date` (already built; call it from the health check), then an Information finding reports books not used in over N years (company setting) with a link to the Pricing Books page.

## 3. Migration from other systems (idea, not designed)
- Alpine Bakery: keep the current design (data pump from SQL Anywhere into the unprefixed legacy tables, then Python/SQL conversion; incremental pump with a state table and a re-check window). The legacy tables and the pump role are dropped before production.
- Other customers: no per-customer legacy tables in the database. Extract from their system into a SQLite staging file, convert there into one unified import package (canonical customers, items, prices, orders, lines, invoices, payments), then import through an API that validates, reports errors and upserts by external IDs.
- Open questions:
  1. Package format: the SQLite file itself, or a zip of JSON/CSV files per entity (SQLite is easy to inspect; JSON streams better into an API).
  2. Who runs the import: us, or customers through an upload page.
  3. Repeatable deltas like Alpine, or a one-time cutover.
  4. Entities in scope at launch: orders and invoices, or only setup data (customers, items, prices).
- Alpine incremental pump, open questions: modified-date columns in ordr, ordr_detail, ar, pmt_detail; re-check window (days) and how the old system cancels or deletes orders; conflict rule when a synced order is edited in the new app during UAT; whether conversion runs automatically after each pump or by a person.

## 4. Order-level shipping and migration follow-ups
- Decision: an order is one delivery (one method, shipped or not). `om_orders` carries `delivery_method_code`, `shipped_at/by`, `carrier`, `tracking_reference`, `delivery_cost`; `ar_transaction_lines.order_id` links an invoice line to its order. Items needing another method (frozen, UPS) go on their own order, so AR is not held back by a late shipment. Item default delivery method (`fnd_items`) and the order-entry split are still to build.
- Rework still pending because it reads the shipment tables: `om_production_run_process`, `om_shipment_confirm`, `om_shipments_get`, `om_report_delivery_get`, `om_invoices_get` (already references a dropped table), `ar_credit_memo_create` cap, the Deliveries page, their SQL tests. Then drop `om_shipments`, `om_shipment_lines` and `ar_transaction_lines.shipment_line_id`.
- Partial fulfilment (later): split the order line. Add a fulfilled column, mark the first row fulfilled and insert a new line for the unfulfilled quantity. No backorder table.
- Roles refactor: `fnd_roles.owner_customer_id` causes `TRUNCATE fnd_customers CASCADE` to wipe roles, role access and user roles. Move customer ownership into a table `fnd_customer_roles` and update the 7 functions, 5 policies, tests and the Roles page that use the column.
- Migration: seeds still truncate or delete. Split a one-time reset step from the migration, make every seed an upsert by legacy id, then run the incremental pump without truncates.
- Migration data to check: 106 invoices whose line total differs from the header (largest 567.08); 7 of 1,296 legacy payments not migrated; 16,193 invoices have no loaded orders (single total line).

### Migration reconciliation: items for the Alpine manager (found 2026-11-23, window 2025-01-01; recheck after the wider window)
- 9 invoices whose order detail lines differ from the order and AR amount: 523935, 525168, 525881, 525882 (looks swapped with 525881), 526310, 533169, 535715, 545814, and 523128 (AR is 65.00 above the order, explained by the -65.00 allowance). Also 524048: the AR row has no amount.
- 21 invoices over-applied in `pmt_detail` (a second payment applied to an invoice already paid, for example 532679 and 529782). The old balance ignores the excess. Decision pending: cap the application at the invoice's open amount, leave the excess as an unapplied payment (customer credit), and list the invoices.
- 4 AR invoices with money and no orders in the window: 523738 (65.00), 524235 (183.00), 526050 (allowance -171.60), 527555 (allowance -4.60). Check again with the earlier window.
- 7 payments dated 2031 and 2043 (customers 330, 183, 526, 226, 159, 311, 445, total 5,598.70) and one 2039 invoice (10262, 0.00) are skipped by the future-date cutoff. They have no application rows in the loaded data.
- 16,188 AR invoices with no orders and an amount of 0 or blank are not worth migrating (to filter out).
- Reconciled so far (old open balance vs new): AR&C Bakery Dist matches exactly. The Harvard Club differs by 86.86 (the swapped pair). Hoboken, Bel Pane, Healthy Bakery and Healthy Bakery NYC differ because of over-applied payments and window edges.

### AR: replace the negative payment application with textbook credit application (decided 2026-11-23)
- For the conversion, a payment that nets a credit is stored as a negative `ar_payment_applications.applied_amount` (check changed from `> 0` to `<> 0`, `relax_ar_payment_application_sign.sql`). Balances equal the old system, but this is not textbook accounting. Example: payment 45875 (1,508.47) applies 1,719.67 to invoices and nets credit invoice 532260 (-211.20) as a -211.20 application.
- Textbook: cash applies to invoices only; a credit memo applies to an invoice through a credit application, never as negative cash. The old data does not say which invoice the credit reduced, so history cannot be converted that way without guessing.
- To do: a credit application concept (credit memo to invoice, with amount and date), a rule to restore the check `applied_amount > 0`, and a one-time clean-up of the negative rows with Alpine's accountant. The negative rows are the only ones below zero today (1 row), so they are easy to find.
- Same section: the 21 over-applied invoices (second payment on an invoice already paid) stay as in the old data until the manager reviews them.

### Full-history reconciliation (pump since 2000-01-01, 2026-11-23): items for the Alpine manager
- Invoices: 530,305 migrated; amounts agree 100% with the old amount due (old amount + invoice discount + allowance + terms discount). Open balance agrees for 99.89%. The 592 that differ: 262 over-applied (payments applied above the invoice, net -103,857.77), 329 closed in the old system (balance 0) with no payment application (317 have none at all; 2000 to 2019, 56 customers, total about 33,500), 1 not shipped yet (405.90).
- AR for customers that are not in the customer table: 481 invoices (38,560.97) and 12 payments (customer 165 for 10 payments in 2001 and 2002, and customer 0 for a pair of 10.10 entries). Not migrated; the customers were probably deleted.
- Payments: 43,513 of 43,897 migrated. Amounts, application counts and applied amounts agree 100%. Skipped: 372 zero-amount and the 12 above.
- Pump: `index_legacy_tables.sql` now runs first in seed_all.py (legacy tables have no indexes). Migration of the full history runs in about 2 minutes.
- To check next: speed of the app's AR reports on 530,000 invoices (`ar_sales_report_get`, `ar_report_open_items`, `ar_customer_balance_get` call `ar_invoice_recognized_amount` per invoice).

## 5. Import Orders follow-ups (built 2026-11-24)
- Aggregator customers: the same import from the customer portal (an aggregator uploads hundreds of orders for its own customers). The import tables already hold the account; needs a portal page, a customer-side area and row security for portal users.
- Approve is blocked while any row has an error; the fix is to correct the file and upload again (it replaces the unapproved import). Consider "approve without the rows that have errors" if staff ask for it.
- `database/functions/om_items_get_v2.sql` is out of date: the deployed function takes production date and code and prices through `fnd_item_prices_map`. Refresh the file from the database.
- Excel files: accept `.xlsx` (not old `.xls`) besides CSV. Use ExcelJS loaded only when an `.xlsx` is picked; read the first sheet's first four columns as displayed text (keeps leading zeros) into the same rows as the CSV reader, so the database checks are unchanged. Unit tests with an in-memory workbook; test with a real customer file.
- Migration files old department orders under the account (department_event "ORDER #..."), while the old data has them under the department (e.g. 15702). Imports create them under the department, so the same customer's history and new orders are filed differently.

## 6. Resellers and default events (agreed 2026-11-24, not built)
- `fnd_customers.is_reseller` (boolean, default false). Resellers (e.g. Featherstone 15700) send their own customer codes.
- Reseller import: every row goes to the account; the reseller's code becomes the order's event as sent (no counter). A code not seen in the last 2 months gets the warning "possible new customer"; no department is created. Non-resellers: the customer number must exist (as today).
- Warnings over the last 2 months, per account + event: item not normally ordered; quantity above 2x the average.
- Corrections: an order is keyed by account + production date + code + event; a new file replaces that order's lines. The latest wins over a phone order (warning "replaced a phone order"). A corrected order goes back to waiting for approval. Open: is a correction file the whole day (missing code = delete) or only changes? Ask the client.
- Default event per customer (account or department), e.g. "Customer-###": `###` is a counter for that customer within the production date/code, so the invoice separates the orders; staff can overwrite it. Must be unique within the customer hierarchy. A department without its own default falls back to its own name (not the account's default, which would repeat the counter). Replaces pseudo "ORDER" departments and dummy walk-in customers. Column: `fnd_customers.default_department_event` (approved).
- Migration: event = the department's real name/code without the "#order" suffix; when two departments share a name in one slot, name + department number (e.g. "BEO 15702"); departments named "ORDER" take the account's default event. Orders stay under the account, so AR and statements are unchanged. Old BPS check: a department never had two orders in one slot; 10,016 slots had different departments with the same name (7,718 "ORDER").
- No `external_customer_number` for now (maybe later, for reseller customers set up as departments).
- Build order: (1) `is_reseller` and the import changes; (2) default event in Order Entry; (3) migration fix, reload, check Featherstone's events; (4) the 2-month warnings (need the corrected history). Until the client answers, a correction replaces the lines of the orders in the file and leaves orders missing from it alone.

## 7. Organizer menu and Sheets (proof of concept built 2026-11-24)
- New top-level menu **Organizer**: Sheets first; later Word-style documents, Documents (files), Calendar, Contacts, Tasks.
- Sheets: create, edit, save, list/search, `.xlsx` import and export, print (PDF), send (email attachment via the coming email connector). Mostly lists with basic math (`=SUM(A1:A9)/B1`). One editor at a time (no co-editing); last save wins.
- Component: Univer (Apache 2.0), chosen because it supports custom (async) functions; load it only on the Sheets page (~1-2 MB).
- Storage: tenant-scoped table holding each workbook as JSON, behind API routes with RLS. Visibility per sheet: owner only, or shared with the tenant (other Alpine users). Table and column names to be shown for approval.
- BPS functions (proof of concept): `BPS.SALES(from, [to])`, `BPS.BALANCE(customer_no)`, `BPS.ITEM_PRICE(item_no, customer_no, [date])`, `BPS.QTY_ORDERED(item_no, date, [code])`, `BPS.AGING(customer_no, bucket)`. Each is a whitelisted database function called through one API route, batched per sheet, run as the signed-in user under RLS (no access → `#ACCESS`). Values recalculate on open; print/send show values at that moment; `.xlsx` export saves last values. Possible later: "freeze values".
- Formulas other than BPS functions run in the browser (accepted exception to computations-in-database: free-form sheets, not business rules).
- Built: `org_sheets` (sheet_id, tenant_id, owner_user_id, sheet_name, visibility, workbook, version, created/updated at/by), area `organizer.sheets`, functions `org_sheets_get`, `org_sheet_get`, `org_sheet_save`, `org_sheet_delete`, `org_sheet_bps_eval`; Organizer menu with Sheets (Documents, Calendar, Contacts, Tasks greyed out).
- Follow-ups: Send (needs the email connector; the button is disabled); the grid stays light in dark mode; check the editor signed in on an iPad; consider "freeze values" and more BPS functions once the client uses it.
