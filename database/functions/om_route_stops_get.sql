-- ============================================================
-- om_route_stops_get
-- Routes Maintenance: one route's stops for a day of week + production code, in stop order, with the ship-to's
-- customer number, name, parent account and delivery address; plus where every ship-to is that day + code (all routes),
-- so the add search can say "on 102, stop 4".
-- Returns { route: { route_id, route_code, route_name, is_active }, day_of_week, production_code,
--   stops: [{ route_stop_id, stop_no, customer_id, customer_number, customer_name, customer_type, parent_name, is_active,
--             address, window_from 'HH:MM', window_to, driver_notes }],
--   day_assignments: [{ customer_id, route_id, route_code, stop_no }] }
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_route_stops_get(p_tenant_id bigint, p_route_id bigint, p_dow text, p_code text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_me   bigint := bps.om_route_check(p_tenant_id, 'R');
  v_code text   := bps.om_route_slot_check(p_tenant_id, p_dow, p_code);
  v_dow  text   := upper(btrim(p_dow));
  v      bps.om_routes := bps.om_route_row_check(p_tenant_id, p_route_id);
BEGIN
  RETURN jsonb_build_object(
    'route', jsonb_build_object('route_id', v.route_id, 'route_code', v.route_code, 'route_name', v.route_name, 'is_active', v.is_active),
    'day_of_week', v_dow, 'production_code', v_code,
    'stops', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'route_stop_id', s.route_stop_id, 'stop_no', s.stop_no, 'customer_id', c.customer_id,
               'customer_number', c.customer_number, 'customer_name', c.customer_name, 'customer_type', c.customer_type,
               'parent_name', p.customer_name, 'is_active', c.is_active,
               'address', bps.om_customer_ship_address(p_tenant_id, c.customer_id),
               'window_from', to_char(s.window_from, 'HH24:MI'), 'window_to', to_char(s.window_to, 'HH24:MI'),
               'driver_notes', s.driver_notes) ORDER BY s.stop_no)
        FROM om_route_stops s
        JOIN fnd_customers c ON c.customer_id = s.ship_to_customer_id
        LEFT JOIN fnd_customers p ON p.customer_id = c.customer_parent_id
       WHERE s.tenant_id = p_tenant_id AND s.route_id = v.route_id AND s.day_of_week = v_dow AND s.production_code = v_code), '[]'::jsonb),
    'day_assignments', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('customer_id', s.ship_to_customer_id, 'route_id', s.route_id, 'route_code', r.route_code, 'stop_no', s.stop_no))
        FROM om_route_stops s JOIN om_routes r ON r.route_id = s.route_id
       WHERE s.tenant_id = p_tenant_id AND s.day_of_week = v_dow AND s.production_code = v_code), '[]'::jsonb));
END $function$;
REVOKE EXECUTE ON FUNCTION bps.om_route_stops_get(bigint, bigint, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.om_route_stops_get(bigint, bigint, text, text) TO authenticated, service_role, bps_dev;
