-- ============================================================
-- OM_SHIPMENT_LINES — Row Level Security
-- Read: tenant members; customer-restricted users only see rows for their customers. Write: tenant staff only.
-- Run after: om_shipment_lines.sql
-- ============================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE om_shipment_lines TO authenticated;
GRANT ALL ON TABLE om_shipment_lines TO bps_dev;

ALTER TABLE om_shipment_lines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_om_shipment_lines_tenant ON om_shipment_lines;
DROP POLICY IF EXISTS pol_om_shipment_lines_read ON om_shipment_lines;
CREATE POLICY pol_om_shipment_lines_read ON om_shipment_lines
    FOR SELECT
    USING (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')))
        AND (
            NOT (tenant_id::text = ANY (ARRAY(
                SELECT jsonb_array_elements_text(
                    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'))))
            OR EXISTS (SELECT 1 FROM om_shipments s WHERE s.shipment_id = om_shipment_lines.shipment_id)
        )
    );

DROP POLICY IF EXISTS pol_om_shipment_lines_staff_write ON om_shipment_lines;
CREATE POLICY pol_om_shipment_lines_staff_write ON om_shipment_lines
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
