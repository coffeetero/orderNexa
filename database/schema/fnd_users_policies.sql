-- ============================================================
-- FND_USERS — Row Level Security
-- Run after: fnd_users.sql. References auth.jwt().
-- ============================================================

ALTER TABLE fnd_users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_users_tenant ON fnd_users;
CREATE POLICY pol_fnd_users_tenant ON fnd_users
    FOR ALL
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);
