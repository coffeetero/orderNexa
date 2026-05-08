-- ============================================================
-- Rename om_orders event/location context to Department/Event.
--
-- The deployed schema previously used event_location; some older local
-- experiments used location_event. Keep the migration defensive so it can
-- run safely against either intermediate state.
-- ============================================================

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = current_schema()
          AND table_name = 'om_orders'
          AND column_name = 'event_location'
    ) AND NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = current_schema()
          AND table_name = 'om_orders'
          AND column_name = 'department_event'
    ) THEN
        ALTER TABLE om_orders RENAME COLUMN event_location TO department_event;
    ELSIF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = current_schema()
          AND table_name = 'om_orders'
          AND column_name = 'location_event'
    ) AND NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = current_schema()
          AND table_name = 'om_orders'
          AND column_name = 'department_event'
    ) THEN
        ALTER TABLE om_orders RENAME COLUMN location_event TO department_event;
    END IF;
END $$;
