-- ============================================================
-- OM_STANDING_ORDERS  –  Customer standing order lines
-- Target: Supabase (PostgreSQL 15+)
--
-- One row per (customer, production_dow, production_code, item).
-- This is the natural key from the legacy sordr table.
--
-- production_dow:  MON|TUE|WED|THU|FRI|SAT|SUN
-- production_code: MORNING|LUNCH|DINNER (tenant-defined shift)
--
-- quantity = 0 is valid and meaningful: a 0-qty line is a
-- standing reminder — it posts as an order line that the
-- user can override before the production cutoff.
--
-- prep_options: per-standing-order prep override (new in BPS).
-- Legacy sordr relied on item-level prep; left empty on migration.
--
-- Department customers (customer_type = DEPARTMENT) may have
-- standing orders but their posted order is merged into the
-- parent account's order — not yet implemented.
--
-- Triggers: fn_set_updated_at_ts_only, fn_audit_log
-- ============================================================

CREATE TABLE IF NOT EXISTS om_standing_orders (
    tenant_id           BIGINT          NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,
    standing_order_id   BIGINT          PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),

    customer_id         BIGINT          NOT NULL REFERENCES fnd_customers(customer_id) ON DELETE CASCADE,
    production_dow      TEXT            NOT NULL,   -- MON|TUE|WED|THU|FRI|SAT|SUN
    production_code     TEXT            NOT NULL,   -- tenant-defined shift name
    item_id             BIGINT          NOT NULL REFERENCES fnd_items(item_id) ON DELETE RESTRICT,

    -- 0 is valid: posted as a reminder line; user adjusts before cutoff
    quantity            NUMERIC(10,4)   NOT NULL DEFAULT 0 CHECK (quantity >= 0),
    prep_options        JSONB           NOT NULL DEFAULT '[]'::JSONB,

    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    effective_from      DATE,                       -- NULL = always active
    effective_to        DATE,                       -- NULL = no end date
    notes               TEXT,

    -- Audit
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT now(),
    created_by          BIGINT,
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_by          BIGINT,

    CONSTRAINT uq_om_standing_orders_line
        UNIQUE (tenant_id, customer_id, production_dow, production_code, item_id)
);

-- Ownership: application tables are owned by bps_owner; runtime access is via grants + RLS.
ALTER TABLE om_standing_orders OWNER TO bps_owner;

-- ── Indexes ──────────────────────────────────────────────────────────────────

-- Posting job: find all active lines for a given day + shift
CREATE INDEX IF NOT EXISTS idx_om_standing_orders_posting
    ON om_standing_orders (tenant_id, production_dow, production_code)
    WHERE is_active = TRUE;

-- Customer view / order-entry pre-population
CREATE INDEX IF NOT EXISTS idx_om_standing_orders_customer
    ON om_standing_orders (tenant_id, customer_id)
    WHERE is_active = TRUE;

-- ── Triggers ─────────────────────────────────────────────────────────────────

DROP TRIGGER IF EXISTS trg_om_standing_orders_set_updated ON om_standing_orders;
CREATE TRIGGER trg_om_standing_orders_set_updated
    BEFORE UPDATE ON om_standing_orders
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_om_standing_orders_audit ON om_standing_orders;
CREATE TRIGGER trg_om_standing_orders_audit
    AFTER INSERT OR UPDATE OR DELETE ON om_standing_orders
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('standing_order_id');

-- RLS policies: om_standing_orders_policies.sql
