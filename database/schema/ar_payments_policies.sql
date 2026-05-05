-- ============================================================
-- AR_PAYMENTS — Row Level Security
-- Run after: ar_payments.sql. References auth.jwt().
-- ============================================================

ALTER TABLE ar_payments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_ar_payments_tenant ON ar_payments;
CREATE POLICY pol_ar_payments_tenant ON ar_payments
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);
