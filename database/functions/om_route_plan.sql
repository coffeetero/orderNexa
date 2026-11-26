-- ============================================================
-- om_route_plan
-- Internal: the routes as they run on one delivery date + production code. Weekly stops of active routes for the
-- date's day of week, with that date's changes (om_route_stop_exceptions) applied:
--   skip  (route_id NULL) : the ship-to is left off; returned as a marker row with route_id NULL so a department does
--                           not fall back to its account's stop;
--   route (route_id, stop_no): the ship-to is on that route at that stop for the date (leaves its usual route that day),
--                           keeping its usual window and driver notes for the day when it has them.
-- Stop numbers are renumbered 1..n per route; a changed stop takes the number it asks for, ahead of the usual one.
-- Used by om_shipments_route_stamp (Process run) and om_route_sheet_get (route sheet for a date).
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_route_plan(p_tenant_id bigint, p_date date, p_code text)
RETURNS TABLE (ship_to_customer_id bigint, route_id bigint, stop_no integer, is_exception boolean,
               window_from time, window_to time, driver_notes text)
LANGUAGE sql
STABLE
SET search_path TO 'bps', 'public'
AS $function$
  WITH ex AS (
    SELECT e.* FROM om_route_stop_exceptions e
     WHERE e.tenant_id = p_tenant_id AND e.exception_date = p_date AND e.production_code = upper(btrim(p_code))
  ), usual AS (
    SELECT s.* FROM om_route_stops s
     WHERE s.tenant_id = p_tenant_id AND s.day_of_week = bps.om_route_dow(p_date) AND s.production_code = upper(btrim(p_code))
  ), stops AS (
    SELECT u.ship_to_customer_id, u.route_id, u.stop_no, false AS is_exception, u.window_from, u.window_to, u.driver_notes
      FROM usual u JOIN om_routes r ON r.route_id = u.route_id AND r.is_active
     WHERE NOT EXISTS (SELECT 1 FROM ex WHERE ex.ship_to_customer_id = u.ship_to_customer_id)
    UNION ALL
    SELECT ex.ship_to_customer_id, ex.route_id, ex.stop_no, true, u.window_from, u.window_to,
           COALESCE(NULLIF(btrim(ex.notes), ''), u.driver_notes)
      FROM ex JOIN om_routes r ON r.route_id = ex.route_id AND r.is_active
      LEFT JOIN usual u ON u.ship_to_customer_id = ex.ship_to_customer_id
  )
  SELECT s.ship_to_customer_id, s.route_id,
         (row_number() OVER (PARTITION BY s.route_id ORDER BY s.stop_no, s.is_exception DESC, s.ship_to_customer_id))::int,
         s.is_exception, s.window_from, s.window_to, s.driver_notes
    FROM stops s
  UNION ALL
  SELECT ex.ship_to_customer_id, NULL::bigint, NULL::int, true, NULL::time, NULL::time, ex.notes
    FROM ex WHERE ex.route_id IS NULL;
$function$;
REVOKE EXECUTE ON FUNCTION bps.om_route_plan(bigint, date, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION bps.om_route_plan(bigint, date, text) TO service_role, bps_dev;
