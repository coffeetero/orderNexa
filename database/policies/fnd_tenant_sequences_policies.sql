-- ============================================================
-- FND_TENANT_SEQUENCES — Row Level Security
-- ============================================================

ALTER TABLE fnd_tenant_sequences ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_tenant_sequences_tenant ON fnd_tenant_sequences;
CREATE POLICY pol_fnd_tenant_sequences_tenant ON fnd_tenant_sequences
    FOR ALL
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);
