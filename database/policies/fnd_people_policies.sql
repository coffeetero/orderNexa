-- ============================================================
-- FND_PEOPLE — Row Level Security
-- Run after: fnd_people.sql. References auth.jwt().
-- ============================================================

ALTER TABLE fnd_people ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_people_tenant ON fnd_people;
CREATE POLICY pol_fnd_people_tenant ON fnd_people
    FOR ALL
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);
