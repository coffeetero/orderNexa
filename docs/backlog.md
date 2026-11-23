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
