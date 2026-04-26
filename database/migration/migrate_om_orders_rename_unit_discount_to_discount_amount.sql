-- Rename om_orders.unit_discount -> discount_amount (in-place; idempotent).
-- New installs: use newTables/om_orders.sql (column is discount_amount).

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'om_orders'
          AND column_name = 'unit_discount'
    )
    AND NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'om_orders'
          AND column_name = 'discount_amount'
    ) THEN
        ALTER TABLE om_orders RENAME COLUMN unit_discount TO discount_amount;
    END IF;
END $$;
