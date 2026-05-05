-- ============================================================
-- OM_ORDER_LINES — Row Level Security
-- Run after: om_order_lines.sql. References auth.jwt().
-- ============================================================

ALTER TABLE om_order_lines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_om_order_lines_tenant ON om_order_lines;
CREATE POLICY pol_om_order_lines_tenant ON om_order_lines
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);
