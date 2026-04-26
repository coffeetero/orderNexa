-- ============================================================
-- FND_PRICEBOOK_ITEMS  –  Item prices within a price book
-- Target: Supabase (PostgreSQL 15+)
--
-- Run after: fnd_entity_id_seq.sql, fnd_tenants.sql, fnd_pricebooks.sql, fnd_items.sql
--   (requires fn_set_updated_at_ts_only, fn_audit_log from fnd_customers.sql chain)
--
-- Amounts are in the currency of the price book (fnd_pricebooks.currency_id → fnd_currencies).
-- uom_id links to a units-of-measure
-- master (add REFERENCES fnd_uoms(uom_id) when that table exists); nullable = inherit from item.
-- ============================================================


CREATE TABLE IF NOT EXISTS fnd_pricebook_items (
    pricebook_item_id     BIGINT      PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),

    pricebook_id          BIGINT      NOT NULL REFERENCES fnd_pricebooks(pricebook_id) ON DELETE CASCADE,

    item_id               BIGINT      NOT NULL REFERENCES fnd_items(item_id) ON DELETE RESTRICT,

    item_price            NUMERIC(14,4) NOT NULL,

    -- Unit of measure for this price row; FK to fnd_uoms when defined.
    uom_id                BIGINT,

    min_quantity          NUMERIC(14,4) NOT NULL DEFAULT 1 CHECK (min_quantity > 0),

    is_active             BOOLEAN     NOT NULL DEFAULT TRUE,

    tenant_id             BIGINT        NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,

    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by            BIGINT,
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by            BIGINT,

    CONSTRAINT uq_fnd_pricebook_items_book_item_tier
        UNIQUE (tenant_id, pricebook_id, item_id, min_quantity)
);

CREATE INDEX IF NOT EXISTS idx_fnd_pricebook_items_tenant_book
    ON fnd_pricebook_items (tenant_id, pricebook_id);

CREATE INDEX IF NOT EXISTS idx_fnd_pricebook_items_tenant_item
    ON fnd_pricebook_items (tenant_id, item_id);

CREATE INDEX IF NOT EXISTS idx_fnd_pricebook_items_book_active
    ON fnd_pricebook_items (tenant_id, pricebook_id)
    WHERE is_active = TRUE;


-- TRIGGERS
-- ============================================================

DROP TRIGGER IF EXISTS trg_fnd_pricebook_items_set_updated ON fnd_pricebook_items;
CREATE TRIGGER trg_fnd_pricebook_items_set_updated
    BEFORE UPDATE ON fnd_pricebook_items
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_fnd_pricebook_items_audit ON fnd_pricebook_items;
CREATE TRIGGER trg_fnd_pricebook_items_audit
    AFTER INSERT OR UPDATE OR DELETE ON fnd_pricebook_items
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('pricebook_item_id');


-- ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE fnd_pricebook_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_pricebook_items_tenant ON fnd_pricebook_items;
CREATE POLICY pol_fnd_pricebook_items_tenant ON fnd_pricebook_items
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);

COMMENT ON TABLE fnd_pricebook_items IS
    'Per-item prices for a price book; item_price is in the book''s currency.';

COMMENT ON COLUMN fnd_pricebook_items.item_price IS
    'Unit price for this row (book currency).';

COMMENT ON COLUMN fnd_pricebook_items.uom_id IS
    'Unit of measure for pricing; NULL = use item default / app rules until FK to fnd_uoms exists.';
