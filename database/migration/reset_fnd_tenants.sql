-- ============================================================
-- RESET FND_TENANTS (drop + recreate)
-- Target: Supabase (PostgreSQL 15+)
--
-- Prerequisites:
--   • fn_set_updated_at_ts_only from fnd_customers.sql
--   • public.fnd_audit_log (fnd_customers.sql)
--
-- Run before other fnd_* tables that FK to fnd_tenants, or run this
-- only when those tables are empty / dropped. CASCADE drops dependent
-- FKs on fnd_tenants from other tables if they still exist.
--
-- After: re-run ALTER TABLE ... ADD CONSTRAINT referencing fnd_tenants as needed.
-- ============================================================

DROP TABLE IF EXISTS fnd_tenants CASCADE;


-- ============================================================
-- 1. fn_audit_log (same as newTables/fnd_tenants.sql)
-- ============================================================

CREATE OR REPLACE FUNCTION fn_audit_log()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_old_data      JSONB;
    v_new_data      JSONB;
    v_record_id     TEXT;
    v_tenant_id     BIGINT;
    v_pk_col        TEXT := TG_ARGV[0];
    v_tenant_col    TEXT := COALESCE(NULLIF(TG_ARGV[1], ''), 'tenant_id');
    v_actor_text    TEXT;
    v_audit_enabled BOOLEAN;
BEGIN
    IF current_setting('app.audit_enabled', true) = 'false' THEN
        RETURN NULL;
    END IF;

    IF TG_OP = 'UPDATE' AND NEW IS NOT DISTINCT FROM OLD THEN
        RETURN NULL;
    END IF;

    IF TG_OP = 'INSERT' THEN
        v_new_data  := to_jsonb(NEW);
        v_record_id := v_new_data ->> v_pk_col;
        v_tenant_id := (v_new_data ->> v_tenant_col)::BIGINT;

    ELSIF TG_OP = 'UPDATE' THEN
        v_new_data  := to_jsonb(NEW);
        v_record_id := v_new_data ->> v_pk_col;
        v_tenant_id := (v_new_data ->> v_tenant_col)::BIGINT;

    ELSIF TG_OP = 'DELETE' THEN
        v_old_data  := to_jsonb(OLD);
        v_record_id := v_old_data ->> v_pk_col;
        v_tenant_id := (v_old_data ->> v_tenant_col)::BIGINT;
    END IF;

    SELECT t.is_audit_log_enabled
    INTO v_audit_enabled
    FROM fnd_tenants t
    WHERE t.tenant_id = v_tenant_id;

    IF COALESCE(v_audit_enabled, FALSE) = FALSE THEN
        RETURN NULL;
    END IF;

    v_actor_text := COALESCE(
        NULLIF(current_setting('app.audit_actor', true), ''),
        NULLIF(current_setting('request.jwt.claim.sub', true), '')
    );

    INSERT INTO fnd_audit_log (
        tenant_id, table_name, record_id, operation,
        old_data, new_data, changed_columns, changed_by, changed_at
    ) VALUES (
        v_tenant_id, TG_TABLE_NAME, v_record_id, TG_OP,
        v_old_data, v_new_data, NULL, CASE WHEN v_actor_text IS NULL THEN NULL ELSE v_actor_text::UUID END, now()
    );

    RETURN NULL;
END;
$$;


-- ============================================================
-- 2. FND_TENANTS
-- ============================================================

CREATE TABLE fnd_tenants (
    tenant_id        BIGINT      PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),
    tenant_name      TEXT        NOT NULL,
    plan             TEXT        NOT NULL DEFAULT 'STARTER'
                                 CHECK (plan IN ('STARTER', 'PRO', 'ENTERPRISE')),
    is_active        BOOLEAN     NOT NULL DEFAULT TRUE,
    is_audit_log_enabled BOOLEAN NOT NULL DEFAULT FALSE,

    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by       BIGINT,
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by       BIGINT
);

CREATE INDEX IF NOT EXISTS idx_fnd_tenants_active
    ON fnd_tenants (is_active);

-- ============================================================
-- 3–4. Triggers
-- ============================================================

DROP TRIGGER IF EXISTS trg_fnd_tenants_set_updated ON fnd_tenants;
CREATE TRIGGER trg_fnd_tenants_set_updated
    BEFORE UPDATE ON fnd_tenants
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_fnd_tenants_audit ON fnd_tenants;
CREATE TRIGGER trg_fnd_tenants_audit
    AFTER INSERT OR UPDATE OR DELETE ON fnd_tenants
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('tenant_id');


-- ============================================================
-- 5. RLS
-- ============================================================

ALTER TABLE fnd_tenants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_tenants_self ON fnd_tenants;
CREATE POLICY pol_fnd_tenants_self ON fnd_tenants
    FOR ALL
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);


-- ============================================================
-- 6. Seed Alpine Bakery
-- ============================================================

INSERT INTO fnd_tenants (tenant_name, plan)
SELECT 'Alpine Bakery', 'PRO'
WHERE NOT EXISTS (
    SELECT 1 FROM fnd_tenants WHERE tenant_name = 'Alpine Bakery'
);


-- ============================================================
-- 7. Optional: backfill fnd_customers + FK (only if fnd_customers exists)
-- ============================================================

DO $$
DECLARE
    v_tenant_id BIGINT;
BEGIN
    IF to_regclass('public.fnd_customers') IS NULL THEN
        RAISE NOTICE 'reset_fnd_tenants: fnd_customers missing — skip backfill / fk_fnd_customers_tenant.';
        RETURN;
    END IF;

    SELECT tenant_id INTO v_tenant_id
    FROM fnd_tenants
    WHERE tenant_name = 'Alpine Bakery'
    LIMIT 1;

    UPDATE fnd_customers SET tenant_id = v_tenant_id;

    RAISE NOTICE 'fnd_customers.tenant_id updated to %', v_tenant_id;

    BEGIN
        ALTER TABLE fnd_customers
            ADD CONSTRAINT fk_fnd_customers_tenant
            FOREIGN KEY (tenant_id) REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE;
    EXCEPTION
        WHEN duplicate_object THEN NULL;
    END;
END $$;
