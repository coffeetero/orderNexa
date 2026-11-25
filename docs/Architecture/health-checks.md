# Health checks

A nightly checker for setup and data consistency. Findings are logged and shown by the heart icon in the top bar and on Admin > Health Checks.

## Tables (two)
- `fnd_health_checks`: one row per company per check (name, category Setup/Data, `runs_before_production`, `is_enabled`, last run time and the open Information/Warning/Error counts). Rows are created from the list in `fnd_health_catalog()`.
- `fnd_health_log`: one row per finding: `type` (Information / Warning / Error), `findings`, `remediation`, `record_type`/`record_id`, `customer_id`, `link_path`, `fixed_at`, `fixed_by`. A finding that the next run no longer finds is closed automatically (`fixed_by` empty); a person can also mark it fixed, and it reopens if the problem is still there.
- Access area `admin.health` (read = see and open the page and heart, write = run checks and mark fixed, approve = enable/disable a check).

## Checks
Each check is a function `fnd_hc_<code>(tenant)` returning findings. Add a check by writing the function and adding a row to `fnd_health_catalog()`. Current checks: users without a role, accounts without a pricing book / contact / address, compound items without components or with inactive components, pricing books not used (Information, also refreshes `last_used_date`), orders without a pricing book (Error, before Production Run), orders with unpriced lines (before Production Run), payments applied for more than received (Error), items not ordered (Information, also refreshes `last_ordered_date`), open balances out of step with a full recalculation (`ar_open_items_drift`, Error), only one user administrator (`single_user_admin`, Warning).

## Running
- `fnd_health_run(tenant, trigger, check_code?)` runs the enabled checks. The page and API (`/api/admin/health`) call it with trigger Manual.
- `fnd_health_run_due()` runs every company whose local time is in the midnight hour and that has not run today. Schedule it hourly with pg_cron (not installed locally): `SELECT cron.schedule('health-checks', '5 * * * *', 'SELECT bps.fnd_health_run_due()');`
- Heart (`/api/health/status`, `fnd_health_status`): grey never run, green clean, yellow warnings, red and blinking errors; Information never changes it. It refreshes every 5 minutes and on window focus.

## Not built yet
- Notification by email and text, and the Data Troubleshooter / Setup Troubleshooter roles that choose the channels.
- Production Run blocked while an Error from a `runs_before_production` check is open.
- Customer-side findings (a `portal.health` area and view).
- More checks: banking and credit card, invoice lines vs shipments, overlapping approved pricing books, production codes without delivery days.
