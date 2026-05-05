-- ============================================================
-- FND_CONTACTS  –  Person/contact master (tenant-scoped)
-- Target: Supabase (PostgreSQL 15+)
--
-- Run with search_path including your app schema, e.g.:
--   SET search_path = bps, public;
--
-- contact_id uses fnd_entity_id_seq (run fnd_entity_id_seq.sql before this file).
-- Run after: fnd_tenants.sql, fnd_customers.sql (fn_set_updated_at_ts_only, fn_audit_log)
--
-- Note: not present on all deployments; optional script for greenfield / future use.
-- RLS policies (auth.jwt) are in fnd_contacts_policies.sql — run that once from a role
-- with USAGE on schema auth (e.g. Supabase SQL Editor as postgres), not from pooler roles.
-- ============================================================

CREATE TABLE IF NOT EXISTS fnd_contacts (
    tenant_id         BIGINT        NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,
    contact_id        BIGINT      PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),
    contact_name      TEXT        NOT NULL,
    first_name        TEXT        NOT NULL,
    last_name         TEXT        NOT NULL,
    is_active         BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by        BIGINT,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by        BIGINT
);

CREATE INDEX IF NOT EXISTS idx_fnd_contacts_tenant_id
    ON fnd_contacts (tenant_id);

CREATE INDEX IF NOT EXISTS idx_fnd_contacts_active
    ON fnd_contacts (tenant_id)
    WHERE is_active = TRUE;

DROP TRIGGER IF EXISTS trg_fnd_contacts_set_updated ON fnd_contacts;
CREATE TRIGGER trg_fnd_contacts_set_updated
    BEFORE UPDATE ON fnd_contacts
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_fnd_contacts_audit ON fnd_contacts;
CREATE TRIGGER trg_fnd_contacts_audit
    AFTER INSERT OR UPDATE OR DELETE ON fnd_contacts
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('contact_id');
