-- ============================================================
-- OM_SHIPMENTS — Row Level Security
-- Read: tenant members; customer-restricted users only see rows for their customers. Write: tenant staff only.
-- Run after: om_shipments.sql
-- ============================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE om_shipments TO authenticated;
GRANT ALL ON TABLE om_shipments TO bps_dev;

ALTER TABLE om_shipments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_om_shipments_tenant ON om_shipments;
DROP POLICY IF EXISTS pol_om_shipments_read ON om_shipments;
CREATE POLICY pol_om_shipments_read ON om_shipments
    FOR SELECT
    USING (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')))
        AND (
            NOT (tenant_id::text = ANY (ARRAY(
                SELECT jsonb_array_elements_text(
                    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'))))
            OR (ship_to_customer_id)::text = ANY (ARRAY(SELECT jsonb_array_elements_text(NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_customer_ids')))
        )
    );

DROP POLICY IF EXISTS pol_om_shipments_staff_write ON om_shipments;
CREATE POLICY pol_om_shipments_staff_write ON om_shipments
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
