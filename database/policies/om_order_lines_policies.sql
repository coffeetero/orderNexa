-- ============================================================
-- OM_ORDER_LINES — Row Level Security
-- Run after: om_order_lines.sql and om_orders_policies.sql.
-- Access follows the parent order's tenant/customer boundary.
-- ============================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE om_order_lines TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE om_order_lines TO bps_dev;

ALTER TABLE om_order_lines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_om_order_lines_tenant ON om_order_lines;
DROP POLICY IF EXISTS pol_om_order_lines_access ON om_order_lines;

CREATE POLICY pol_om_order_lines_access ON om_order_lines
    FOR ALL
    USING (
        EXISTS (
            SELECT 1
              FROM om_orders o
             WHERE o.tenant_id = om_order_lines.tenant_id
               AND o.order_id = om_order_lines.order_id
               AND (o.tenant_id::text = ANY (
                    ARRAY(
                        SELECT jsonb_array_elements_text(
                            NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids'
                        )
                    )
               ))
               AND (
                    NOT (o.tenant_id::text = ANY (
                        ARRAY(
                            SELECT jsonb_array_elements_text(
                                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'
                            )
                        )
                    ))
                    OR
                    (o.customer_id::text = ANY (
                        ARRAY(
                            SELECT jsonb_array_elements_text(
                                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_customer_ids'
                            )
                        )
                    ))
               )
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1
              FROM om_orders o
             WHERE o.tenant_id = om_order_lines.tenant_id
               AND o.order_id = om_order_lines.order_id
               AND (o.tenant_id::text = ANY (
                    ARRAY(
                        SELECT jsonb_array_elements_text(
                            NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids'
                        )
                    )
               ))
               AND (
                    NOT (o.tenant_id::text = ANY (
                        ARRAY(
                            SELECT jsonb_array_elements_text(
                                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'
                            )
                        )
                    ))
                    OR
                    (o.customer_id::text = ANY (
                        ARRAY(
                            SELECT jsonb_array_elements_text(
                                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_customer_ids'
                            )
                        )
                    ))
               )
        )
    );
