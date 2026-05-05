-- ============================================================
-- FND_USER_TENANTS — Row Level Security
-- Run after: fnd_user_tenants.sql. References auth.jwt().
-- ============================================================

ALTER TABLE fnd_user_tenants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_user_tenants_tenant ON fnd_user_tenants;
CREATE POLICY pol_fnd_user_tenants_tenant ON fnd_user_tenants
    FOR ALL
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);
