-- ============================================================
-- OM_SHIPMENT_LINES  –  What a shipment carries: one row per order line
--
-- (Formerly om_order_shipments, a flat per-line event table; the header now lives in om_shipments.)
-- quantity = planned quantity (from the order line at processing); shipped_quantity = confirmed at delivery (NULL until then).
-- AR recognises an invoice line from shipped_quantity once its shipment is SHIPPED/DELIVERED.
--
-- shipment_line_id uses fnd_entity_id_seq.
-- Run after: om_shipments.sql, om_orders.sql, om_order_lines.sql. Policies: ../policies/om_shipment_lines_policies.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS om_shipment_lines (
    tenant_id          BIGINT        NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,
    shipment_line_id   BIGINT        PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),
    shipment_id        BIGINT        NOT NULL REFERENCES om_shipments(shipment_id) ON DELETE CASCADE,
    order_id           BIGINT        NOT NULL REFERENCES om_orders(order_id) ON DELETE CASCADE,
    order_line_id      BIGINT        REFERENCES om_order_lines(order_line_id) ON DELETE CASCADE,
    quantity           NUMERIC(14,4) NOT NULL CHECK (quantity > 0),
    shipped_quantity   NUMERIC(14,4) CHECK (shipped_quantity >= 0),
    snapshot_data      JSONB         NOT NULL DEFAULT '{}'::jsonb,

    created_at         TIMESTAMPTZ   NOT NULL DEFAULT now(),
    created_by         BIGINT,
    updated_at         TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_by         BIGINT
);

-- Ownership: application tables are owned by bps_owner; runtime access is via grants + RLS.
ALTER TABLE om_shipment_lines OWNER TO bps_owner;

CREATE INDEX IF NOT EXISTS idx_om_shipment_lines_shipment ON om_shipment_lines (tenant_id, shipment_id);
CREATE INDEX IF NOT EXISTS idx_om_shipment_lines_order ON om_shipment_lines (tenant_id, order_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_om_shipment_lines_order_line
    ON om_shipment_lines (tenant_id, order_line_id) WHERE order_line_id IS NOT NULL;

DROP TRIGGER IF EXISTS trg_om_shipment_lines_set_updated ON om_shipment_lines;
CREATE TRIGGER trg_om_shipment_lines_set_updated
    BEFORE UPDATE ON om_shipment_lines
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_om_shipment_lines_audit ON om_shipment_lines;
CREATE TRIGGER trg_om_shipment_lines_audit
    AFTER INSERT OR UPDATE OR DELETE ON om_shipment_lines
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('shipment_line_id');

COMMENT ON TABLE om_shipment_lines IS
    'Shipment detail: planned quantity per order line (one shipment per order line) and the quantity actually shipped.';
