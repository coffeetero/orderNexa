-- ============================================================
-- FND_TENANTS — Row Level Security
-- Target: Supabase (PostgreSQL 15+)
--
-- Run after: fnd_tenants.sql (table + triggers).
-- References auth.jwt() — requires USAGE on schema auth (e.g. SQL Editor / postgres).
-- ============================================================

ALTER TABLE fnd_tenants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_tenants_self ON fnd_tenants;
CREATE POLICY pol_fnd_tenants_self ON fnd_tenants
    FOR ALL
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);
