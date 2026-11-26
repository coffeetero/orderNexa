-- ============================================================
-- om_route_stop_add
-- Adds a ship-to location (an account or department) to a route for a day of week + production code at stop p_stop_no
-- (NULL = at the end); later stops move down and the route is renumbered. A ship-to can be on one route per day + code:
-- when it is on another route, p_move = true takes it off that one (which is renumbered), otherwise it is refused.
-- Returns { route_stop_id, stop_no, stops, moved_from: { route_id, route_code, stop_no } | null }.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_route_stop_add(p_tenant_id bigint, p_route_id bigint, p_dow text, p_code text, p_customer_id bigint,
                                                 p_stop_no integer DEFAULT NULL, p_move boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_me    bigint := bps.om_route_check(p_tenant_id, 'W');
  v_code  text   := bps.om_route_slot_check(p_tenant_id, p_dow, p_code);
  v_dow   text   := upper(btrim(p_dow));
  v       bps.om_routes := bps.om_route_row_check(p_tenant_id, p_route_id);
  c       bps.fnd_customers := bps.om_route_ship_to_check(p_tenant_id, p_customer_id);
  v_old   record;
  v_moved jsonb;
  v_count integer;
  v_pos   integer;
  v_id    bigint;
BEGIN
  IF NOT c.is_active THEN RAISE EXCEPTION '% is inactive', c.customer_name; END IF;
  -- lock the routes involved (in id order) so two people editing the same day do not collide
  PERFORM 1 FROM om_routes WHERE route_id IN (
    SELECT v.route_id UNION SELECT s.route_id FROM om_route_stops s
     WHERE s.tenant_id = p_tenant_id AND s.day_of_week = v_dow AND s.production_code = v_code AND s.ship_to_customer_id = c.customer_id)
   ORDER BY route_id FOR UPDATE;

  SELECT s.route_stop_id, s.route_id, s.stop_no, r.route_code INTO v_old
    FROM om_route_stops s JOIN om_routes r ON r.route_id = s.route_id
   WHERE s.tenant_id = p_tenant_id AND s.day_of_week = v_dow AND s.production_code = v_code AND s.ship_to_customer_id = c.customer_id;
  IF FOUND THEN
    IF v_old.route_id = v.route_id THEN
      RAISE EXCEPTION '% is already stop % on this route', c.customer_name, v_old.stop_no;
    END IF;
    IF NOT COALESCE(p_move, false) THEN
      RAISE EXCEPTION '% is already on route % (stop %) for % %', c.customer_name, v_old.route_code, v_old.stop_no, v_dow, v_code;
    END IF;
    DELETE FROM om_route_stops WHERE route_stop_id = v_old.route_stop_id;
    PERFORM bps.om_route_stops_renumber(p_tenant_id, v_old.route_id, v_dow, v_code);
    v_moved := jsonb_build_object('route_id', v_old.route_id, 'route_code', v_old.route_code, 'stop_no', v_old.stop_no);
  END IF;

  SELECT count(*) INTO v_count FROM om_route_stops
   WHERE tenant_id = p_tenant_id AND route_id = v.route_id AND day_of_week = v_dow AND production_code = v_code;
  v_pos := LEAST(GREATEST(COALESCE(p_stop_no, v_count + 1), 1), v_count + 1);
  UPDATE om_route_stops SET stop_no = stop_no + 1, updated_by = v_me
   WHERE tenant_id = p_tenant_id AND route_id = v.route_id AND day_of_week = v_dow AND production_code = v_code AND stop_no >= v_pos;
  INSERT INTO om_route_stops (tenant_id, route_id, day_of_week, production_code, ship_to_customer_id, stop_no, created_by, updated_by)
  VALUES (p_tenant_id, v.route_id, v_dow, v_code, c.customer_id, v_pos, v_me, v_me)
  RETURNING route_stop_id INTO v_id;
  v_count := bps.om_route_stops_renumber(p_tenant_id, v.route_id, v_dow, v_code);
  RETURN jsonb_build_object('route_stop_id', v_id, 'stop_no', (SELECT stop_no FROM om_route_stops WHERE route_stop_id = v_id),
                            'stops', v_count, 'moved_from', v_moved);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.om_route_stop_add(bigint, bigint, text, text, bigint, integer, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.om_route_stop_add(bigint, bigint, text, text, bigint, integer, boolean) TO authenticated, service_role, bps_dev;
