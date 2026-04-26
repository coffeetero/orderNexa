-- ============================================================
-- AR_TRANSACTION_LINES  –  Line detail for an AR document
-- Target: Supabase (PostgreSQL 15+)
--
-- Run after: ar_transactions.sql, om_order_shipments.sql, fnd_items.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS ar_transaction_lines (
    ar_transaction_line_id  BIGINT      PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),

    tenant_id               BIGINT        NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,

    ar_transaction_id       BIGINT      NOT NULL REFERENCES ar_transactions(ar_transaction_id) ON DELETE CASCADE,

    line_number             INT         NOT NULL,

    source_type             TEXT        NOT NULL DEFAULT 'ITEM'
        CHECK (source_type IN ('ITEM', 'DELIVERY', 'FEE', 'ADJUSTMENT')),

    item_id                 BIGINT      REFERENCES fnd_items(item_id) ON DELETE SET NULL,

    item_description        TEXT,
    quantity                NUMERIC(14,4),
    unit_price              NUMERIC(14,4),
    amount                  NUMERIC(14,4) NOT NULL,

    order_shipment_id       BIGINT      REFERENCES om_order_shipments(order_shipment_id) ON DELETE SET NULL,

    snapshot_data           JSONB       NOT NULL DEFAULT '{}'::jsonb,

    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by              BIGINT,
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by              BIGINT,

    CONSTRAINT uq_ar_transaction_lines_number
        UNIQUE (tenant_id, ar_transaction_id, line_number)
);

CREATE INDEX IF NOT EXISTS idx_ar_transaction_lines_txn
    ON ar_transaction_lines (tenant_id, ar_transaction_id);

CREATE INDEX IF NOT EXISTS idx_ar_transaction_lines_order_shipment
    ON ar_transaction_lines (tenant_id, order_shipment_id)
    WHERE order_shipment_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_ar_transaction_lines_item
    ON ar_transaction_lines (tenant_id, item_id)
    WHERE item_id IS NOT NULL;


DROP TRIGGER IF EXISTS trg_ar_transaction_lines_set_updated ON ar_transaction_lines;
CREATE TRIGGER trg_ar_transaction_lines_set_updated
    BEFORE UPDATE ON ar_transaction_lines
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_ar_transaction_lines_audit ON ar_transaction_lines;
CREATE TRIGGER trg_ar_transaction_lines_audit
    AFTER INSERT OR UPDATE OR DELETE ON ar_transaction_lines
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('ar_transaction_line_id');


ALTER TABLE ar_transaction_lines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_ar_transaction_lines_tenant ON ar_transaction_lines;
CREATE POLICY pol_ar_transaction_lines_tenant ON ar_transaction_lines
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);

COMMENT ON TABLE ar_transaction_lines IS
    'Commercial / tax lines; optional at go-live if header-only AR is enough.';

COMMENT ON COLUMN ar_transaction_lines.source_type IS
    'Line classification: ITEM, DELIVERY, FEE, ADJUSTMENT.';

COMMENT ON COLUMN ar_transaction_lines.item_description IS
    'Display text for the line (e.g. product or charge label).';
