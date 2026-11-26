-- ============================================================
-- om_route_stop_move
-- Moves a stop to stop number p_stop_no on its route (clamped to 1..n); the others shift and the route is renumbered.
-- Returns { route_stop_id, stop_no }.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_route_stop_move(p_tenant_id bigint, p_route_stop_id bigint, p_stop_no integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_me  bigint := bps.om_route_check(p_tenant_id, 'W');
  v     bps.om_route_stops;
  v_pos integer;
BEGIN
  SELECT * INTO v FROM om_route_stops WHERE tenant_id = p_tenant_id AND route_stop_id = p_route_stop_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Stop not found'; END IF;
  PERFORM 1 FROM om_routes WHERE route_id = v.route_id FOR UPDATE;
  WITH sib AS (
    SELECT route_stop_id, row_number() OVER (ORDER BY stop_no, route_stop_id)::int AS rn
      FROM om_route_stops
     WHERE route_id = v.route_id AND day_of_week = v.day_of_week AND production_code = v.production_code AND route_stop_id <> v.route_stop_id
  ), k AS (SELECT LEAST(GREATEST(COALESCE(p_stop_no, 1), 1), (SELECT count(*) FROM sib) + 1)::int AS pos)
  UPDATE om_route_stops s SET stop_no = CASE WHEN sib.rn < k.pos THEN sib.rn ELSE sib.rn + 1 END, updated_by = v_me
    FROM sib, k
   WHERE s.route_stop_id = sib.route_stop_id AND s.stop_no <> CASE WHEN sib.rn < k.pos THEN sib.rn ELSE sib.rn + 1 END;
  SELECT LEAST(GREATEST(COALESCE(p_stop_no, 1), 1), count(*))::int INTO v_pos
    FROM om_route_stops WHERE route_id = v.route_id AND day_of_week = v.day_of_week AND production_code = v.production_code;
  UPDATE om_route_stops SET stop_no = v_pos, updated_by = v_me WHERE route_stop_id = v.route_stop_id AND stop_no <> v_pos;
  RETURN jsonb_build_object('route_stop_id', v.route_stop_id, 'stop_no', v_pos);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.om_route_stop_move(bigint, bigint, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.om_route_stop_move(bigint, bigint, integer) TO authenticated, service_role, bps_dev;
