-- ============================================================
-- add_order_entry_fields.sql
-- Idempotent migration for Order Entry screen requirements.
--
-- Changes:
--   1. om_orders       → add delivery_amount column
--   2. om_order_lines  → add per-line prep flags: is_sliced, is_wrapped,
--                         is_covered, is_scored
--   3. bps_items       → add scored capability/default columns (is_scoreable,
--                         default_scored) with matching CHECK constraint
-- ============================================================


-- ============================================================
-- 1. om_orders: delivery_amount
-- ============================================================

ALTER TABLE om_orders
    ADD COLUMN IF NOT EXISTS delivery_amount NUMERIC(14,4) NOT NULL DEFAULT 0;

COMMENT ON COLUMN om_orders.delivery_amount IS
    'Delivery / freight charge applied to the order (legacy: Dlvry $).';


-- ============================================================
-- 2. om_order_lines: preparation flags (per order line)
--    These capture the customer's requested prep for each line,
--    defaulting from bps_items at line creation time.
-- ============================================================

ALTER TABLE om_order_lines
    ADD COLUMN IF NOT EXISTS is_sliced  BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS is_wrapped BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS is_covered BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS is_scored  BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN om_order_lines.is_sliced  IS 'Customer requested sliced preparation for this line.';
COMMENT ON COLUMN om_order_lines.is_wrapped IS 'Customer requested wrapped preparation for this line.';
COMMENT ON COLUMN om_order_lines.is_covered IS 'Customer requested covered/coated preparation for this line.';
COMMENT ON COLUMN om_order_lines.is_scored  IS 'Customer requested scored preparation for this line.';


-- ============================================================
-- 3. bps_items: scored capability/default columns
--    Follows the same pattern as sliceable/wrappable/coverable.
-- ============================================================

ALTER TABLE bps_items
    ADD COLUMN IF NOT EXISTS is_scoreable   BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS default_scored BOOLEAN NOT NULL DEFAULT FALSE;

-- Add CHECK constraint only if it doesn't already exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM   information_schema.table_constraints
        WHERE  table_name   = 'bps_items'
          AND  constraint_name = 'chk_scored_requires_scoreable'
    ) THEN
        ALTER TABLE bps_items
            ADD CONSTRAINT chk_scored_requires_scoreable
                CHECK (NOT default_scored OR is_scoreable);
    END IF;
END $$;

COMMENT ON COLUMN bps_items.is_scoreable   IS 'Item can be scored (cross-cut). Enables the CS checkbox on order entry.';
COMMENT ON COLUMN bps_items.default_scored IS 'Item ships scored by default unless overridden on the order line.';
