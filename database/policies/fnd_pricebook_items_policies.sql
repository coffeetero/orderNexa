-- ============================================================
-- FND_PRICEBOOK_ITEMS — Row Level Security
-- Run after: fnd_pricebook_items.sql. References auth.jwt().
-- ============================================================

ALTER TABLE fnd_pricebook_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_pricebook_items_tenant ON fnd_pricebook_items;
CREATE POLICY pol_fnd_pricebook_items_tenant ON fnd_pricebook_items
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);
