-- Customer statement becomes an open-item statement, like the old BPS (no period, weekly subtotals, total due = aging total).
-- Load these function files after this one:
--   database/functions/ar_report_open_items.sql  (adds unapplied payments as credits)
--   database/functions/ar_statement_get.sql      (new signature: p_tenant_id, p_account_id, p_as_of)
DROP FUNCTION IF EXISTS bps.ar_statement_get(bigint, bigint, date, date);
