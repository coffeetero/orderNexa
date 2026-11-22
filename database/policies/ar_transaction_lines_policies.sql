-- ============================================================
-- AR_TRANSACTION_LINES — Row Level Security
-- Read: tenant members; customer-restricted users only see rows for their customers. Write: tenant staff only.
-- Run after: ar_transaction_lines.sql
-- ============================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE ar_transaction_lines TO authenticated;
GRANT ALL ON TABLE ar_transaction_lines TO bps_dev;

ALTER TABLE ar_transaction_lines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_ar_transaction_lines_tenant ON ar_transaction_lines;
DROP POLICY IF EXISTS pol_ar_transaction_lines_read ON ar_transaction_lines;
CREATE POLICY pol_ar_transaction_lines_read ON ar_transaction_lines
    FOR SELECT
    USING (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')))
        AND (
            NOT (tenant_id::text = ANY (ARRAY(
                SELECT jsonb_array_elements_text(
                    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'))))
            OR EXISTS (SELECT 1 FROM ar_transactions t WHERE t.ar_transaction_id = ar_transaction_lines.ar_transaction_id)
        )
    );

DROP POLICY IF EXISTS pol_ar_transaction_lines_staff_write ON ar_transaction_lines;
CREATE POLICY pol_ar_transaction_lines_staff_write ON ar_transaction_lines
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
