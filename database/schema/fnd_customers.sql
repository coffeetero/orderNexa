-- ============================================================
-- FND SCHEMA  –  Foundation Tables
-- Target: Supabase (PostgreSQL 15+)
--
-- Schema: unqualified identifiers — set search_path before apply, e.g. SET search_path = bps, public;
--
-- customer_id uses the global sequence fnd_entity_id_seq (run fnd_entity_id_seq.sql before this file).
-- tenant_id is BIGINT (FK to fnd_tenants, ON DELETE CASCADE). created_by / updated_by are BIGINT (app user id).
--
-- Typical run order:
--   1) fnd_entity_id_seq.sql   2) fnd_tenants.sql (fnd_tenants table)   3) fnd_customers.sql (this file)
--   4) fnd_audit_log.sql (creates fnd_audit_log + fn_audit_log + RLS)   5) fnd_items.sql …
--   • After fnd_pricebooks.sql: fnd_customer_pricebooks.sql links customers to price books.
-- ============================================================

-- ============================================================
-- 1. FND_CUSTOMERS
-- ============================================================

CREATE TABLE IF NOT EXISTS fnd_customers (
    tenant_id                  BIGINT      NOT NULL,
    customer_id            BIGINT      PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),

    legacy_id              INT,
    customer_parent_id     BIGINT      REFERENCES fnd_customers(customer_id),
    top_customer_id        BIGINT      REFERENCES fnd_customers(customer_id),

    customer_name          TEXT        NOT NULL,
    customer_number        TEXT,

    customer_type          TEXT        NOT NULL,

    billing_type               TEXT,                   -- ACCOUNT | COD
    billing_period             TEXT,                   -- DAILY | WEEKLY | MONTHLY
    credit_limit               NUMERIC(12,2),          -- NULL = no limit

    invoice_copy_count         INT     NOT NULL DEFAULT 1  CHECK (invoice_copy_count >= 1),
    is_standing_order          BOOLEAN NOT NULL DEFAULT FALSE,
    is_signature_required      BOOLEAN NOT NULL DEFAULT FALSE,

    is_active                  BOOLEAN NOT NULL DEFAULT TRUE,
    is_label_required          BOOLEAN NOT NULL DEFAULT FALSE,
    is_invoice_required        BOOLEAN NOT NULL DEFAULT FALSE,
    is_cost_on_invoice         BOOLEAN NOT NULL DEFAULT FALSE,
    is_cost_on_bill_of_lading  BOOLEAN NOT NULL DEFAULT FALSE,
    is_returns_allowed         BOOLEAN NOT NULL DEFAULT TRUE,

    created_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                 BIGINT,
    updated_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                 BIGINT,

    account_slug               TEXT,

    UNIQUE (tenant_id, customer_number)
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
        WHERE  table_schema = current_schema()
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
        WHERE  table_schema = current_schema()
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

UPDATE fnd_customers
   SET customer_type = 'DEPARTMENT'
 WHERE UPPER(TRIM(customer_type)) = 'LOCATION';

COMMENT ON COLUMN fnd_customers.customer_type IS
    'Hierarchy role (text): ACCOUNT — bill-to / top-level; SITE — invoiced under an account; DEPARTMENT — department/event grouping, not invoiced directly.';

CREATE INDEX IF NOT EXISTS idx_fnd_customers_tenant_id
    ON fnd_customers (tenant_id);

CREATE INDEX IF NOT EXISTS idx_fnd_customers_legacy_id
    ON fnd_customers (legacy_id);

CREATE INDEX IF NOT EXISTS idx_fnd_customers_parent
    ON fnd_customers (customer_parent_id);

ALTER TABLE fnd_customers
    ADD COLUMN IF NOT EXISTS top_customer_id BIGINT REFERENCES fnd_customers(customer_id);

CREATE INDEX IF NOT EXISTS idx_fnd_customers_top_customer
    ON fnd_customers (tenant_id, top_customer_id);

CREATE INDEX IF NOT EXISTS idx_fnd_customers_active
    ON fnd_customers (tenant_id)
    WHERE is_active = TRUE;

WITH RECURSIVE customer_tree AS (
    SELECT
        cus.tenant_id,
        cus.customer_id,
        cus.customer_id AS resolved_top_customer_id,
        ARRAY[cus.customer_id]::BIGINT[] AS path_ids
    FROM fnd_customers cus
    WHERE cus.customer_parent_id IS NULL

    UNION ALL

    SELECT
        child.tenant_id,
        child.customer_id,
        parent.resolved_top_customer_id,
        parent.path_ids || child.customer_id
    FROM fnd_customers child
    JOIN customer_tree parent
      ON parent.tenant_id = child.tenant_id
     AND parent.customer_id = child.customer_parent_id
    WHERE NOT child.customer_id = ANY(parent.path_ids)
)
UPDATE fnd_customers cus
   SET top_customer_id = tree.resolved_top_customer_id
  FROM customer_tree tree
 WHERE tree.tenant_id = cus.tenant_id
   AND tree.customer_id = cus.customer_id
   AND cus.top_customer_id IS DISTINCT FROM tree.resolved_top_customer_id;

UPDATE fnd_customers
   SET top_customer_id = customer_id
 WHERE top_customer_id IS NULL;

COMMENT ON COLUMN fnd_customers.top_customer_id IS
    'Top account customer for hierarchy access checks and grouping; equals customer_id for top-level accounts.';

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

-- RLS policies: fnd_customers_policies.sql
