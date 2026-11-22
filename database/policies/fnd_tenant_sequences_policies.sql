-- ============================================================
-- FND_TENANT_SEQUENCES — Row Level Security
-- Read: tenant staff (restricted customer users get nothing: numbering is internal). Write: tenant staff only.
-- Run after: fnd_tenant_sequences.sql
-- ============================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE fnd_tenant_sequences TO authenticated;
GRANT ALL ON TABLE fnd_tenant_sequences TO bps_dev;

ALTER TABLE fnd_tenant_sequences ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_tenant_sequences_tenant ON fnd_tenant_sequences;
DROP POLICY IF EXISTS pol_fnd_tenant_sequences_read ON fnd_tenant_sequences;
CREATE POLICY pol_fnd_tenant_sequences_read ON fnd_tenant_sequences
    FOR SELECT
    USING (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')))
        AND (
            NOT (tenant_id::text = ANY (ARRAY(
                SELECT jsonb_array_elements_text(
                    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'))))
            OR FALSE
        )
    );

DROP POLICY IF EXISTS pol_fnd_tenant_sequences_staff_write ON fnd_tenant_sequences;
CREATE POLICY pol_fnd_tenant_sequences_staff_write ON fnd_tenant_sequences
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
