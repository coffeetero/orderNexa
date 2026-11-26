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
  - Done 2026-11-25 for open items: `bps.ar_open_items` (migration/add_ar_open_items.sql) holds only documents with money open, kept by triggers. Dashboard AR call 0.45 s → 0.01 s; aging and statements for today use it too. Health check `ar_open_items_drift`. Still slow: `ar_sales_report_get`, `ar_customer_balance_get` (not yet checked).

### Returns and credits: where they live (decided 2026-11-25)
- Returns and credits are entered under **Financials** (Adjustments): Enter Credits (built; credit memo referencing the invoice line), Enter Returns (to design). The office that handles checks, credits and debits does this work, as in the old BPS. Orders › Returns & Credits placeholder removed.
- Every route ends in a credit memo in AR; applying a credit to an invoice is a credit application (Financials › Manage Payments), never negative cash.
- To design Enter Returns (mockup first): stales policy (credit up to a % of delivered?), entry by delivery date / customer / item quantities with BPS pricing them, whether returned goods are tracked for waste or production, and debit memos (charges) if Alpine needs them.

### Post Orders: rename Process Run, number invoices, post to AR (decided 2026-11-25, not built)
- Rename Production › Process Run to **Post Orders**. Posting locks the run for customers (firm cutoff), creates one invoice per bill-to customer per run, **gives it its number** (moved from the Packaging print) and posts it to AR. Packaging List and Print Invoices only print what is posted.
- No production table is needed: the Baker's Report already expands compound items on the fly (`om_run_item_quantities`).
- Application setting **"Lock invoices with Post"** (per company, Admin › Application Settings):
  - ON: posted orders cannot be edited; corrections go through Enter Credits (or a reopen by a privileged user, to decide).
  - OFF: staff may edit a posted order; the save re-syncs that customer's invoice for the run by invoice number (same number, lines and amount rebuilt from its orders) in the same transaction, so AR follows; the invoice is flagged "changed since printed". One database function builds invoices for both Post Orders and order save.
- **Once an invoice is paid (any payment applied), changes go only through Enter Credits**, whatever the setting. Probably the same for a confirmed delivery or a closed period (to confirm).
- Orders keep their own numbers per Department/Event (as in old BPS: easier to call about an order number); all of a customer's orders for a run share one invoice.
- Open: who may reopen a posted run; whether an order entered after posting joins the invoice automatically (setting OFF); gapless numbering vs "cancelled, number kept".

### Credits flow (decided 2026-11-25, Enter Credits screen in progress)
- A credit is a CM in AR linked to the invoice (and line) it is for. It is not applied to that invoice automatically: open credits are applied to the customer's **next issued invoice** and printed on it ("Less credit CM 1042 for INV-1000 (11/27), 20 rolls short"). If there is no next invoice it stays open on the account.
- Paid invoice: the credit stays open and is used on later invoices.
- Built 2026-11-25: `ar_transaction_lines.quantity_credited` (invoice lines; quantity only, no amount) kept by triggers from the credit memo lines and a credit memo's status (migration/add_quantity_credited.sql); Enter Credits shows it and `ar_credit_memo_create` limits new credits with it. To do: a health check comparing it with the credit memo lines (like `ar_open_items_drift`).
- Needs: `ar_credit_applications.ar_payment_id` optional (apply without a payment), apply-on-issue in the posting function, credits on the invoice print and reprint, customer portal shows the CM and balance.
- Statement: each invoice followed by its credit lines (number, date, reason), the invoice balance on its last line; leftover open credits as their own lines.

### Credit line vs credit memo: decide with Alpine (meeting Monday 2026-11-30)
- Alpine today: go back to the order and add a **CREDIT** line (an amount), then reprint the invoice. Simple for them; works while the invoice is unpaid, but changes a past invoice and has no answer once the invoice is paid.
- Built so far: Enter Credits creates a numbered **credit memo in AR** linked to the invoice lines (item quantities), dated the day it is given, so closed periods and paid invoices are untouched.
- Owner's proposal (2026-11-25, to confirm with Alpine): application setting **"Accounting Rules: Strict | Relaxed"**.
  - **Strict:** any change after posting creates an adjustment in AR (credit memo, or a debit for added items); the posted invoice never changes.
  - **Relaxed:** while the invoice is unpaid, staff may change the order, including adding items and a **CREDIT** line; the invoice is re-synced by invoice number (same number) and AR follows, as in the Post Orders design. Once paid, changes produce adjustments, as in Strict.
  - In both, a paid invoice is never edited. Replaces the separate "Lock invoices with Post" setting idea above (Strict = locked, Relaxed = editable until paid).
  - Open: under Strict, anything that raises the amount after posting (an added item, or a higher quantity on an existing item) needs a **debit memo** (charge) document type, which does not exist yet; lowering a quantity is a credit memo.
