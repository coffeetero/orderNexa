-- ============================================================
-- FND_ITEMS  –  Generic product catalogue
-- Target: Supabase (PostgreSQL 15+)
--
-- Replaces legacy `item` table.
-- Bakery-specific columns live in bps_items (see bps_items.sql).
-- Bill-of-materials lives in fnd_item_bom (see fnd_item_bom.sql).
--
-- item_id uses global fnd_entity_id_seq (run fnd_entity_id_seq.sql before this file).
-- created_by / updated_by are app user ids — not auth.uid() (use fn_set_updated_at_ts_only).
--
-- Run after: fnd_customers.sql (fn_set_updated_at_ts_only), fnd_tenants.sql
-- Run before: bps_items.sql, fnd_item_bom.sql
-- ============================================================


-- unit_of_sale is TEXT, not an ENUM.
-- The legacy data has 52+ variations of ~6 real units (Pcs/PCS/Pcs./pcs…).
-- An ENUM would block migration until every value is normalized.
-- Normalization happens in seed_fnd_items.sql; a CHECK constraint
-- or lookup table can be added once the data is clean.


CREATE TABLE IF NOT EXISTS fnd_items (
    item_id             BIGINT      PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),

    -- Identity
    legacy_id           INT,                        -- source: item.item_id
    item_number         TEXT,                       -- source: item.item_no  (SKU / product code)
    item_name           TEXT        NOT NULL,       -- source: item.item_desc
    item_description    TEXT,                       -- long-form notes / additional detail

    -- Classification
    category            TEXT,                       -- source: item.item_ctgry  (BREADS, ROLLS, etc.)
    unit_of_sale        TEXT        NOT NULL DEFAULT 'PCS',  -- source: item.item_unit

    -- Weight (unit travels with the value — tenant can use LB, OZ, KG, G)
    item_weight         NUMERIC(10,4),              -- source: item.item_weight  (per-piece weight)
    weight_uom          TEXT,                       -- e.g. 'LB', 'OZ', 'KG', 'G' — future FK to fnd_lookup_codes

    -- Box / packaging logistics
    -- legacy_box_id will become a FK to fnd_boxes once that table is created.
    legacy_box_id       INT,                        -- source: item.box_id
    box_qty_per_box     NUMERIC(10,2),              -- source: item.qty_per_box
    box_capacity_volume  NUMERIC(10,2),             -- source: item.item_bxsz_volume  (volume-based max per box)
    box_capacity_weight  NUMERIC(10,2),             -- source: item.item_bxsz_weight  (weight-based max per box)
    box_capacity_optimal NUMERIC(10,2),             -- source: item.item_bxsz_optimal (recommended per box)

    -- Ordering
    preorder_days       INT         NOT NULL DEFAULT 0 CHECK (preorder_days >= 0),  -- source: item.item_preorder_days

    -- Sales
    sales_terms_apply   BOOLEAN     NOT NULL DEFAULT TRUE,   -- source: item.item_sales_terms
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,   -- source: item.item_active

    tenant_id           BIGINT        NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,

    -- Audit (BIGINT user ids — not Supabase auth.uid())
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by          BIGINT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by          BIGINT,

    UNIQUE (tenant_id, item_number),
    UNIQUE (tenant_id, legacy_id)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_fnd_items_tenant_id
    ON fnd_items (tenant_id);

CREATE INDEX IF NOT EXISTS idx_fnd_items_category
    ON fnd_items (tenant_id, category);

CREATE INDEX IF NOT EXISTS idx_fnd_items_active
    ON fnd_items (tenant_id)
    WHERE is_active = TRUE;

-- ============================================================
-- TRIGGERS  —  updated_at (ts_only), audit log
-- ============================================================

DROP TRIGGER IF EXISTS trg_fnd_items_set_updated ON fnd_items;
CREATE TRIGGER trg_fnd_items_set_updated
    BEFORE UPDATE ON fnd_items
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_fnd_items_audit ON fnd_items;
CREATE TRIGGER trg_fnd_items_audit
    AFTER INSERT OR UPDATE OR DELETE ON fnd_items
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('item_id');


-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE fnd_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_items_tenant ON fnd_items;
CREATE POLICY pol_fnd_items_tenant ON fnd_items
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);
