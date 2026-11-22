-- ============================================================
-- AR_PAYMENTS — Row Level Security
-- Read: tenant members; customer-restricted users only see rows for their customers. Write: tenant staff only.
-- Run after: ar_payments.sql
-- ============================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE ar_payments TO authenticated;
GRANT ALL ON TABLE ar_payments TO bps_dev;

ALTER TABLE ar_payments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_ar_payments_tenant ON ar_payments;
DROP POLICY IF EXISTS pol_ar_payments_read ON ar_payments;
CREATE POLICY pol_ar_payments_read ON ar_payments
    FOR SELECT
    USING (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')))
        AND (
            NOT (tenant_id::text = ANY (ARRAY(
                SELECT jsonb_array_elements_text(
                    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'))))
            OR (customer_id)::text = ANY (ARRAY(SELECT jsonb_array_elements_text(NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_customer_ids')))
        )
    );

DROP POLICY IF EXISTS pol_ar_payments_staff_write ON ar_payments;
CREATE POLICY pol_ar_payments_staff_write ON ar_payments
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
