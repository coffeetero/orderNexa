-- ============================================================
-- FND_TENANT_OPTIONS — Row Level Security
-- Run after: fnd_tenant_options.sql.
-- ============================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE fnd_tenant_options TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE fnd_tenant_options TO bps_dev;

ALTER TABLE fnd_tenant_options ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_tenant_options_tenant ON fnd_tenant_options;

CREATE POLICY pol_fnd_tenant_options_tenant ON fnd_tenant_options
    FOR ALL
    USING (
        tenant_id::text = ANY (
            ARRAY(
                SELECT jsonb_array_elements_text(
                    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids'
                )
            )
        )
    )
    WITH CHECK (
        tenant_id::text = ANY (
            ARRAY(
                SELECT jsonb_array_elements_text(
                    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids'
                )
            )
        )
    );
