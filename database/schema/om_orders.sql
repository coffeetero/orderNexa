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
    order_id                BIGINT      PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),
    order_number            TEXT        NOT NULL,   -- app-facing, source: ordr.ordr_no
    order_date              DATE,                   -- source: ordr.ordr_dt
    order_source            TEXT,                   -- Web, Clerk, Fax, Electronic, SORDER (set by app / later migration)
    quantity                NUMERIC(14,4) NOT NULL,   -- ordr_qty_sold
    amount                  NUMERIC(14,4) NOT NULL,   -- ordr_amt
    discount_amount         NUMERIC(14,4) NOT NULL,   -- ordr_discount_amt
    customer_id             BIGINT      REFERENCES fnd_customers(customer_id),  -- source: ordr.cus_id (nullable: legacy rows without cus_id)
    event_location          TEXT,
    delivery_date           DATE        NOT NULL,   -- source: ordr.ordr_prdctn_dt
    delivery_window         TEXT,                   -- source: ordr.ordr_prdctn_cd
    snapshot_data           JSONB       NOT NULL DEFAULT '{}'::jsonb,
    tenant_id               BIGINT        NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,
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

CREATE INDEX IF NOT EXISTS idx_om_orders_delivery_date
    ON om_orders (tenant_id, delivery_date DESC);

-- TRIGGERS
DROP TRIGGER IF EXISTS trg_om_orders_set_updated ON om_orders;
CREATE TRIGGER trg_om_orders_set_updated
    BEFORE UPDATE ON om_orders
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_om_orders_audit ON om_orders;
CREATE TRIGGER trg_om_orders_audit
    AFTER INSERT OR UPDATE OR DELETE ON om_orders
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('order_id');

-- RLS
ALTER TABLE om_orders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_om_orders_tenant ON om_orders;
CREATE POLICY pol_om_orders_tenant ON om_orders
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);
