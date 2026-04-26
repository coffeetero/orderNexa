-- ============================================================
-- om_order_shipments  -  Append-only shipment events (ship / deliver / pick)
-- Target: Supabase (PostgreSQL 15+)
--
-- Operational truth separate from AR. quantity is the event amount (e.g. units shipped).
--
-- Run after: fnd_entity_id_seq.sql, fnd_tenants.sql, om_orders.sql, om_order_lines.sql
--   (fn_set_updated_at_ts_only, fn_audit_log from fnd_customers.sql chain)
-- ============================================================

CREATE TABLE IF NOT EXISTS om_order_shipments (
    order_shipment_id      BIGINT      PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),
    order_id               BIGINT      NOT NULL REFERENCES om_orders(order_id) ON DELETE CASCADE,
    order_line_id          BIGINT      REFERENCES om_order_lines(order_line_id) ON DELETE CASCADE,

    production_date        DATE,
    production_window      TEXT,

    shipment_date          TIMESTAMPTZ,
    shipment_number        BIGINT      NOT NULL DEFAULT 1,

    quantity               NUMERIC(14,4) NOT NULL CHECK (quantity > 0),
    status                 TEXT,

    delivery_type          TEXT        NOT NULL DEFAULT 'CUSTOMER_DELIVERY',
    delivery_reference     TEXT,
    ship_from_location_id  BIGINT,
    ship_to_location_id    BIGINT,
    snapshot_data          JSONB       NOT NULL DEFAULT '{}'::jsonb,

    tenant_id              BIGINT        NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,

    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by             BIGINT,
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by             BIGINT
);

CREATE INDEX IF NOT EXISTS idx_om_order_shipments_tenant_order
    ON om_order_shipments (tenant_id, order_id, shipment_date DESC);

CREATE INDEX IF NOT EXISTS idx_om_order_shipments_line
    ON om_order_shipments (tenant_id, order_line_id)
    WHERE order_line_id IS NOT NULL;


DROP TRIGGER IF EXISTS trg_om_order_shipments_set_updated ON om_order_shipments;
CREATE TRIGGER trg_om_order_shipments_set_updated
    BEFORE UPDATE ON om_order_shipments
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_om_order_shipments_audit ON om_order_shipments;
CREATE TRIGGER trg_om_order_shipments_audit
    AFTER INSERT OR UPDATE OR DELETE ON om_order_shipments
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('order_shipment_id');


ALTER TABLE om_order_shipments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_om_order_shipments_tenant ON om_order_shipments;
CREATE POLICY pol_om_order_shipments_tenant ON om_order_shipments
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);

COMMENT ON TABLE om_order_shipments IS
    'Append-only shipment events; sum(quantity) by order_line gives shipped qty for reporting.';

COMMENT ON COLUMN om_order_shipments.delivery_type IS
    'e.g. SHIP, PICK, DELIVER - app-defined.';

COMMENT ON COLUMN om_order_shipments.production_date IS
    'Calendar date for production scheduling (may align with order delivery_date).';

COMMENT ON COLUMN om_order_shipments.production_window IS
    'Scheduled production slot or window label (text).';

COMMENT ON COLUMN om_order_shipments.snapshot_data IS
    'Optional JSON for legacy or app-specific shipment context.';
