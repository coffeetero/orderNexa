-- ============================================================
-- FND SCHEMA  –  Foundation Tables
-- Target: Supabase (PostgreSQL 15+)
--
-- customer_id uses the global sequence fnd_entity_id_seq (run fnd_entity_id_seq.sql before this file).
-- tenant_id is BIGINT (FK to fnd_tenants, ON DELETE CASCADE). created_by / updated_by are BIGINT (app user id).
--
-- Typical run order:
--   1) fnd_entity_id_seq.sql   2) fnd_customers.sql (creates fnd_tenants + fnd_customers)
--   3) fnd_audit_log.sql (creates fnd_audit_log + fn_audit_log + RLS)
--   4) fnd_tenants.sql (tenant triggers + RLS only)   5) fnd_items.sql …
--   • After fnd_pricebooks.sql: fnd_customer_pricebooks.sql links customers to price books.
-- ============================================================


-- ============================================================
-- 0. FND_TENANTS  (must exist before fnd_customers.tenant_id FK)
--    Full DDL also documented in fnd_tenants.sql; table is created here for load order.
-- ============================================================

CREATE TABLE IF NOT EXISTS fnd_tenants (
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
-- 1. FND_CUSTOMERS
-- ============================================================

CREATE TABLE IF NOT EXISTS fnd_customers (
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

-- FK fnd_customers.tenant_id -> fnd_tenants.tenant_id
DO $$ BEGIN
    ALTER TABLE fnd_customers
        ADD CONSTRAINT fk_fnd_customers_tenant
        FOREIGN KEY (tenant_id) REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    IF EXISTS (
        SELECT 1
        FROM   information_schema.columns
        WHERE  table_schema = 'public'
          AND  table_name   = 'fnd_customers'
          AND  column_name  = 'org_type'
    ) THEN
        ALTER TABLE fnd_customers RENAME COLUMN org_type TO customer_type;
    END IF;
END $$;

-- Legacy: customer_type was enum — convert to plain text and drop enum types
DO $$ BEGIN
    IF EXISTS (
        SELECT 1
        FROM   information_schema.columns
        WHERE  table_schema = 'public'
          AND  table_name   = 'fnd_customers'
          AND  column_name  = 'customer_type'
          AND  udt_name IN ('customer_type_enum', 'org_type_enum')
    ) THEN
        ALTER TABLE fnd_customers
            ALTER COLUMN customer_type TYPE TEXT USING customer_type::text;
    END IF;
END $$;

DROP TYPE IF EXISTS customer_type_enum CASCADE;
DROP TYPE IF EXISTS org_type_enum CASCADE;

COMMENT ON COLUMN fnd_customers.customer_type IS
    'Hierarchy role (text): ACCOUNT — bill-to / top-level; SITE — invoiced under an account; LOCATION — delivery point, not invoiced directly.';

CREATE INDEX IF NOT EXISTS idx_fnd_customers_tenant_id
    ON fnd_customers (tenant_id);

CREATE INDEX IF NOT EXISTS idx_fnd_customers_legacy_id
    ON fnd_customers (legacy_id);

CREATE INDEX IF NOT EXISTS idx_fnd_customers_parent
    ON fnd_customers (customer_parent_id);

CREATE INDEX IF NOT EXISTS idx_fnd_customers_active
    ON fnd_customers (tenant_id)
    WHERE is_active = TRUE;

-- ============================================================
-- 2. TRIGGER FUNCTIONS  –  updated_at
-- ============================================================

CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    NEW.updated_by := auth.uid();
    RETURN NEW;
END;
$$;

-- For tables where updated_by is BIGINT (not auth UUID)
CREATE OR REPLACE FUNCTION fn_set_updated_at_ts_only()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_fnd_customers_set_updated ON fnd_customers;
CREATE TRIGGER trg_fnd_customers_set_updated
    BEFORE UPDATE ON fnd_customers
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();


-- ============================================================
-- 3. AUDIT TRIGGER (requires fn_audit_log from fnd_audit_log.sql)
-- ============================================================

DROP TRIGGER IF EXISTS trg_fnd_customers_audit ON fnd_customers;
CREATE TRIGGER trg_fnd_customers_audit
    AFTER INSERT OR UPDATE OR DELETE ON fnd_customers
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('customer_id');


-- ============================================================
-- 4. ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE fnd_customers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_customers_tenant ON fnd_customers;

CREATE POLICY pol_fnd_customers_tenant ON fnd_customers
    USING (
        -- 1. Use current_setting to grab the JWT claim without calling the auth schema function
        (tenant_id::text = ANY (
            ARRAY(
                SELECT jsonb_array_elements_text(
                    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids'
                )
            )
        ))
        AND (
            -- 2. Check restricted tenants
            NOT (tenant_id::text = ANY (
                ARRAY(
                    SELECT jsonb_array_elements_text(
                        NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'
                    )
                )
            ))
            OR 
            -- 3. Check allowed customers
            (customer_id::text = ANY (
                ARRAY(
                    SELECT jsonb_array_elements_text(
                        NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_customer_ids'
                    )
                )
            ))
        )
    );