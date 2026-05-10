-- ============================================================
-- FND_VALUESETS / FND_VALUESET_VALUES — Row Level Security
-- Run after: fnd_valuesets.sql. References auth.jwt().
-- ============================================================

ALTER TABLE fnd_valuesets ENABLE ROW LEVEL SECURITY;
ALTER TABLE fnd_valueset_values ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_valuesets_tenant ON fnd_valuesets;
CREATE POLICY pol_fnd_valuesets_tenant ON fnd_valuesets
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);

DROP POLICY IF EXISTS pol_fnd_valueset_values_tenant ON fnd_valueset_values;
CREATE POLICY pol_fnd_valueset_values_tenant ON fnd_valueset_values
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);
