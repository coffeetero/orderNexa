-- ============================================================
-- om_route_sheet_get
-- Printable route sheet(s) in stop order. Without p_date: the weekly stops for p_dow + p_code. With p_date: the routes
-- as they run that date (day of week from the date, date changes applied, om_route_plan). p_route_id NULL = every active
-- route with stops (one per page); a given route is shown even when inactive or empty.
-- Returns { day_of_week, production_code, production_label, date, routes: [{ route_id, route_code, route_name,
--   driver_name, start_time, notes, stops: [{ stop_no, customer_number, customer_name, parent_name, address,
--   window_from, window_to, driver_notes, is_change }] }] }
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_route_sheet_get(p_tenant_id bigint, p_dow text, p_code text, p_route_id bigint DEFAULT NULL, p_date date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_me   bigint := bps.om_route_check(p_tenant_id, 'R');
  v_dow  text   := COALESCE(bps.om_route_dow(p_date), upper(btrim(p_dow)));
  v_code text   := bps.om_route_slot_check(p_tenant_id, v_dow, p_code);
BEGIN
  IF p_route_id IS NOT NULL THEN PERFORM bps.om_route_row_check(p_tenant_id, p_route_id); END IF;
  RETURN jsonb_build_object(
    'day_of_week', v_dow, 'production_code', v_code, 'date', p_date,
    'production_label', COALESCE((SELECT vv.label FROM fnd_valuesets vs JOIN fnd_valueset_values vv ON vv.valueset_id = vs.valueset_id AND vv.tenant_id = vs.tenant_id
                                   WHERE vs.tenant_id = p_tenant_id AND vs.valueset_code = 'PRODUCTIONCODE' AND vv.value = v_code LIMIT 1), v_code),
    'routes', COALESCE((
      WITH st AS (
        SELECT s.route_id, s.ship_to_customer_id, s.stop_no, s.window_from, s.window_to, s.driver_notes, false AS is_change
          FROM om_route_stops s
         WHERE p_date IS NULL AND s.tenant_id = p_tenant_id AND s.day_of_week = v_dow AND s.production_code = v_code
        UNION ALL
        SELECT p.route_id, p.ship_to_customer_id, p.stop_no, p.window_from, p.window_to, p.driver_notes, p.is_exception
          FROM bps.om_route_plan(p_tenant_id, p_date, v_code) p
         WHERE p_date IS NOT NULL AND p.route_id IS NOT NULL
      )
      SELECT jsonb_agg(jsonb_build_object(
               'route_id', r.route_id, 'route_code', r.route_code, 'route_name', r.route_name,
               'driver_name', COALESCE(u.user_name, u.email), 'start_time', to_char(r.start_time, 'HH24:MI'), 'notes', r.notes,
               'stops', COALESCE((
                 SELECT jsonb_agg(jsonb_build_object(
                          'stop_no', st.stop_no, 'customer_number', c.customer_number, 'customer_name', c.customer_name,
                          'parent_name', pc.customer_name, 'address', bps.om_customer_ship_address(p_tenant_id, c.customer_id),
                          'window_from', to_char(st.window_from, 'HH24:MI'), 'window_to', to_char(st.window_to, 'HH24:MI'),
                          'driver_notes', st.driver_notes, 'is_change', st.is_change) ORDER BY st.stop_no)
                   FROM st JOIN fnd_customers c ON c.customer_id = st.ship_to_customer_id
                   LEFT JOIN fnd_customers pc ON pc.customer_id = c.customer_parent_id
                  WHERE st.route_id = r.route_id), '[]'::jsonb))
             ORDER BY r.sort_order, upper(r.route_code))
        FROM om_routes r
        LEFT JOIN fnd_users u ON u.user_id = r.default_driver_user_id
       WHERE r.tenant_id = p_tenant_id
         AND (r.route_id = p_route_id OR (p_route_id IS NULL AND r.is_active AND EXISTS (SELECT 1 FROM st WHERE st.route_id = r.route_id)))
    ), '[]'::jsonb));
END $function$;
REVOKE EXECUTE ON FUNCTION bps.om_route_sheet_get(bigint, text, text, bigint, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.om_route_sheet_get(bigint, text, text, bigint, date) TO authenticated, service_role, bps_dev;
