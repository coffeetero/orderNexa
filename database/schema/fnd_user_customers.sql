-- ============================================================
-- FND_USER_CUSTOMERS  –  Which customers a user may access (per tenant)
-- Target: Supabase (PostgreSQL 15+)
--
-- user_customer_id uses fnd_entity_id_seq (run fnd_entity_id_seq.sql before this file).
-- created_by / updated_by are BIGINT app user ids — not auth.uid() (use fn_set_updated_at_ts_only).
--
-- Composite FK (customer_id, tenant_id) → fnd_customers requires a unique key on those
-- columns on the parent (added below if missing).
--
-- Run after: fnd_tenants.sql, fnd_customers.sql, fnd_users.sql
-- ============================================================

-- Parent must expose (customer_id, tenant_id) as a unique target for the composite FK.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = 'public'
          AND t.relname = 'fnd_customers'
          AND c.conname = 'uq_fnd_customers_customer_id_tenant'
    ) THEN
        ALTER TABLE fnd_customers
            ADD CONSTRAINT uq_fnd_customers_customer_id_tenant UNIQUE (customer_id, tenant_id);
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS fnd_user_customers (
    user_customer_id   BIGINT      PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),

    user_id            BIGINT      NOT NULL REFERENCES fnd_users(user_id) ON DELETE CASCADE,
    customer_id        BIGINT      NOT NULL,
    tenant_id          BIGINT      NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,

    is_active          BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by         BIGINT,
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by         BIGINT,

    CONSTRAINT uq_fnd_user_customers_tenant_user_customer UNIQUE (tenant_id, user_id, customer_id),

    CONSTRAINT fk_fnd_user_customers_customer_tenant
        FOREIGN KEY (customer_id, tenant_id)
        REFERENCES fnd_customers (customer_id, tenant_id)
        ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_fnd_user_customers_tenant_id
    ON fnd_user_customers (tenant_id);

CREATE INDEX IF NOT EXISTS idx_fnd_user_customers_user_id
    ON fnd_user_customers (user_id);

CREATE INDEX IF NOT EXISTS idx_fnd_user_customers_customer_id
    ON fnd_user_customers (customer_id);

CREATE INDEX IF NOT EXISTS idx_fnd_user_customers_active
    ON fnd_user_customers (tenant_id)
    WHERE is_active = TRUE;

DROP TRIGGER IF EXISTS trg_fnd_user_customers_set_updated ON fnd_user_customers;
CREATE TRIGGER trg_fnd_user_customers_set_updated
    BEFORE UPDATE ON fnd_user_customers
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_fnd_user_customers_audit ON fnd_user_customers;
CREATE TRIGGER trg_fnd_user_customers_audit
    AFTER INSERT OR UPDATE OR DELETE ON fnd_user_customers
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('user_customer_id');

ALTER TABLE fnd_user_customers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_user_customers_tenant ON fnd_user_customers;
CREATE POLICY pol_fnd_user_customers_tenant ON fnd_user_customers
    FOR ALL
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);
