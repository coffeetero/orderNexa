-- ============================================================
-- Fix the Department/Event of migrated orders (2026-11-24), in place.
-- Departments named "ORDER" are placeholders in the old BPS; the real department/event is on the order itself
-- (ordr.cus_name, e.g. Featherstone's "R01 A1006502 0003"). New rule (same as seed_om_orders.sql):
--   order of a department named ORDER → the order's own name, upper-cased and trimmed (blank → ORDER)
--   order of any other department/site → the department's name, as before (renamed departments keep today's name)
--   two orders of one customer, date and code with the same event → event + ' ' + department number (e.g. "R05 02832 15713")
--   still the same (or taken by an order entered or imported in BPS) → event + ' #' + order number
-- Only migrated orders (order_source IS NULL) change. Not a reload: seed_om_orders.sql truncates om_orders, and the
-- cascade empties ar_transaction_lines, om_shipment_lines and om_order_import_rows.
-- Run: docker exec -i supabase_db_bps-local psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 < database/migration/fix_om_orders_department_event.sql
-- ============================================================
BEGIN;
SET search_path = bps, public;

CREATE TEMP TABLE _ev ON COMMIT DROP AS
WITH src AS (
    SELECT o.order_id, o.tenant_id, o.customer_id, o.production_date, o.production_code, o.order_number, o.department_event AS old_event,
           cus.customer_number AS dept_number,
           CASE WHEN upper(btrim(cus.customer_type)) NOT IN ('DEPARTMENT', 'LOCATION') THEN ''
                WHEN upper(btrim(cus.customer_name)) = 'ORDER' THEN COALESCE(NULLIF(upper(btrim(lo.cus_name)), ''), 'ORDER')
                ELSE COALESCE(NULLIF(upper(btrim(cus.customer_name)), ''), '') END AS base
      FROM om_orders o
      JOIN ordr lo ON btrim(lo.ordr_no::bigint::text) = o.order_number
      JOIN fnd_customers cus ON cus.tenant_id = o.tenant_id AND cus.legacy_id = lo.cus_id::int
     WHERE o.order_source IS NULL
), step1 AS (
    SELECT s.*, CASE WHEN count(*) OVER (PARTITION BY tenant_id, customer_id, production_date, production_code, base) > 1 AND base <> ''
                     THEN base || ' ' || dept_number ELSE base END AS ev1
      FROM src s
), step2 AS (
    SELECT s.*, CASE WHEN count(*) OVER (PARTITION BY tenant_id, customer_id, production_date, production_code, ev1) > 1
                       OR EXISTS (SELECT 1 FROM om_orders x WHERE x.order_source IS NOT NULL AND x.tenant_id = s.tenant_id AND x.customer_id = s.customer_id
                                    AND x.production_date = s.production_date AND x.production_code IS NOT DISTINCT FROM s.production_code
                                    AND x.department_event = s.ev1)
                     THEN s.ev1 || ' #' || s.order_number ELSE s.ev1 END AS new_event
      FROM step1 s
)
SELECT order_id, old_event, new_event FROM step2 WHERE new_event IS DISTINCT FROM old_event;

-- two steps so no row briefly takes an event another row still holds
UPDATE om_orders o SET department_event = 'TMP#' || o.order_id FROM _ev e WHERE e.order_id = o.order_id;
UPDATE om_orders o SET department_event = e.new_event FROM _ev e WHERE e.order_id = o.order_id;

SELECT count(*) AS orders_changed FROM _ev;
COMMIT;
