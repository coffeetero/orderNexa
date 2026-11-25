-- ============================================================
-- Allowances on invoices (Financials › Enter Payments).
-- An allowance is money taken off an invoice that is not a payment and not a return: at Alpine almost always spoiled
-- product the customer threw away (about 25 in two years, typically $16). Entered on Enter Payments next to the payment,
-- stored on the invoice itself as the old BPS did (ar_trn_allowance_amt), so it shows on the same line:
--   ar_transactions.allowance_amount  total allowance on this invoice (several allowances add up), default 0
--   ar_transactions.allowance_reason  why, and which items (free text, e.g. "2 cases rye, moldy")
--   ar_transactions.allowance_at / allowance_by  when and by whom it was last changed (the audit log keeps every change)
-- Every open balance subtracts it: ar_transaction_open_amount, ar_open_items_refresh, ar_report_open_items_full,
-- ar_payment_open_items_get, fnd_hc_ar_open_items_drift (updated function files). The open-items triggers already recalculate
-- when an invoice row changes.
-- Load this first, then: functions/ar_transaction_open_amount.sql, ar_open_items_refresh.sql, ar_report_open_items.sql,
-- fnd_hc_ar_open_items_drift.sql, ar_payment_open_items_get.sql, ar_payment_enter.sql.
-- ============================================================
SET search_path = bps, public;

ALTER TABLE bps.ar_transactions ADD COLUMN IF NOT EXISTS allowance_amount numeric(14,4) NOT NULL DEFAULT 0;
ALTER TABLE bps.ar_transactions ADD COLUMN IF NOT EXISTS allowance_reason text;
ALTER TABLE bps.ar_transactions ADD COLUMN IF NOT EXISTS allowance_at timestamptz;
ALTER TABLE bps.ar_transactions ADD COLUMN IF NOT EXISTS allowance_by bigint;
ALTER TABLE bps.ar_transactions DROP CONSTRAINT IF EXISTS chk_ar_transactions_allowance;
ALTER TABLE bps.ar_transactions ADD CONSTRAINT chk_ar_transactions_allowance CHECK (allowance_amount >= 0 AND (allowance_amount = 0 OR transaction_type = 'INV'));
COMMENT ON COLUMN bps.ar_transactions.allowance_amount IS 'Allowance taken off this invoice (spoiled product, accepted short-pay, pricing); reduces what is open. Several add up.';
COMMENT ON COLUMN bps.ar_transactions.allowance_reason IS 'Why the allowance was given, and which items (free text).';
