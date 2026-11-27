-- ============================================================
-- om_route_delete
-- Deletes a route with all its stops and date changes. Shipments already stamped with it keep the route name in
-- om_shipments.route (route_id becomes NULL). Needs delivery.routes delete access.
-- Returns { route_id, stops_removed }.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_route_delete(p_tenant_id bigint, p_route_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_me bigint := bps.om_route_check(p_tenant_id, 'D');
  v    bps.om_routes := bps.om_route_row_check(p_tenant_id, p_route_id);
  n    integer;
BEGIN
  SELECT count(*) INTO n FROM om_route_stops WHERE route_id = v.route_id;
  DELETE FROM om_routes WHERE route_id = v.route_id;
  RETURN jsonb_build_object('route_id', v.route_id, 'stops_removed', n);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.om_route_delete(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.om_route_delete(bigint, bigint) TO authenticated, service_role, bps_dev;
