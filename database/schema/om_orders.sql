-- ============================================================
-- om_orders  –  Sales order header (legacy: ordr)
-- Target: Supabase (PostgreSQL 15+)
--
-- order_number    ← ordr.ordr_no as text (unique per tenant)
-- customer_id     ← ordr.cus_id via fnd_customers.legacy_id
--
-- snapshot_data (JSONB) — stable app-facing keys at top level:
--   cus_name   (text, nullable)  ← ordr.cus_name
--   cus_key    (text, nullable)  ← ordr.cus_key
--   route_id   (number, nullable) ← ordr.route_id
--   route_no   (number, nullable) ← ordr.route_stop_no (legacy stop / sequence on route)
--
-- Run after: fnd_entity_id_seq.sql, fnd_customers.sql (functions), fnd_tenants.sql
-- Lines: ordr_detail → om_order_lines (see om_order_lines.sql, seed_om_order_lines.sql)
-- ============================================================

CREATE TABLE IF NOT EXISTS om_orders (
    tenant_id               BIGINT        NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,
    order_id                BIGINT      PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),
    order_number            TEXT        NOT NULL,   -- app-facing, source: ordr.ordr_no
    order_date              DATE,                   -- source: ordr.ordr_dt
    order_source            TEXT,                   -- Web, Clerk, Fax, Electronic, SORDER (set by app / later migration)
    quantity                NUMERIC(14,4) NOT NULL,   -- ordr_qty_sold
    amount                  NUMERIC(14,4) NOT NULL,   -- ordr_amt
    discount_amount         NUMERIC(14,4) NOT NULL,   -- ordr_discount_amt
    customer_id             BIGINT      REFERENCES fnd_customers(customer_id),  -- source: ordr.cus_id (nullable: legacy rows without cus_id)
    customer_name           TEXT,
    department_event          TEXT        NOT NULL DEFAULT '',
    production_date         DATE        NOT NULL,   -- source: ordr.ordr_prdctn_dt
    production_code         TEXT,                   -- source: ordr.ordr_prdctn_cd (AM / PM / SPECIAL)
    snapshot_data           JSONB       NOT NULL DEFAULT '{}'::jsonb,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by              BIGINT,
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by              BIGINT,

    UNIQUE (tenant_id, order_number)
);

CREATE INDEX IF NOT EXISTS idx_om_orders_tenant_id
    ON om_orders (tenant_id);

CREATE INDEX IF NOT EXISTS idx_om_orders_customer
    ON om_orders (tenant_id, customer_id);

ALTER TABLE om_orders
    ADD COLUMN IF NOT EXISTS customer_name TEXT;

UPDATE om_orders o
   SET customer_name = COALESCE(c.customer_name, o.snapshot_data->>'cus_name')
  FROM fnd_customers c
 WHERE c.tenant_id = o.tenant_id
   AND c.customer_id = o.customer_id
   AND o.customer_name IS NULL;

UPDATE om_orders
   SET customer_name = snapshot_data->>'cus_name'
 WHERE customer_name IS NULL
   AND snapshot_data ? 'cus_name';

UPDATE om_orders o
   SET customer_id = parent.customer_id,
       customer_name = parent.customer_name,
       department_event =
           COALESCE(NULLIF(UPPER(TRIM(o.department_event)), ''), UPPER(TRIM(location.customer_name)), '')
           || '-' || o.order_number
  FROM fnd_customers location
  JOIN fnd_customers parent
    ON parent.tenant_id = location.tenant_id
   AND parent.customer_id = location.customer_parent_id
 WHERE location.tenant_id = o.tenant_id
   AND location.customer_id = o.customer_id
   AND UPPER(TRIM(location.customer_type)) = 'LOCATION'
   AND location.customer_parent_id IS NOT NULL;

UPDATE om_orders
   SET production_code = NULLIF(UPPER(TRIM(production_code)), ''),
       department_event = COALESCE(NULLIF(UPPER(TRIM(department_event)), ''), '')
 WHERE production_code IS DISTINCT FROM NULLIF(UPPER(TRIM(production_code)), '')
    OR department_event IS DISTINCT FROM COALESCE(NULLIF(UPPER(TRIM(department_event)), ''), '');

CREATE INDEX IF NOT EXISTS idx_om_orders_production_date
    ON om_orders (tenant_id, production_date DESC);

CREATE INDEX IF NOT EXISTS idx_om_orders_existing_customer_slot
    ON om_orders (tenant_id, customer_id, production_date, production_code);

CREATE INDEX IF NOT EXISTS idx_om_orders_existing_slot
    ON om_orders (tenant_id, production_date, production_code);

CREATE UNIQUE INDEX IF NOT EXISTS uq_om_orders_slot_department_event
    ON om_orders (tenant_id, customer_id, production_date, production_code, department_event)
    NULLS NOT DISTINCT;

-- TRIGGERS
DROP TRIGGER IF EXISTS trg_om_orders_set_updated ON om_orders;
CREATE TRIGGER trg_om_orders_set_updated
    BEFORE UPDATE ON om_orders
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_om_orders_audit ON om_orders;
CREATE TRIGGER trg_om_orders_audit
    AFTER INSERT OR UPDATE OR DELETE ON om_orders
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('order_id');

-- RLS policies: om_orders_policies.sql