- Related parked item: a **Credit** amount line at the bottom of Enter Credits' Order Detail (no quantity; goes on the same credit memo with the reason). Open: cap at order total less earlier credits or at the invoice's open balance; reason required; keep CM- numbers or continue the old CR- numbers.
- Either way the invoice reprint and statement show the credit, so the customer sees it on the document they know.

### AR troubleshooting and write-off screen (idea 2026-11-25, not designed)
- Built on `bps.ar_open_items`: list old documents that are still open (e.g. a 2022 invoice or a 2000 payment), show their history (invoice, applications, reversals, credits) so a user can see why the balance remains.
- Actions: write off an invoice remainder to an allowance, zero out an unapplied payment, or apply it to an invoice. Needs: approval rules, an allowance/write-off document type, audit, and how write-offs show on statements and in the sales report.
- Would clear most of the about -$191,000 of old negative items behind the negative Outstanding AR (see the reconciliation above).
- Likely cause of many of them (owner, 2026-11-25): Alpine sometimes accepted a settlement (the customer paid less, or a payment was taken as payment in full) and nobody went back to clear the remaining invoices or payment balances, because the old BPS simply left negative transactions out of its reports. BPS counts them, so they now show as open.
- So the screen needs a **settlement** action: pick an account's open items, record the settlement (date, reason, who approved) and close the remainders in one step, as a write-off/allowance document so statements and the sales report show it.
- Open question for the Alpine manager: clear the old remainders once at go-live (a migration cleanup with a cut-off date and their sign-off), or leave them and settle account by account with the screen.

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
- Done 2026-11-24 (migration events): departments named "ORDER" take the old order's own name (`ordr.cus_name`, e.g. Featherstone "R01 A1006502 0003"); other departments keep their name; same event in one slot → + department number, still the same → + " #order". Applied in place (`fix_om_orders_department_event.sql`, 137,688 orders) and in `seed_om_orders.sql`. Not a reload: truncating om_orders cascades to ar_transaction_lines.
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

## 8. Users, invites and UAT site (built locally 2026-11-24)
Built: Add user, invite / resend, accept page, forgot password, edit user (name, email until first sign-in, customer account), customer email sender panel, links built from `SITE_BASE_URL`. Emails go through Resend (ordernexa.com and alpinebakerynj.com verified). Customer emails never name OrderNexa.

