-- ============================================================
-- DROP LEGACY OM_ORDER_LINES PREP BOOLEAN COLUMNS
--
-- Prep choices now live in om_order_lines.prep_options JSONB.
-- Apply after om_orders_get / om_orders_save no longer reference the
-- legacy is_sliced, is_wrapped, and is_covered columns.
-- ============================================================

ALTER TABLE om_order_lines
    DROP COLUMN IF EXISTS is_sliced,
    DROP COLUMN IF EXISTS is_wrapped,
    DROP COLUMN IF EXISTS is_covered;
