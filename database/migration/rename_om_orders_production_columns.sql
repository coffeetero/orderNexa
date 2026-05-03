-- ============================================================
-- Rename om_orders delivery_* columns to production_*.
-- Run once against databases created before this rename.
-- Idempotent: skips if old column names are already gone.
-- ============================================================

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM   information_schema.columns
        WHERE  table_schema = 'public'
          AND  table_name   = 'om_orders'
          AND  column_name  = 'delivery_date'
    ) THEN
        ALTER TABLE public.om_orders RENAME COLUMN delivery_date TO production_date;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM   information_schema.columns
        WHERE  table_schema = 'public'
          AND  table_name   = 'om_orders'
          AND  column_name  = 'delivery_window'
    ) THEN
        ALTER TABLE public.om_orders RENAME COLUMN delivery_window TO production_code;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relname = 'idx_om_orders_delivery_date'
    ) THEN
        ALTER INDEX public.idx_om_orders_delivery_date RENAME TO idx_om_orders_production_date;
    END IF;
END $$;
