-- ============================================================
-- om_order_lines  –  Sales order line items (legacy: ordr_detail)
-- Target: Supabase (PostgreSQL 15+)
--
-- order_id     ← om_orders (match via ordr_detail.ordr_no → order_number)
-- item_id      ← fnd_items via ordr_detail.item_id → legacy_id (nullable if unknown)
--
-- fulfilled_quantity — units fulfilled (e.g. sum of om_order_shipments.quantity per line; seed default 0).
--
-- Run after: fnd_entity_id_seq.sql, om_orders.sql, fnd_items.sql (fn_set_updated_at_ts_only, fn_audit_log)
-- ============================================================

CREATE TABLE IF NOT EXISTS om_order_lines (
    order_line_id       BIGINT      PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),

    order_id            BIGINT      NOT NULL REFERENCES om_orders(order_id) ON DELETE CASCADE,

    item_id             BIGINT      REFERENCES fnd_items(item_id),
    item_description    TEXT,       -- display text; legacy: ordr_detail.item_desc

    quantity            NUMERIC(14,4) NOT NULL,
    unit_price          NUMERIC(14,4),
    extended_amount     NUMERIC(14,4),
    unit_discount       NUMERIC(14,4) NOT NULL DEFAULT 0,

    fulfilled_quantity  NUMERIC(14,4) NOT NULL DEFAULT 0,

    tenant_id           BIGINT        NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by          BIGINT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by          BIGINT
);

CREATE INDEX IF NOT EXISTS idx_om_order_lines_tenant
    ON om_order_lines (tenant_id);

CREATE INDEX IF NOT EXISTS idx_om_order_lines_order
    ON om_order_lines (tenant_id, order_id);

CREATE INDEX IF NOT EXISTS idx_om_order_lines_item
    ON om_order_lines (tenant_id, item_id);

COMMENT ON COLUMN om_order_lines.item_description IS
    'Line display description; seed from ordr_detail.item_desc.';

COMMENT ON COLUMN om_order_lines.fulfilled_quantity IS
    'Quantity fulfilled for this line; typically maintained from fulfillment events.';


-- TRIGGERS
DROP TRIGGER IF EXISTS trg_om_order_lines_set_updated ON om_order_lines;
CREATE TRIGGER trg_om_order_lines_set_updated
    BEFORE UPDATE ON om_order_lines
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_om_order_lines_audit ON om_order_lines;
CREATE TRIGGER trg_om_order_lines_audit
    AFTER INSERT OR UPDATE OR DELETE ON om_order_lines
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('order_line_id');


-- RLS
ALTER TABLE om_order_lines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_om_order_lines_tenant ON om_order_lines;
CREATE POLICY pol_om_order_lines_tenant ON om_order_lines
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);
