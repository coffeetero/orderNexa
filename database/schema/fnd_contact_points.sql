-- ============================================================
-- FND_CONTACT_POINTS  –  Entity/person contact points (tenant-scoped)
-- Target: Supabase (PostgreSQL 15+)
--
-- contact_point_id uses fnd_entity_id_seq (run fnd_entity_id_seq.sql before this file).
-- Run after: fnd_tenants.sql, fnd_customers.sql, fnd_contacts.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS fnd_contact_points (
    tenant_id         BIGINT        NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,
    contact_point_id  BIGINT      PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),

    contact_id        BIGINT      NOT NULL REFERENCES fnd_contacts(contact_id),
    label             TEXT,
    is_primary        BOOLEAN     NOT NULL DEFAULT FALSE,

    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by        BIGINT,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by        BIGINT
);

-- Legacy: drop entity_id from older deployments (no-op on fresh creates).
ALTER TABLE fnd_contact_points DROP COLUMN IF EXISTS entity_id;
DROP INDEX IF EXISTS idx_fnd_contact_points_entity_id;

-- Remove legacy label CHECK constraint on existing databases (if present).
DO $$
DECLARE
    v_constraint_name TEXT;
BEGIN
    SELECT c.conname
    INTO v_constraint_name
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = current_schema()
      AND t.relname = 'fnd_contact_points'
      AND c.contype = 'c'
      AND pg_get_constraintdef(c.oid) ILIKE '%label%'
      AND pg_get_constraintdef(c.oid) ILIKE '%billing%'
      AND pg_get_constraintdef(c.oid) ILIKE '%delivery%'
    LIMIT 1;

    IF v_constraint_name IS NOT NULL THEN
        EXECUTE format(
            'ALTER TABLE %I.%I DROP CONSTRAINT %I',
            current_schema(),
            'fnd_contact_points',
            v_constraint_name
        );
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_fnd_contact_points_tenant_id
    ON fnd_contact_points (tenant_id);

CREATE INDEX IF NOT EXISTS idx_fnd_contact_points_contact_id
    ON fnd_contact_points (tenant_id, contact_id);

CREATE UNIQUE INDEX IF NOT EXISTS uq_fnd_contact_points_primary
    ON fnd_contact_points (tenant_id, contact_id, label)
    WHERE is_primary = TRUE;

DROP TRIGGER IF EXISTS trg_fnd_contact_points_set_updated ON fnd_contact_points;
CREATE TRIGGER trg_fnd_contact_points_set_updated
    BEFORE UPDATE ON fnd_contact_points
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_fnd_contact_points_audit ON fnd_contact_points;
CREATE TRIGGER trg_fnd_contact_points_audit
    AFTER INSERT OR UPDATE OR DELETE ON fnd_contact_points
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('contact_point_id');

-- RLS policies: fnd_contact_points_policies.sql
