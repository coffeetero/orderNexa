-- ============================================================
-- FND_CONTACT_POINTS  –  Entity/person contact points (tenant-scoped)
-- Target: Supabase (PostgreSQL 15+)
--
-- contact_point_id uses fnd_entity_id_seq (run fnd_entity_id_seq.sql before this file).
-- Run after: fnd_tenants.sql, fnd_people.sql, fnd_customers.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS fnd_contact_points (
    contact_point_id  BIGINT      PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),

    entity_id         BIGINT      NOT NULL,
    person_id         BIGINT      NOT NULL REFERENCES fnd_people(person_id),
    label             TEXT,
    is_primary        BOOLEAN     NOT NULL DEFAULT FALSE,

    tenant_id         BIGINT        NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,

    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by        BIGINT,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by        BIGINT
);

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
    WHERE n.nspname = 'public'
      AND t.relname = 'fnd_contact_points'
      AND c.contype = 'c'
      AND pg_get_constraintdef(c.oid) ILIKE '%label%'
      AND pg_get_constraintdef(c.oid) ILIKE '%billing%'
      AND pg_get_constraintdef(c.oid) ILIKE '%delivery%'
    LIMIT 1;

    IF v_constraint_name IS NOT NULL THEN
        EXECUTE format('ALTER TABLE public.fnd_contact_points DROP CONSTRAINT %I', v_constraint_name);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_fnd_contact_points_tenant_id
    ON fnd_contact_points (tenant_id);

CREATE INDEX IF NOT EXISTS idx_fnd_contact_points_entity_id
    ON fnd_contact_points (tenant_id, entity_id);

CREATE INDEX IF NOT EXISTS idx_fnd_contact_points_person_id
    ON fnd_contact_points (tenant_id, person_id);

CREATE UNIQUE INDEX IF NOT EXISTS uq_fnd_contact_points_primary
    ON fnd_contact_points (tenant_id, person_id, label)
    WHERE is_primary = TRUE;

DROP TRIGGER IF EXISTS trg_fnd_contact_points_set_updated ON fnd_contact_points;
CREATE TRIGGER trg_fnd_contact_points_set_updated
    BEFORE UPDATE ON fnd_contact_points
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_fnd_contact_points_audit ON fnd_contact_points;
CREATE TRIGGER trg_fnd_contact_points_audit
    AFTER INSERT OR UPDATE OR DELETE ON fnd_contact_points
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('contact_point_id');

ALTER TABLE fnd_contact_points ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_contact_points_tenant ON fnd_contact_points;
CREATE POLICY pol_fnd_contact_points_tenant ON fnd_contact_points
    FOR ALL
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);
