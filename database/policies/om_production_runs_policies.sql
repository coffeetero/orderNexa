-- ============================================================
-- OM_PRODUCTION_RUNS — Row Level Security
-- Everyone in an allowed tenant can read. Only tenant staff (tenant NOT in restricted_tenant_ids) can write.
-- Run after: om_production_runs.sql
-- ============================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE om_production_runs TO authenticated;
GRANT ALL ON TABLE om_production_runs TO bps_dev;

ALTER TABLE om_production_runs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_om_production_runs_read ON om_production_runs;
CREATE POLICY pol_om_production_runs_read ON om_production_runs
    FOR SELECT
    USING (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')
        ))
    );

DROP POLICY IF EXISTS pol_om_production_runs_staff_write ON om_production_runs;
CREATE POLICY pol_om_production_runs_staff_write ON om_production_runs
    FOR ALL
    USING (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')
        ))
        AND NOT (tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids')
        )))
    )
    WITH CHECK (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')
        ))
        AND NOT (tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids')
        )))
    );
