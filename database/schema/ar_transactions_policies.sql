-- ============================================================
-- AR_TRANSACTIONS — Row Level Security
-- Run after: ar_transactions.sql. References auth.jwt().
-- ============================================================

ALTER TABLE ar_transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_ar_transactions_tenant ON ar_transactions;
CREATE POLICY pol_ar_transactions_tenant ON ar_transactions
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);
