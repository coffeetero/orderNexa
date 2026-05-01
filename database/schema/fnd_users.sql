-- ============================================================
-- FND_USERS  –  Application users (tenant-scoped, Supabase auth link)
-- Target: Supabase (PostgreSQL 15+)
--
-- user_id uses the global fnd_entity_id_seq (run fnd_entity_id_seq.sql before this file).
-- created_by / updated_by are BIGINT app user ids — not auth.uid() (use fn_set_updated_at_ts_only).
-- Run after: fnd_tenants.sql, fnd_customers.sql (fn_set_updated_at_ts_only, fnd_audit_log, fn_audit_log).
-- fnd_tenants required for tenant_id FK.
-- ============================================================

CREATE TABLE IF NOT EXISTS fnd_users (
    user_id           BIGINT      PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),

    tenant_id         BIGINT        NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,

    auth_user_id      UUID        NOT NULL UNIQUE,
    user_name         TEXT,
    email             TEXT,

    last_login_at     TIMESTAMPTZ,
    deleted_at        TIMESTAMPTZ,

    is_active         BOOLEAN     NOT NULL DEFAULT TRUE,
    can_debug         BOOLEAN     NOT NULL DEFAULT FALSE,

    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by        BIGINT,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by        BIGINT
);

DO $$ BEGIN
    IF EXISTS (
        SELECT 1
        FROM   information_schema.columns
        WHERE  table_schema = 'public'
          AND  table_name   = 'fnd_users'
          AND  column_name  = 'login_user_id'
    ) THEN
        ALTER TABLE fnd_users RENAME COLUMN login_user_id TO auth_user_id;
    END IF;
END $$;

ALTER TABLE fnd_users ADD COLUMN IF NOT EXISTS email TEXT;

ALTER TABLE fnd_users ADD COLUMN IF NOT EXISTS can_debug BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN fnd_users.tenant_id IS
    'Tenant scope; BIGINT FK to fnd_tenants.tenant_id.';
COMMENT ON COLUMN fnd_users.auth_user_id IS
    'Maps to auth.users.id.';
COMMENT ON COLUMN fnd_users.email IS
    'Contact / login email (optional; may mirror auth.users.email).';
COMMENT ON COLUMN fnd_users.can_debug IS
    'When true, user may use diagnostic / debug tooling (e.g. elevated RPCs).';

CREATE INDEX IF NOT EXISTS idx_fnd_users_tenant_id
    ON fnd_users (tenant_id);

CREATE INDEX IF NOT EXISTS idx_fnd_users_active
    ON fnd_users (tenant_id)
    WHERE is_active = TRUE AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_fnd_users_tenant_email
    ON fnd_users (tenant_id, email)
    WHERE email IS NOT NULL;

DROP TRIGGER IF EXISTS trg_fnd_users_set_updated ON fnd_users;
CREATE TRIGGER trg_fnd_users_set_updated
    BEFORE UPDATE ON fnd_users
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_fnd_users_audit ON fnd_users;
CREATE TRIGGER trg_fnd_users_audit
    AFTER INSERT OR UPDATE OR DELETE ON fnd_users
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('user_id');

ALTER TABLE fnd_users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_users_tenant ON fnd_users;
CREATE POLICY pol_fnd_users_tenant ON fnd_users
    FOR ALL
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);
