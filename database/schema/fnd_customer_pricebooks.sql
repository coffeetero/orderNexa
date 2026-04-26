-- ============================================================
-- FND_CUSTOMER_PRICEBOOKS  –  Which price books apply to a customer
-- Target: Supabase (PostgreSQL 15+)
--
-- Replaces promo_pricebook_id / pricebook_id / default_pricebook_id on fnd_customers.
-- Effective dating lives here (not on fnd_pricebooks).
--
-- Prerequisites:
--   • fnd_entity_id_seq.sql
--   • fnd_customers.sql, fnd_tenants.sql
--   • fnd_pricebooks.sql
-- ============================================================

-- ============================================================
-- 1. TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS fnd_customer_pricebooks (
    customer_pricebook_id   BIGINT      PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),

    customer_id               BIGINT      NOT NULL REFERENCES fnd_customers(customer_id) ON DELETE CASCADE,
    pricebook_id              BIGINT      NOT NULL REFERENCES fnd_pricebooks(pricebook_id) ON DELETE RESTRICT,

    assignment_type           TEXT        NOT NULL,

    effective_start_date      DATE        NOT NULL,
    effective_end_date        DATE,

    is_active                 BOOLEAN     NOT NULL DEFAULT TRUE,

    tenant_id                 BIGINT        NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,

    created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                BIGINT,
    updated_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                BIGINT,

    CONSTRAINT chk_fnd_customer_pricebooks_effective_range
        CHECK (effective_end_date IS NULL OR effective_end_date >= effective_start_date)
);

ALTER TABLE fnd_customer_pricebooks ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE;

CREATE INDEX IF NOT EXISTS idx_fnd_customer_pricebooks_tenant_id
    ON fnd_customer_pricebooks (tenant_id);

CREATE INDEX IF NOT EXISTS idx_fnd_customer_pricebooks_customer_id
    ON fnd_customer_pricebooks (customer_id);

CREATE INDEX IF NOT EXISTS idx_fnd_customer_pricebooks_pricebook_id
    ON fnd_customer_pricebooks (pricebook_id);

CREATE INDEX IF NOT EXISTS idx_fnd_customer_pricebooks_tenant_active
    ON fnd_customer_pricebooks (tenant_id)
    WHERE is_active = TRUE;

CREATE UNIQUE INDEX IF NOT EXISTS uq_fnd_customer_pricebooks_customer_assignment
    ON fnd_customer_pricebooks (customer_id, assignment_type);


-- ============================================================
-- 2. TRIGGERS
-- ============================================================

DROP TRIGGER IF EXISTS trg_fnd_customer_pricebooks_set_updated ON fnd_customer_pricebooks;
CREATE TRIGGER trg_fnd_customer_pricebooks_set_updated
    BEFORE UPDATE ON fnd_customer_pricebooks
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_fnd_customer_pricebooks_audit ON fnd_customer_pricebooks;
CREATE TRIGGER trg_fnd_customer_pricebooks_audit
    AFTER INSERT OR UPDATE OR DELETE ON fnd_customer_pricebooks
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('customer_pricebook_id');


-- ============================================================
-- 3. ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE fnd_customer_pricebooks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_customer_pricebooks_tenant ON fnd_customer_pricebooks;
CREATE POLICY pol_fnd_customer_pricebooks_tenant ON fnd_customer_pricebooks
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);

COMMENT ON COLUMN fnd_customer_pricebooks.assignment_type IS
    'How this book applies (e.g. PRIMARY, PROMO, DEFAULT).';

COMMENT ON COLUMN fnd_customer_pricebooks.is_active IS
    'When false, this assignment is ignored for pricing resolution.';


-- ============================================================
-- 4. MIGRATION — assignment_type was enum in earlier DDL; use text
-- ============================================================

DO $$ BEGIN
    IF EXISTS (
        SELECT 1
        FROM   information_schema.columns
        WHERE  table_schema = 'public'
          AND  table_name   = 'fnd_customer_pricebooks'
          AND  column_name  = 'assignment_type'
          AND  udt_name     = 'pricebook_assignment_type_enum'
    ) THEN
        ALTER TABLE fnd_customer_pricebooks
            ALTER COLUMN assignment_type TYPE TEXT USING assignment_type::text;
        DROP TYPE IF EXISTS pricebook_assignment_type_enum;
    END IF;
END $$;


-- ============================================================
-- 5. MIGRATION — remove legacy pricebook columns from fnd_customers
-- ============================================================

ALTER TABLE fnd_customers DROP CONSTRAINT IF EXISTS fk_fnd_customers_promo_pricebook;
ALTER TABLE fnd_customers DROP CONSTRAINT IF EXISTS fk_fnd_customers_pricebook;
ALTER TABLE fnd_customers DROP CONSTRAINT IF EXISTS fk_fnd_customers_default_pricebook;

DROP INDEX IF EXISTS idx_fnd_customers_promo_pricebook;
DROP INDEX IF EXISTS idx_fnd_customers_pricebook;
DROP INDEX IF EXISTS idx_fnd_customers_default_pricebook;

ALTER TABLE fnd_customers DROP COLUMN IF EXISTS promo_pricebook_id;
ALTER TABLE fnd_customers DROP COLUMN IF EXISTS pricebook_id;
ALTER TABLE fnd_customers DROP COLUMN IF EXISTS default_pricebook_id;
