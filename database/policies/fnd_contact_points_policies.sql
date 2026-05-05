-- ============================================================
-- FND_CONTACT_POINTS — Row Level Security
-- Run after: fnd_contact_points.sql. References auth.jwt().
-- ============================================================

ALTER TABLE fnd_contact_points ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_contact_points_tenant ON fnd_contact_points;
CREATE POLICY pol_fnd_contact_points_tenant ON fnd_contact_points
    FOR ALL
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);
