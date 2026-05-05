-- ============================================================
-- OM_ORDERS — Row Level Security
-- Run after: om_orders.sql. References auth.jwt().
-- ============================================================

ALTER TABLE om_orders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_om_orders_tenant ON om_orders;
CREATE POLICY pol_om_orders_tenant ON om_orders
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);
