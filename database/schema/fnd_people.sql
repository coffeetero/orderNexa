-- ============================================================
-- FND_PEOPLE  –  Person/contact master (tenant-scoped)
-- Target: Supabase (PostgreSQL 15+)
--
-- person_id uses fnd_entity_id_seq (run fnd_entity_id_seq.sql before this file).
-- Run after: fnd_tenants.sql, fnd_customers.sql (fn_set_updated_at_ts_only, fn_audit_log)
-- ============================================================

CREATE TABLE IF NOT EXISTS fnd_people (
    person_id         BIGINT      PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),
    first_name        TEXT        NOT NULL,
    last_name         TEXT        NOT NULL,
    display_name      TEXT        NOT NULL,
    primary_phone     TEXT,
    primary_email     TEXT,
    is_active         BOOLEAN     NOT NULL DEFAULT TRUE,
    contact_details   JSONB       NOT NULL DEFAULT '{}'::jsonb,

    tenant_id         BIGINT        NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,

    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by        BIGINT,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by        BIGINT
);

CREATE INDEX IF NOT EXISTS idx_fnd_people_tenant_id
    ON fnd_people (tenant_id);

CREATE INDEX IF NOT EXISTS idx_fnd_people_active
    ON fnd_people (tenant_id)
    WHERE is_active = TRUE;

CREATE INDEX IF NOT EXISTS idx_fnd_people_primary_email
    ON fnd_people (tenant_id, primary_email)
    WHERE primary_email IS NOT NULL;

DROP TRIGGER IF EXISTS trg_fnd_people_set_updated ON fnd_people;
CREATE TRIGGER trg_fnd_people_set_updated
    BEFORE UPDATE ON fnd_people
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_fnd_people_audit ON fnd_people;
CREATE TRIGGER trg_fnd_people_audit
    AFTER INSERT OR UPDATE OR DELETE ON fnd_people
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('person_id');

ALTER TABLE fnd_people ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_people_tenant ON fnd_people;
CREATE POLICY pol_fnd_people_tenant ON fnd_people
    FOR ALL
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);