### Before the first real invite
- Commit the work (nothing from 2026-11-24 evening is committed).
- Cloud database: apply `add_user_invites.sql`, `fnd_user_invites.sql`, `fnd_users_get.sql` (needs the owner's OK per write).
- Host the UAT site with `SITE_BASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `RESEND_API_KEY`, `ORDERNEXA_EMAIL_FROM`; decide the address (`alpine-bakery.ordernexa.com` or Alpine's `bps.alpinebakerynj.com`; a custom domain needs link support).
- Supabase dashboard (cloud): Email OTP Expiration = 86400 (emails promise 24 hours; local is 1 hour); confirm Auth › Hooks points at `bps.bps_access_token_hook`.
- Alpine's From and Reply-to addresses: type them in Admin › Customer Users › Change (owner to supply).
- maria@bps.com has no customer account: pick one on Customer Users.
- Read one real invite email end to end from the hosted site (link address, wording, lands in the right place).

### Circle back
- Last-administrator guard (built 2026-11-24): a user or role change that would leave nobody able to manage users is refused (`fnd_assert_user_admin`); the Users screen warns when only one person has that access. Still open: an OrderNexa recovery path other than SQL, and add `add_access_admin_functions.sql` to the cloud apply list.
- Change type (staff ↔ customer): a user's type is fixed and one email is one person, so today it is SQL only (change `user_type`, remove the customer link, swap roles for the other audience, add customer groups for staff). Add a "Change type" action; decide whether only before first sign-in or any time. Same email cannot be both staff and customer (needs a second address).
- No delete user: only "Active in this tenancy" off. Decide whether a delete (soft) is wanted, e.g. for a mistyped user who never signed in.
- From address: any tenancy admin can type any address, including another tenancy's verified domain. Lock it to OrderNexa before a second tenancy goes live (needs a platform-admin notion, also needed for trial signup).
- Forgot password: limited to one email per person per 2 minutes; no per-visitor limit (new table, or the hosting platform's rate limiting).
- Shared email across tenancies is refused; only a direct database session can attach a person to a second tenancy. Needs a proper OrderNexa screen when a second tenancy exists.
- Trial signup (prospect creates their own tenancy): deferred.
- "Designed by orderNexa.com" on the site, and the inquiries website (owner).
- Resend: each new bakery's domain is added in OrderNexa's Resend account (DNS records in the bakery's DNS). Free plan: 3,000 emails a month, 100 a day.

### From the 2026-11-24 review (not fixed)
- High: cloud 8-second limit vs AR Open Balances for all accounts (12.6 s) and Print Invoices for all accounts, one day (13-14 s); Next.js 13.5.1 is out of support; direct database logins (`bps_dev`, `bps_app`) are fully trusted.
- Rotate the cloud `postgres`, `bps_dev` and `bps_app` passwords (shown once in tool output).
- Medium: 23 staff pages have no per-area guard; a session token is committed in `.claude/worktrees/dazzling-heyrovsky-7d6ad1/.claude/settings.local.json` (untrack it); no security headers; lint is skipped in builds.
- Low: `fn_audit_log` and `handle_new_user` have no search_path; dead `handle_*` functions; 5 junk `v_*` tables in bps (also in cloud); the access-token hook ignores `deleted_at`; raw database errors reach the browser; about 6 redundant indexes (~100 MB).

## 9. Overnight build 2026-11-24 follow-ups (local only, not in the cloud)
Built and merged: Dashboard real data, Customers Import/Export, Inventory › Nutrition Labels, Financials › Manage Payments, Organizer › Contacts. Each has a migration in database/migration (add_customer_import_export, add_nutrition_labels, add_manage_payments, add_organizer_contacts) plus function files; apply them to the cloud with the user-invite files.
- Approve the new tables and columns (listed in the morning report).
- Outstanding AR shows negative on the dashboard (-$35k, -$192k over 90 days): legacy negative payment applications (section 4). Fix before Alpine sees it.
- Customer import can change a customer's type and parent: keep or restrict.
- Repo file database/functions/fnd_customers_save.sql inserts `fnd_contacts.contact_name` (column no longer exists); the live local function does not. Bring the file in line before it is reapplied anywhere.
- Nutrition Labels: test real printouts (page breaks); tabular and linear layouts are approximations; no version history; last save wins.
- Manage Payments: deposit batches, edit payment header, refunds of unapplied cash, payment number on the Admin numbering screen; tighten delete policies on ar_payments / ar_payment_applications; measure the AR report (0.8 → 1.1 s locally) on the cloud.
- Contacts: no PERSON contacts exist yet (migrated customer data has only ADDRESSES / OTHER_CONTACTS rows), so the address book starts empty; consider converting OTHER_CONTACTS into people. Not done: per-user favourites, structured address parts, picking related people from contacts, photos in export. Contacts users can edit customer person contacts in their scope without customer-profile write access.
- Tests failing before tonight and still failing: rls_test (legacy tables, order visibility), documents_reports_test (om_shipments.production_run_id).

## 10. Post Production (after go-live)

### Customer email templates and mass emails (idea 2026-11-24, not designed)
- Purpose: notices to many customers at once, e.g. "Dear {{customer_name}}, as always we truly appreciate your business. This Thanksgiving the cutoff time is 2 hours earlier."
- Editor: an email template editor (open-source rich text such as TipTap, MIT) with "Insert field", not a Word-style editor. Emails are HTML; Univer Docs targets page layout and .docx and has no free merge fields. Word-style documents stay a separate Organizer item.
- Fields filled by a database function (computations in the database), e.g. customer name, account number, cutoff time, delivery day.
- Audience: all active customers, a customer group, a route, a delivery day or a production code.
- Before sending: preview as a chosen customer; test send to yourself. After: a send log per customer (sent, failed, bounced) in the customer's history.
- Needs the email connector (provider such as Resend, Postmark or Amazon SES, plus the bakery's domain set up so mail is not marked as spam).
- Open questions: which contact receives notices (billing, ordering, or contacts flagged for notices); operational notices only or promotions too (unsubscribe rules); which fields; customers' country (CAN-SPAM or CASL); later the same template by text message (Phone & Messaging).

## 11. Security risks

### Second sign-in step (MFA) for Company Administrators (idea 2026-11-25, not built)
- An authenticator-app code after the password (Supabase Auth supports TOTP). Strongest protection against someone who knows a user's email and guesses or reuses a password.
- To decide: required for Company Administrators, or offered to anyone; how a user who lost their phone gets back in (recovery codes, or an admin reset).

### Security signals for customer administrators (agreed 2026-11-25, waits for the customer portal)
- Built for staff (2026-11-25): activity, IP and approximate place recorded for everyone (`fnd_user_access_log`, 180 days); Company Administrators get To-Dos for staff inactive N working days and staff using BPS from a new city, with Deactivate / Still with us / Expected; nobody can clear a signal about themselves.
- Done 2026-11-25: customer portal › Users (customer administrators add, invite, change role, deactivate their own people; role Customer Staff added). Email held by bakery staff is refused with a clear message and Alpine gets an EMAIL_REUSE To-Do (`fnd_security_events`); Alpine can deactivate and release the email (old record ended, kept for history; new account gets a new user number and password).
- Still to do: inactivity / new-place To-Dos for each customer's administrator about their own users. Needs a real portal home page (it shows sample data today).
- To test once the portal runs on a real domain (or locally): a customer administrator adds an email held by Alpine staff; confirm the message they see and that Alpine's Dashboard gets the EMAIL_REUSE To-Do.
- Reverse case, not built: a customer's employee joins the bakery as staff. Today the add says only "A user with this email already exists". Mirror the staff case: active customer user → "belongs to <name>, an active user of <customer>; deactivate them on Customer Users first"; inactive → "Release email and add" (fnd_user_release_email accepts deactivated customer users; their record ends, kept for the customer's history, old sign-in retired; new staff account with a new user number and password). Later, tell the customer's administrator when the bakery deactivates one of their users.
- Possibly later: an alert when a deactivated person tries to sign in; a monthly access review email.

### Usernames as an optional sign-in name (idea 2026-11-25, parked)
- Owner's reasons: an account name is less known than an email; one person could have e.g. moraglen-alpine and moraglen-tomcat.
- Findings: Supabase allows one account per email, so two usernames on one email share one password; the company is already chosen at sign-in (or by the company web address). The real uses are privacy and, later, staff without email.
- If built: new column `fnd_users.username` (unique across BPS), sign-in accepts email or username (resolved on the server, without revealing whether a name exists, with a limit on failed tries).

### Account recovery codes stored in the project folder (found 2026-11-25)
- `docs/vercel/` holds the Vercel account's recovery codes in a plain text file. Anyone with the file can take over the Vercel account (and so the hosted site and its environment variables).
- Done: `docs/vercel/` is in `.gitignore`, so it cannot be committed.
- To do (owner): move the file into a password manager and delete it from the project folder; check it was never copied elsewhere (cloud sync, backups, other machines).
- 2026-11-25: both cloud database passwords in `supabase setup/supabase initial setup.txt` (the `postgres` user and the pooler user `bps_dev`) were printed into a Claude Code session transcript by mistake. Change both in the Supabase dashboard (Project Settings > Database), then update the file.
- Same rule for `supabase setup/` (cloud database passwords, `uat.env` with the Resend API key): gitignored, but still plain files on disk. Move them to a password manager or an encrypted vault before go-live, and rotate any key that was ever shared.

## 12. Overnight build 2026-11-25 follow-ups (merged 2026-11-26, local only, not in the cloud)
Built and merged: Organizer › Calendar, Organizer › Tasks, Inventory › Recipes. Migrations add_organizer_calendar, add_organizer_tasks, add_recipes plus function files; apply to the cloud only with the owner's OK. Hand-over notes (column lists) are in the session notes folder.
- Owner to confirm: Calendar privacy per calendar (not per event), colours from status tokens, company time zone only, any Calendar writer may edit any shared event; another user's private task list hidden even from Company Administrators; recipe ingredients as their own catalog; °F only.
- Not tested: Ledger and Graphite themes; Calendar "this and following" and one-occurrence delete in the browser; Tasks drag and drop in the browser; Recipes print preview, iPad, delete buttons.
- `npm run build` fails when `website/.env.local` is a symlink (worktrees need a copy).
- Recipes demo data in the local database (8 ingredients; Poolish, Ciabatta, Light Rye); removal SQL in recipes-handover.md.

### Calendar
- Reminders/notifications and invitations/attendees; Google / Apple sync, .ics export/import.
- Drag to move or resize events; multi-day all-day events as one bar; Year view.
- Hidden calendars stored per user in the database (per browser today); week start day as a company setting (Sunday now).
- Link events to customers/orders and Contacts; show Closed & holidays days on Order Entry / production planning.
- Categorical colour tokens for calendars; Day/Week opens at 5 AM, consider scrolling to the first event or now.

### Tasks
- Reminders / notifications, notify the assignee; dated tasks in Calendar.
- Show health-check findings and `fnd_security_events` To-Dos as a read-only "System" view, or let a finding create a task.
- Purge soft-deleted tasks after 30 days; "every X from completion" repeats; search; reorder lists; link a task to a customer or order.

### Recipes
- Replace native selects (ingredients, 1,000+ items) with EntityComboBox-style search.
- Friendly units per line from the database (g under 1 kg, oz under 1 lb); °C option; volume units and "each".
- Restore and compare versions; water content of milk, eggs, butter for hydration.
- Nutrition from recipes into Nutrition Labels; production batch sheets from order quantities via dough_code.
- Costing & COGS screen, ingredient price history, bake loss; items as ingredients (optional item_id on inv_ingredients).
