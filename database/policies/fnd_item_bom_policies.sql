-- ============================================================
-- FND_ITEM_BOM — Row Level Security
-- Run after: fnd_item_bom.sql. References auth.jwt().
-- ============================================================

ALTER TABLE fnd_item_bom ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_item_bom_tenant ON fnd_item_bom;
CREATE POLICY pol_fnd_item_bom_tenant ON fnd_item_bom
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);
