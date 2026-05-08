-- ============================================================
-- Normalize om_orders slot fields for existing-order lookup.
--
-- - production_code is stored as UPPER(TRIM(value)).
-- - department_event is stored uppercase and non-null.
-- - orders saved against LOCATION customers are moved to the
--   immediate parent customer, with the LOCATION name preserved in
--   department_event when department_event is blank.
-- - Adds lookup indexes for existing-orders retrieval.
--
-- The proposed unique slot constraint:
--   (tenant_id, customer_id, production_date, production_code, department_event)
-- is intentionally not added here. Current legacy data contains duplicate
-- slot keys and needs a separate dedupe/legacy-retention decision first.
-- ============================================================

SET search_path = bps, public;

UPDATE om_orders o
   SET customer_id = parent.customer_id,
       customer_name = parent.customer_name,
       department_event = COALESCE(NULLIF(UPPER(TRIM(o.department_event)), ''), UPPER(TRIM(location.customer_name)), '')
  FROM fnd_customers location
  JOIN fnd_customers parent
    ON parent.tenant_id = location.tenant_id
   AND parent.customer_id = location.customer_parent_id
 WHERE location.tenant_id = o.tenant_id
   AND location.customer_id = o.customer_id
   AND UPPER(TRIM(location.customer_type)) = 'LOCATION'
   AND location.customer_parent_id IS NOT NULL;

UPDATE om_orders
   SET production_code = NULLIF(UPPER(TRIM(production_code)), ''),
       department_event = COALESCE(NULLIF(UPPER(TRIM(department_event)), ''), '')
 WHERE production_code IS DISTINCT FROM NULLIF(UPPER(TRIM(production_code)), '')
    OR department_event IS DISTINCT FROM COALESCE(NULLIF(UPPER(TRIM(department_event)), ''), '');

ALTER TABLE om_orders
    ALTER COLUMN department_event SET DEFAULT '',
    ALTER COLUMN department_event SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_om_orders_existing_customer_slot
    ON om_orders (tenant_id, customer_id, production_date, production_code);

CREATE INDEX IF NOT EXISTS idx_om_orders_existing_slot
    ON om_orders (tenant_id, production_date, production_code);
