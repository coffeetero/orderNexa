-- ============================================================
-- AR_TRANSACTION_LINES — Row Level Security
-- Run after: ar_transaction_lines.sql. References auth.jwt().
-- ============================================================

ALTER TABLE ar_transaction_lines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_ar_transaction_lines_tenant ON ar_transaction_lines;
CREATE POLICY pol_ar_transaction_lines_tenant ON ar_transaction_lines
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);
