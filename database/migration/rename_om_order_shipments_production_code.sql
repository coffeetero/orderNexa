-- ============================================================
-- Rename om_order_shipments.production_window → production_code.
-- Run once on databases that still have production_window.
-- Idempotent.
-- ============================================================

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM   information_schema.columns
        WHERE  table_schema = 'public'
          AND  table_name   = 'om_order_shipments'
          AND  column_name  = 'production_window'
    ) THEN
        ALTER TABLE public.om_order_shipments
            RENAME COLUMN production_window TO production_code;
    END IF;
END $$;
