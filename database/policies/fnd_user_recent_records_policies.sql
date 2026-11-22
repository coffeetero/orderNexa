-- ============================================================
-- FND_USER_RECENT_RECORDS — Row Level Security
-- A user sees only their own rows, and only for tenants named in allowed_tenant_ids.
-- Run after: fnd_user_recent_records.sql, functions/fnd_nav_app_user_id.sql
-- ============================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE fnd_user_recent_records TO authenticated;
GRANT ALL ON TABLE fnd_user_recent_records TO bps_dev;

ALTER TABLE fnd_user_recent_records ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_user_recent_records_owner ON fnd_user_recent_records;
CREATE POLICY pol_fnd_user_recent_records_owner ON fnd_user_recent_records
    FOR ALL
    USING (
        user_id = bps.fnd_nav_app_user_id()
        AND tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids'
            )
        ))
    )
    WITH CHECK (
        user_id = bps.fnd_nav_app_user_id()
        AND tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids'
            )
        ))
    );
