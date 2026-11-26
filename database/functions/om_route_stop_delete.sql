-- ============================================================
-- om_route_stop_delete
-- Takes a stop off its route; the route is renumbered. Returns { route_stop_id, stops } (stops left).
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_route_stop_delete(p_tenant_id bigint, p_route_stop_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_me bigint := bps.om_route_check(p_tenant_id, 'W');
  v    bps.om_route_stops;
BEGIN
  SELECT * INTO v FROM om_route_stops WHERE tenant_id = p_tenant_id AND route_stop_id = p_route_stop_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Stop not found'; END IF;
  PERFORM 1 FROM om_routes WHERE route_id = v.route_id FOR UPDATE;
  DELETE FROM om_route_stops WHERE route_stop_id = v.route_stop_id;
  RETURN jsonb_build_object('route_stop_id', v.route_stop_id,
                            'stops', bps.om_route_stops_renumber(p_tenant_id, v.route_id, v.day_of_week, v.production_code));
END $function$;
REVOKE EXECUTE ON FUNCTION bps.om_route_stop_delete(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.om_route_stop_delete(bigint, bigint) TO authenticated, service_role, bps_dev;
