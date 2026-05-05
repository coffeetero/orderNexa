-- ============================================================
-- FND_PRICEBOOKS — Row Level Security
-- Run after: fnd_pricebooks.sql. References auth.jwt().
-- ============================================================

ALTER TABLE fnd_pricebooks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_pricebooks_tenant ON fnd_pricebooks;
CREATE POLICY pol_fnd_pricebooks_tenant ON fnd_pricebooks
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);
