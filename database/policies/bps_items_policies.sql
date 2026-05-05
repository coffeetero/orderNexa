-- ============================================================
-- BPS_ITEMS — Row Level Security
-- Run after: bps_items.sql (including bakery column drops section). References auth.jwt().
-- ============================================================

ALTER TABLE bps_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_bps_items_tenant ON bps_items;
CREATE POLICY pol_bps_items_tenant ON bps_items
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);
