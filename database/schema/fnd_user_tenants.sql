-- ============================================================
-- FND_USER_TENANTS  –  User membership per tenant (many-to-many)
-- Target: Supabase (PostgreSQL 15+)
--
-- user_tenant_id uses fnd_entity_id_seq (run fnd_entity_id_seq.sql before this file).
-- created_by / updated_by are BIGINT app user ids — not auth.uid() (use fn_set_updated_at_ts_only).
-- Run after: fnd_tenants.sql, fnd_customers.sql, fnd_users.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS fnd_user_tenants (
    user_tenant_id    BIGINT      PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),

    tenant_id         BIGINT        NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,
    user_id           BIGINT      NOT NULL REFERENCES fnd_users(user_id) ON DELETE CASCADE,

    is_active              BOOLEAN     NOT NULL DEFAULT TRUE,
    is_customer_restricted BOOLEAN     NOT NULL DEFAULT FALSE,

    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by        BIGINT,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by        BIGINT,

    CONSTRAINT uq_fnd_user_tenants_tenant_user UNIQUE (tenant_id, user_id)
);

ALTER TABLE fnd_user_tenants
    ADD COLUMN IF NOT EXISTS is_customer_restricted BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN fnd_user_tenants.is_customer_restricted IS
    'When true, user access to customers is limited to rows in fnd_user_customers for this tenant.';

CREATE INDEX IF NOT EXISTS idx_fnd_user_tenants_tenant_id
    ON fnd_user_tenants (tenant_id);

CREATE INDEX IF NOT EXISTS idx_fnd_user_tenants_user_id
    ON fnd_user_tenants (user_id);

CREATE INDEX IF NOT EXISTS idx_fnd_user_tenants_active
    ON fnd_user_tenants (tenant_id)
    WHERE is_active = TRUE;

DROP TRIGGER IF EXISTS trg_fnd_user_tenants_set_updated ON fnd_user_tenants;
CREATE TRIGGER trg_fnd_user_tenants_set_updated
    BEFORE UPDATE ON fnd_user_tenants
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_fnd_user_tenants_audit ON fnd_user_tenants;
CREATE TRIGGER trg_fnd_user_tenants_audit
    AFTER INSERT OR UPDATE OR DELETE ON fnd_user_tenants
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('user_tenant_id');

ALTER TABLE fnd_user_tenants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_user_tenants_tenant ON fnd_user_tenants;
CREATE POLICY pol_fnd_user_tenants_tenant ON fnd_user_tenants
    FOR ALL
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);
