-- ============================================================
-- BPS_ITEMS  —  Bakery-specific item extensions
-- Target: Supabase (PostgreSQL 15+)
--
-- 1:1 extension of fnd_items.  item_id (BIGINT) is both the PK of this
-- table and a FK to fnd_items(item_id). tenant_id is BIGINT (fnd_tenants).
-- created_by / updated_by are BIGINT app user ids — not auth.uid() (use fn_set_updated_at_ts_only).
--
-- This table holds every attribute that is specific to the
-- bakery industry and would be meaningless for a generic
-- product catalogue.  Keeping it separate means:
--   • fnd_items stays clean and reusable across industries
--   • bps_* tables are clearly the business-specific layer
--   • Queries that don't need bakery detail skip this table entirely
-- ============================================================


-- ============================================================
-- 1. BPS_ITEMS
-- ============================================================

CREATE TABLE IF NOT EXISTS bps_items (

    -- 1:1 link to fnd_items — item_id is both PK and FK
    item_id             BIGINT      PRIMARY KEY
                                    REFERENCES fnd_items(item_id) ON DELETE CASCADE,

    -- --------------------------------------------------------
    -- Product characteristics
    -- --------------------------------------------------------
    dough_type          TEXT,           -- source: item.item_dough        (FRPETITE, PRTZL, BRIOSCHE …)
    shape               TEXT,           -- source: item.item_shape         (FICELLE, PETITE, OTHER …)
    packing             TEXT,           -- source: item.item_packing       (REGULAR, NONE …)

    -- --------------------------------------------------------
    -- Production / equipment settings
    -- --------------------------------------------------------
    machine_setting     TEXT,           -- source: item.item_machine_setting  (e.g. #12, #28)
    sheeter_setting     TEXT,           -- source: item.item_sheeter          (dough sheeter setting)

    -- Weight correction and scale calibration used on the bakery floor
    weight_adjuster     NUMERIC(10,4)   NOT NULL DEFAULT 0,  -- source: item.item_weight_adjuster
    scale_weight        NUMERIC(10,4)   NOT NULL DEFAULT 0,  -- source: item.item_scale_wt
    scale_qty           NUMERIC(10,4)   NOT NULL DEFAULT 0,  -- source: item.item_scale_qty

    -- --------------------------------------------------------
    -- Preparation capabilities
    -- What this item CAN be prepared as (drives UI options on order entry)
    -- --------------------------------------------------------
    is_sliceable        BOOLEAN         NOT NULL DEFAULT FALSE,  -- source: item.item_sliceable
    is_wrappable        BOOLEAN         NOT NULL DEFAULT FALSE,  -- source: item.item_wrappable
    is_coverable        BOOLEAN         NOT NULL DEFAULT FALSE,  -- source: item.item_coverable

    -- --------------------------------------------------------
    -- Preparation defaults
    -- How this item ships UNLESS the customer overrides on the order
    -- --------------------------------------------------------
    default_sliced      BOOLEAN         NOT NULL DEFAULT FALSE,  -- source: item.item_sliced
    default_wrapped     BOOLEAN         NOT NULL DEFAULT FALSE,  -- source: item.item_wrapped
    default_covered     BOOLEAN         NOT NULL DEFAULT FALSE,  -- source: item.item_covered

    -- --------------------------------------------------------
    -- Constraint: capability must be enabled before a default can be set
    -- --------------------------------------------------------
    CONSTRAINT chk_sliced_requires_sliceable
        CHECK (NOT default_sliced  OR is_sliceable),
    CONSTRAINT chk_wrapped_requires_wrappable
        CHECK (NOT default_wrapped OR is_wrappable),
    CONSTRAINT chk_covered_requires_coverable
        CHECK (NOT default_covered OR is_coverable),

    tenant_id           BIGINT        NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,

    -- Audit (BIGINT user ids — not Supabase auth.uid())
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT now(),
    created_by          BIGINT,
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_by          BIGINT
);

CREATE INDEX IF NOT EXISTS idx_bps_items_tenant
    ON bps_items (tenant_id);

CREATE INDEX IF NOT EXISTS idx_bps_items_dough_type
    ON bps_items (tenant_id, dough_type);

CREATE INDEX IF NOT EXISTS idx_bps_items_shape
    ON bps_items (tenant_id, shape);


-- ============================================================
-- 2. TRIGGERS  —  updated_at (ts_only) + audit log
-- ============================================================

DROP TRIGGER IF EXISTS trg_bps_items_set_updated ON bps_items;
CREATE TRIGGER trg_bps_items_set_updated
    BEFORE UPDATE ON bps_items
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_bps_items_audit ON bps_items;
CREATE TRIGGER trg_bps_items_audit
    AFTER INSERT OR UPDATE OR DELETE ON bps_items
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('item_id');


-- ============================================================
-- 3. ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE bps_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_bps_items_tenant ON bps_items;
CREATE POLICY pol_bps_items_tenant ON bps_items
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);


-- ============================================================
-- 4. Drop bakery-specific columns from fnd_items
--    (moved here permanently — this migration is idempotent)
-- ============================================================

ALTER TABLE fnd_items
    DROP COLUMN IF EXISTS dough_type,
    DROP COLUMN IF EXISTS shape,
    DROP COLUMN IF EXISTS packing,
    DROP COLUMN IF EXISTS machine_setting,
    DROP COLUMN IF EXISTS sheeter_setting,
    DROP COLUMN IF EXISTS weight_adjuster,
    DROP COLUMN IF EXISTS scale_weight,
    DROP COLUMN IF EXISTS scale_qty,
    DROP COLUMN IF EXISTS is_sliceable,
    DROP COLUMN IF EXISTS is_wrappable,
    DROP COLUMN IF EXISTS is_coverable,
    DROP COLUMN IF EXISTS default_sliced,
    DROP COLUMN IF EXISTS default_wrapped,
    DROP COLUMN IF EXISTS default_covered;
