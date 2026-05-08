-- ============================================================
-- Dedupe existing legacy om_orders slot keys.
--
-- Existing live data was already normalized to parent customers and uppercase
-- Department/Event values. Numeric legacy order numbers are suffixed to
-- Department/Event only where that slot key is duplicated, then the unique
-- slot index is created.
--
-- New app order numbers are not numeric legacy values and are not changed.
-- ============================================================

SET search_path = bps, public;

WITH duplicate_slots AS (
    SELECT
        tenant_id,
        customer_id,
        production_date,
        production_code,
        department_event
    FROM om_orders
    GROUP BY
        tenant_id,
        customer_id,
        production_date,
        production_code,
        department_event
    HAVING COUNT(*) > 1
)
UPDATE om_orders o
   SET department_event = o.department_event || '-' || o.order_number
  FROM duplicate_slots dup
 WHERE o.tenant_id = dup.tenant_id
   AND o.customer_id IS NOT DISTINCT FROM dup.customer_id
   AND o.production_date = dup.production_date
   AND o.production_code IS NOT DISTINCT FROM dup.production_code
   AND o.department_event = dup.department_event
   AND o.order_number ~ '^[0-9]+$'
   AND o.department_event !~ ('-' || o.order_number || '$');

CREATE UNIQUE INDEX IF NOT EXISTS uq_om_orders_slot_department_event
    ON om_orders (tenant_id, customer_id, production_date, production_code, department_event)
    NULLS NOT DISTINCT;
