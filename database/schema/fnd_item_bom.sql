-- ============================================================
-- FND_ITEM_BOM  –  Bill of materials / recipe
-- Target: Supabase (PostgreSQL 15+)
--
-- Replaces legacy `citem` table.
-- Prerequisite: fnd_entity_id_seq.sql, fnd_customers.sql (fn_set_updated_at_ts_only), fnd_items.sql, fnd_tenants.sql
--
-- item_bom_id and audit user columns are BIGINT; tenant_id is BIGINT (FK fnd_tenants).
-- created_by / updated_by are app user ids — not auth.uid() (use fn_set_updated_at_ts_only).
--
-- A parent item that has rows here is a BOM parent.
-- Each row defines one component item and the required quantity.
-- ============================================================

CREATE TABLE IF NOT EXISTS fnd_item_bom (
    item_bom_id     BIGINT      PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),
    parent_item_id  BIGINT      NOT NULL REFERENCES fnd_items(item_id),   -- source: citem.citem_id (parent SKU)
    item_id         BIGINT      NOT NULL REFERENCES fnd_items(item_id),   -- source: citem.item_id (component SKU)
    quantity        NUMERIC(10,4) NOT NULL DEFAULT 1 CHECK (quantity > 0), -- source: citem.citem_qty
    tenant_id       BIGINT        NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,
    -- Audit (BIGINT user ids — not Supabase auth.uid())
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by      BIGINT,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by      BIGINT,

    -- A component item can only appear once per parent item
    UNIQUE (parent_item_id, item_id),

    -- A parent item cannot be its own component
    CONSTRAINT chk_no_self_reference CHECK (parent_item_id != item_id)
);

CREATE INDEX IF NOT EXISTS idx_fnd_item_bom_tenant
    ON fnd_item_bom (tenant_id);

CREATE INDEX IF NOT EXISTS idx_fnd_item_bom_parent
    ON fnd_item_bom (parent_item_id);

CREATE INDEX IF NOT EXISTS idx_fnd_item_bom_item
    ON fnd_item_bom (item_id);


-- ============================================================
-- TRIGGERS  —  updated_at (ts_only) + audit log
-- ============================================================

DROP TRIGGER IF EXISTS trg_fnd_item_bom_set_updated ON fnd_item_bom;
CREATE TRIGGER trg_fnd_item_bom_set_updated
    BEFORE UPDATE ON fnd_item_bom
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_fnd_item_bom_audit ON fnd_item_bom;
CREATE TRIGGER trg_fnd_item_bom_audit
    AFTER INSERT OR UPDATE OR DELETE ON fnd_item_bom
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('item_bom_id');


-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE fnd_item_bom ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_item_bom_tenant ON fnd_item_bom;
CREATE POLICY pol_fnd_item_bom_tenant ON fnd_item_bom
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);
