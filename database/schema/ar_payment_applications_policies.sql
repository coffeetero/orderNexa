-- ============================================================
-- AR_PAYMENT_APPLICATIONS — Row Level Security
-- Run after: ar_payment_applications.sql. References auth.jwt().
-- ============================================================

ALTER TABLE ar_payment_applications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_ar_payment_applications_tenant ON ar_payment_applications;
CREATE POLICY pol_ar_payment_applications_tenant ON ar_payment_applications
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);
