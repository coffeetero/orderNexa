-- ============================================================
-- RESET FND_CUSTOMERS (drop + recreate + reattach FKs)
-- Target: Supabase (PostgreSQL 15+)
--
-- Destroys all rows in fnd_customers. Drops any dependent objects
-- that reference this table (CASCADE) — review before running.
--
-- Prerequisites (run once per database, before this script):
--   • fnd_entity_id_seq (newTables/fnd_entity_id_seq.sql)
--   • fnd_customers (customer_type is TEXT)
--   • fnd_audit_log, fn_set_updated_at_ts_only, fn_audit_log — from fnd_customers.sql
--   • fnd_tenants (for FK targets)
--   • fnd_pricebooks.sql, fnd_customer_pricebooks.sql (customer ↔ price book links)
--
-- After this script:
--   1) Run seed_fnd_customers.sql to load from legacy public.customer
--      (or insert your own seed rows).
-- ============================================================

DROP TABLE IF EXISTS fnd_customers CASCADE;

CREATE SEQUENCE IF NOT EXISTS fnd_entity_id_seq
    AS BIGINT
    START WITH 200000000001
    INCREMENT BY 1
    MINVALUE 1
    NO MAXVALUE
    CACHE 1;

CREATE TABLE fnd_customers (
    customer_id            BIGINT      PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),

    legacy_id              INT,
    customer_parent_id     BIGINT      REFERENCES fnd_customers(customer_id),

    customer_name          TEXT        NOT NULL,
    customer_number        TEXT,

    customer_type          TEXT        NOT NULL,

    invoice_copy_count         INT     NOT NULL DEFAULT 1  CHECK (invoice_copy_count >= 1),
    is_standing_order          BOOLEAN NOT NULL DEFAULT FALSE,
    is_signature_required      BOOLEAN NOT NULL DEFAULT FALSE,
    is_active                  BOOLEAN NOT NULL DEFAULT TRUE,
    is_label_required          BOOLEAN NOT NULL DEFAULT FALSE,
    is_invoice_required        BOOLEAN NOT NULL DEFAULT FALSE,
    is_cost_on_invoice         BOOLEAN NOT NULL DEFAULT FALSE,
    is_cost_on_bill_of_lading  BOOLEAN NOT NULL DEFAULT FALSE,
    is_returns_allowed         BOOLEAN NOT NULL DEFAULT TRUE,

    tenant_id     BIGINT      NOT NULL,

    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by    BIGINT,
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by    BIGINT,
    UNIQUE (tenant_id, customer_number),
    UNIQUE (tenant_id, legacy_id)
);

CREATE INDEX IF NOT EXISTS idx_fnd_customers_tenant_id
    ON fnd_customers (tenant_id);

CREATE INDEX IF NOT EXISTS idx_fnd_customers_legacy_id
    ON fnd_customers (legacy_id);

CREATE INDEX IF NOT EXISTS idx_fnd_customers_parent
    ON fnd_customers (customer_parent_id);

DROP TRIGGER IF EXISTS trg_fnd_customers_set_updated ON fnd_customers;
CREATE TRIGGER trg_fnd_customers_set_updated
    BEFORE UPDATE ON fnd_customers
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_fnd_customers_audit ON fnd_customers;
CREATE TRIGGER trg_fnd_customers_audit
    AFTER INSERT OR UPDATE OR DELETE ON fnd_customers
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('customer_id');

ALTER TABLE fnd_customers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_customers_tenant ON fnd_customers;
CREATE POLICY pol_fnd_customers_tenant ON fnd_customers
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);

-- FK to tenant (same as fnd_tenants.sql)
DO $$ BEGIN
    ALTER TABLE fnd_customers
        ADD CONSTRAINT fk_fnd_customers_tenant
        FOREIGN KEY (tenant_id) REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

-- ============================================================
-- SEED: seed_fnd_customers.sql, then seed_fnd_customer_pricebooks.sql (requires legacy public.customer).
-- ============================================================
