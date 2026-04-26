-- ============================================================
-- FND SCHEMA  –  Foundation Tables
-- Target: Supabase (PostgreSQL 15+)
--
-- customer_id uses the global sequence fnd_entity_id_seq (run fnd_entity_id_seq.sql before this file).
-- tenant_id is BIGINT (FK to fnd_tenants, ON DELETE CASCADE). created_by / updated_by are BIGINT (app user id).
--
-- Typical run order:
--   1) fnd_entity_id_seq.sql   2) fnd_customers.sql (creates fnd_tenants + fnd_customers + audit)
--   3) fnd_tenants.sql (tenant triggers + RLS only)   4) fnd_items.sql …
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
-- 2. AUDIT LOG TABLE
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
-- 2b. fn_audit_log  (requires fnd_tenants + fnd_audit_log)
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
-- 3. TRIGGER FUNCTIONS  –  updated_at
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
-- 4. AUDIT TRIGGER
-- ============================================================

DROP TRIGGER IF EXISTS trg_fnd_customers_audit ON fnd_customers;
CREATE TRIGGER trg_fnd_customers_audit
    AFTER INSERT OR UPDATE OR DELETE ON fnd_customers
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('customer_id');


-- ============================================================
-- 5. ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE fnd_customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE fnd_audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_customers_tenant ON fnd_customers;
CREATE POLICY pol_fnd_customers_tenant ON fnd_customers
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);

DROP POLICY IF EXISTS pol_fnd_audit_log_tenant_read ON fnd_audit_log;
CREATE POLICY pol_fnd_audit_log_tenant_read ON fnd_audit_log
    FOR SELECT
    USING (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);
