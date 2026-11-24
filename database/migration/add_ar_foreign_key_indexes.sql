-- Indexes for the AR foreign keys. Deleting an ar_transactions / ar_payments row checks its child rows by the key alone;
-- the existing (tenant_id, key) indexes cannot serve that, so each delete scanned the child tables (a full AR reload took
-- hours). No new tables or columns.
CREATE INDEX IF NOT EXISTS idx_ar_transaction_lines_ar_transaction ON bps.ar_transaction_lines (ar_transaction_id);
CREATE INDEX IF NOT EXISTS idx_ar_payment_applications_ar_transaction ON bps.ar_payment_applications (ar_transaction_id);
CREATE INDEX IF NOT EXISTS idx_ar_payment_applications_ar_payment ON bps.ar_payment_applications (ar_payment_id);
CREATE INDEX IF NOT EXISTS idx_ar_transactions_applies_to ON bps.ar_transactions (applies_to_ar_transaction_id) WHERE applies_to_ar_transaction_id IS NOT NULL;
