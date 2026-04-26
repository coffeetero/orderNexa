-- ============================================================
-- RECREATE fnd_items (drop + create from current definition)
--
-- Empties and truncates dependent rows, drops fnd_items, recreates
-- it from newTables/fnd_items.sql, then restores FKs to bps_items
-- and fnd_item_bom.
--
-- Destructive: all rows in fnd_items, bps_items, and fnd_item_bom
-- are removed.
-- ============================================================

DO $$
BEGIN
    IF to_regclass('public.fnd_item_bom') IS NOT NULL THEN
        EXECUTE 'TRUNCATE TABLE fnd_item_bom CASCADE';
    END IF;
    IF to_regclass('public.bps_items') IS NOT NULL THEN
        EXECUTE 'TRUNCATE TABLE bps_items CASCADE';
    END IF;
    IF to_regclass('public.fnd_items') IS NOT NULL THEN
        EXECUTE 'TRUNCATE TABLE fnd_items CASCADE';
    END IF;
END $$;

DROP TABLE IF EXISTS fnd_items CASCADE;

CREATE SEQUENCE IF NOT EXISTS fnd_entity_id_seq
    AS BIGINT
    START WITH 200000000001
    INCREMENT BY 1
    MINVALUE 1
    NO MAXVALUE
    CACHE 1;

CREATE TABLE fnd_items (
    item_id             BIGINT      PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),

    legacy_id           INT,
    item_number         TEXT,
    item_name           TEXT        NOT NULL,
    item_description    TEXT,

    category            TEXT,
    unit_of_sale        TEXT        NOT NULL DEFAULT 'PCS',

    item_weight         NUMERIC(10,4),
    weight_uom          TEXT,

    legacy_box_id       INT,
    box_qty_per_box     NUMERIC(10,2),
    box_capacity_volume  NUMERIC(10,2),
    box_capacity_weight  NUMERIC(10,2),
    box_capacity_optimal NUMERIC(10,2),

    preorder_days       INT         NOT NULL DEFAULT 0 CHECK (preorder_days >= 0),

    sales_terms_apply   BOOLEAN     NOT NULL DEFAULT TRUE,
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    tenant_id           BIGINT        NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by          BIGINT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by          BIGINT,

    UNIQUE (tenant_id, item_number),
    UNIQUE (tenant_id, legacy_id)
);

CREATE INDEX IF NOT EXISTS idx_fnd_items_tenant_id
    ON fnd_items (tenant_id);

CREATE INDEX IF NOT EXISTS idx_fnd_items_category
    ON fnd_items (tenant_id, category);

CREATE INDEX IF NOT EXISTS idx_fnd_items_active
    ON fnd_items (tenant_id)
    WHERE is_active = TRUE;

DROP TRIGGER IF EXISTS trg_fnd_items_set_updated ON fnd_items;
CREATE TRIGGER trg_fnd_items_set_updated
    BEFORE UPDATE ON fnd_items
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_fnd_items_audit ON fnd_items;
CREATE TRIGGER trg_fnd_items_audit
    AFTER INSERT OR UPDATE OR DELETE ON fnd_items
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('item_id');

ALTER TABLE fnd_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_items_tenant ON fnd_items;
CREATE POLICY pol_fnd_items_tenant ON fnd_items
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);


-- Restore FKs (removed when fnd_items was dropped)
DO $$
DECLARE
    v_bps   oid;
    v_bom   oid;
BEGIN
    v_bps := to_regclass('public.bps_items');
    v_bom := to_regclass('public.fnd_item_bom');

    IF v_bps IS NOT NULL
       AND NOT EXISTS (
           SELECT 1 FROM pg_constraint
           WHERE conname = 'bps_items_item_id_fkey'
             AND conrelid = v_bps
       ) THEN
        ALTER TABLE bps_items
            ADD CONSTRAINT bps_items_item_id_fkey
            FOREIGN KEY (item_id) REFERENCES fnd_items(item_id) ON DELETE CASCADE;
    END IF;

    IF v_bom IS NOT NULL
       AND NOT EXISTS (
           SELECT 1 FROM pg_constraint
           WHERE conname = 'fnd_item_bom_parent_item_id_fkey'
             AND conrelid = v_bom
       ) THEN
        ALTER TABLE fnd_item_bom
            ADD CONSTRAINT fnd_item_bom_parent_item_id_fkey
            FOREIGN KEY (parent_item_id) REFERENCES fnd_items(item_id);
    END IF;

    IF v_bom IS NOT NULL
       AND NOT EXISTS (
           SELECT 1 FROM pg_constraint
           WHERE conname = 'fnd_item_bom_item_id_fkey'
             AND conrelid = v_bom
       ) THEN
        ALTER TABLE fnd_item_bom
            ADD CONSTRAINT fnd_item_bom_item_id_fkey
            FOREIGN KEY (item_id) REFERENCES fnd_items(item_id);
    END IF;
END $$;
