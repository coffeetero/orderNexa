-- ============================================================
-- om_shipments_route_stamp
-- Called by om_production_run_process: stamps each PLANNED own-fleet shipment of the run (delivery method is_own_fleet,
-- or none) with its route and stop number from Routes Maintenance, for the run's delivery date (its day of week) and
-- production code, date changes applied (om_route_plan). A ship-to with no stop of its own takes its nearest ancestor's
-- stop (a department rides with its account); a skip for that date leaves it without a route.
-- om_shipments.route gets the route name; a route text typed by hand (no route_id) is kept when no route is found.
-- Other shipments of the run have their stamped route cleared. Staff only (as Process run).
-- SECURITY DEFINER so Process run stamps routes even for staff who cannot open Routes Maintenance.
-- Returns the number of shipments that got a route.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_shipments_route_stamp(p_tenant_id bigint, p_production_run_id bigint)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_run bps.om_production_runs;
  n     integer;
BEGIN
  IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
    RAISE EXCEPTION 'Only tenant staff can process a run';
  END IF;
  SELECT * INTO v_run FROM om_production_runs WHERE tenant_id = p_tenant_id AND production_run_id = p_production_run_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Run % not found', p_production_run_id; END IF;

  WITH RECURSIVE plan AS MATERIALIZED (
    SELECT * FROM bps.om_route_plan(p_tenant_id, v_run.delivery_date, v_run.production_code)
  ), ships AS (
    SELECT s.shipment_id, s.ship_to_customer_id, (s.delivery_method_code IS NULL OR COALESCE(m.is_own_fleet, false)) AS own_fleet
      FROM om_shipments s
      LEFT JOIN om_delivery_methods m ON m.tenant_id = s.tenant_id AND m.delivery_method_code = s.delivery_method_code
     WHERE s.tenant_id = p_tenant_id AND s.production_run_id = p_production_run_id AND s.shipment_status = 'PLANNED'
  ), up AS (
    SELECT ships.shipment_id, ships.ship_to_customer_id AS customer_id, 0 AS depth FROM ships WHERE ships.own_fleet
    UNION ALL
    SELECT up.shipment_id, c.customer_parent_id, up.depth + 1
      FROM up JOIN fnd_customers c ON c.customer_id = up.customer_id
     WHERE c.customer_parent_id IS NOT NULL AND up.depth < 10
  ), hit AS (
    SELECT DISTINCT ON (up.shipment_id) up.shipment_id, p.route_id, p.stop_no
      FROM up JOIN plan p ON p.ship_to_customer_id = up.customer_id
     ORDER BY up.shipment_id, up.depth
  ), newv AS (
    SELECT ships.shipment_id, hit.route_id, hit.stop_no, r.route_name
      FROM ships LEFT JOIN hit ON hit.shipment_id = ships.shipment_id
      LEFT JOIN om_routes r ON r.route_id = hit.route_id
  )
  UPDATE om_shipments s
     SET route_id = newv.route_id, route_stop_no = newv.stop_no,
         route = CASE WHEN newv.route_id IS NOT NULL THEN newv.route_name WHEN s.route_id IS NOT NULL THEN NULL ELSE s.route END
    FROM newv
   WHERE s.shipment_id = newv.shipment_id
     AND (s.route_id, s.route_stop_no, s.route) IS DISTINCT FROM
         (newv.route_id, newv.stop_no, CASE WHEN newv.route_id IS NOT NULL THEN newv.route_name WHEN s.route_id IS NOT NULL THEN NULL ELSE s.route END);

  SELECT count(*) INTO n FROM om_shipments
   WHERE tenant_id = p_tenant_id AND production_run_id = p_production_run_id AND shipment_status = 'PLANNED' AND route_id IS NOT NULL;
  RETURN n;
END $function$;
REVOKE EXECUTE ON FUNCTION bps.om_shipments_route_stamp(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.om_shipments_route_stamp(bigint, bigint) TO authenticated, service_role, bps_dev;
