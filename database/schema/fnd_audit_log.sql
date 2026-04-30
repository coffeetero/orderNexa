-- ============================================================
-- FND_AUDIT_LOG  –  Shared audit log table + trigger function
-- Target: Supabase (PostgreSQL 15+)
--
-- Run after: fnd_entity_id_seq.sql, fnd_tenants.sql
-- Run before: any table scripts that create audit triggers using fn_audit_log().
-- ============================================================

-- ============================================================
-- 1. AUDIT LOG TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS fnd_audit_log (
    id               BIGINT      PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),
    tenant_id        BIGINT,
    table_name       TEXT        NOT NULL,
    record_id        TEXT,
    operation        TEXT        NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    old_data         JSONB,
    new_data         JSONB,
    changed_columns  TEXT[],
    changed_by       UUID,
    changed_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_audit_log_table_record
    ON fnd_audit_log (table_name, record_id);

CREATE INDEX IF NOT EXISTS idx_audit_log_tenant_time
    ON fnd_audit_log (tenant_id, changed_at DESC);

DROP INDEX IF EXISTS idx_audit_log_changed_at;
DROP INDEX IF EXISTS idx_audit_log_operation;


-- ============================================================
-- 2. fn_audit_log  (requires fnd_tenants + fnd_audit_log)
-- ============================================================

CREATE OR REPLACE FUNCTION fn_audit_log()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
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
        v_new_data := to_jsonb(NEW);
        v_record_id := v_new_data ->> v_pk_col;
        v_tenant_id := (v_new_data ->> v_tenant_col)::BIGINT;

    ELSIF TG_OP = 'UPDATE' THEN
        v_new_data := to_jsonb(NEW);
        v_record_id := v_new_data ->> v_pk_col;
        v_tenant_id := (v_new_data ->> v_tenant_col)::BIGINT;

    ELSIF TG_OP = 'DELETE' THEN
        v_old_data := to_jsonb(OLD);
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
        tenant_id,
        table_name,
        record_id,
        operation,
        old_data,
        new_data,
        changed_columns,
        changed_by,
        changed_at
    )
    VALUES (
        v_tenant_id,
        TG_TABLE_NAME,
        v_record_id,
        TG_OP,
        v_old_data,
        v_new_data,
        NULL,
        CASE WHEN v_actor_text IS NULL THEN NULL ELSE v_actor_text::UUID END,
        now()
    );

    RETURN NULL;
END;
$$;


-- ============================================================
-- 3. ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE fnd_audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_audit_log_tenant_read ON fnd_audit_log;

CREATE POLICY pol_fnd_audit_log_tenant_read ON fnd_audit_log
    FOR SELECT
    USING (
        tenant_id::text = ANY (
            ARRAY(
                SELECT jsonb_array_elements_text(
                    auth.jwt() -> 'app_metadata' -> 'allowed_tenant_ids'
                )
            )
        )
    );
