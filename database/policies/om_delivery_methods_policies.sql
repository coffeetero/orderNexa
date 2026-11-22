-- ============================================================
-- OM_DELIVERY_METHODS — Row Level Security
-- Everyone in an allowed tenant can read. Only tenant staff (tenant NOT in restricted_tenant_ids) can write.
-- Run after: om_delivery_methods.sql
-- ============================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE om_delivery_methods TO authenticated;
GRANT ALL ON TABLE om_delivery_methods TO bps_dev;

ALTER TABLE om_delivery_methods ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_om_delivery_methods_read ON om_delivery_methods;
CREATE POLICY pol_om_delivery_methods_read ON om_delivery_methods
    FOR SELECT
    USING (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')
        ))
    );

DROP POLICY IF EXISTS pol_om_delivery_methods_staff_write ON om_delivery_methods;
CREATE POLICY pol_om_delivery_methods_staff_write ON om_delivery_methods
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
