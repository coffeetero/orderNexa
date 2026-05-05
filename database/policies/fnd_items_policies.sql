-- ============================================================
-- FND_ITEMS — Row Level Security
-- Run after: fnd_items.sql. References auth.jwt().
-- ============================================================

ALTER TABLE fnd_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_items_tenant ON fnd_items;
CREATE POLICY pol_fnd_items_tenant ON fnd_items
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);
