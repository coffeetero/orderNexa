-- ============================================================
-- AR_PAYMENT_APPLICATIONS — Row Level Security
-- Read: tenant members; customer-restricted users only see rows for their customers. Write: tenant staff only.
-- Run after: ar_payment_applications.sql
-- ============================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE ar_payment_applications TO authenticated;
GRANT ALL ON TABLE ar_payment_applications TO bps_dev;

ALTER TABLE ar_payment_applications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_ar_payment_applications_tenant ON ar_payment_applications;
DROP POLICY IF EXISTS pol_ar_payment_applications_read ON ar_payment_applications;
CREATE POLICY pol_ar_payment_applications_read ON ar_payment_applications
    FOR SELECT
    USING (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')))
        AND (
            NOT (tenant_id::text = ANY (ARRAY(
                SELECT jsonb_array_elements_text(
                    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'))))
            OR EXISTS (SELECT 1 FROM ar_payments p WHERE p.ar_payment_id = ar_payment_applications.ar_payment_id)
        )
    );

DROP POLICY IF EXISTS pol_ar_payment_applications_staff_write ON ar_payment_applications;
CREATE POLICY pol_ar_payment_applications_staff_write ON ar_payment_applications
    FOR ALL
    USING (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')))
        AND NOT (tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'))))
    )
    WITH CHECK (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')))
        AND NOT (tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'))))
    );
