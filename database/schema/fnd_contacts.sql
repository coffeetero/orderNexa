-- ============================================================
-- FND_CONTACTS  –  Person/contact master (tenant-scoped)
-- Target: Supabase (PostgreSQL 15+)
--
-- contact_id uses fnd_entity_id_seq (run fnd_entity_id_seq.sql before this file).
-- Run after: fnd_tenants.sql, fnd_customers.sql (fn_set_updated_at_ts_only, fn_audit_log)
-- ============================================================

CREATE TABLE IF NOT EXISTS bps.fnd_contacts (
    contact_id        BIGINT      PRIMARY KEY DEFAULT nextval('bps.fnd_entity_id_seq'::regclass),
    contact_name      TEXT        NOT NULL,
    first_name        TEXT        NOT NULL,
    last_name         TEXT        NOT NULL,
    is_active         BOOLEAN     NOT NULL DEFAULT TRUE,

    tenant_id         BIGINT        NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,

    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by        BIGINT,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by        BIGINT
);

CREATE INDEX IF NOT EXISTS idx_fnd_contacts_tenant_id
    ON bps.fnd_contacts (tenant_id);

CREATE INDEX IF NOT EXISTS idx_fnd_contacts_active
    ON bps.fnd_contacts (tenant_id)
    WHERE is_active = TRUE;

CREATE INDEX IF NOT EXISTS idx_fnd_contacts_primary_email
    ON bps.fnd_contacts (tenant_id, primary_email)
    WHERE primary_email IS NOT NULL;

DROP TRIGGER IF EXISTS trg_fnd_contacts_set_updated ON bps.fnd_contacts;
CREATE TRIGGER trg_fnd_contacts_set_updated
    BEFORE UPDATE ON bps.fnd_contacts
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_fnd_contacts_audit ON bps.fnd_contacts;
CREATE TRIGGER trg_fnd_contacts_audit
    AFTER INSERT OR UPDATE OR DELETE ON bps.fnd_contacts
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('contact_id');

ALTER TABLE bps.fnd_contacts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_contacts_tenant ON bps.fnd_contacts;
CREATE POLICY pol_fnd_contacts_tenant ON bps.fnd_contacts
    FOR ALL
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);
