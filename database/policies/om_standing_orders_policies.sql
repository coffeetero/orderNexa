-- ============================================================
-- OM_STANDING_ORDERS — Row Level Security
-- Run after: om_standing_orders.sql.
-- Access follows the standing order customer boundary.
-- ============================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE om_standing_orders TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE om_standing_orders TO bps_dev;

ALTER TABLE om_standing_orders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_om_standing_orders_tenant ON om_standing_orders;
DROP POLICY IF EXISTS pol_om_standing_orders_access ON om_standing_orders;

CREATE POLICY pol_om_standing_orders_access ON om_standing_orders
    FOR ALL
    USING (
        (tenant_id::text = ANY (
            ARRAY(
                SELECT jsonb_array_elements_text(
                    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids'
                )
            )
        ))
        AND (
            NOT (tenant_id::text = ANY (
                ARRAY(
                    SELECT jsonb_array_elements_text(
                        NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'
                    )
                )
            ))
            OR
            (customer_id::text = ANY (
                ARRAY(
                    SELECT jsonb_array_elements_text(
                        NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_customer_ids'
                    )
                )
            ))
        )
    )
    WITH CHECK (
        (tenant_id::text = ANY (
            ARRAY(
                SELECT jsonb_array_elements_text(
                    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids'
                )
            )
        ))
        AND (
            NOT (tenant_id::text = ANY (
                ARRAY(
                    SELECT jsonb_array_elements_text(
                        NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'
                    )
                )
            ))
            OR
            (customer_id::text = ANY (
                ARRAY(
                    SELECT jsonb_array_elements_text(
                        NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_customer_ids'
                    )
                )
            ))
        )
    );
