-- ============================================================
-- om_route_exceptions_get
-- Routes Maintenance › Date changes: one-off changes with delivery date in [p_from, p_to] (one production code when
-- given), with the ship-to and where it usually is that day.
-- Returns { changes: [{ exception_id, exception_date, day_of_week, production_code, customer_id, customer_number,
--   customer_name, kind 'SKIP'|'ROUTE', route_id, route_code, route_name, stop_no, notes, usual_route_code, usual_stop_no }] }
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_route_exceptions_get(p_tenant_id bigint, p_from date, p_to date, p_code text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_me   bigint := bps.om_route_check(p_tenant_id, 'R');
  v_code text   := NULLIF(upper(btrim(p_code)), '');
BEGIN
  IF p_from IS NULL OR p_to IS NULL OR p_to < p_from THEN RAISE EXCEPTION 'A valid from date and to date are required'; END IF;
  RETURN jsonb_build_object('changes', COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
             'exception_id', e.exception_id, 'exception_date', e.exception_date, 'day_of_week', bps.om_route_dow(e.exception_date),
             'production_code', e.production_code, 'customer_id', c.customer_id, 'customer_number', c.customer_number,
             'customer_name', c.customer_name, 'kind', CASE WHEN e.route_id IS NULL THEN 'SKIP' ELSE 'ROUTE' END,
             'route_id', e.route_id, 'route_code', r.route_code, 'route_name', r.route_name, 'stop_no', e.stop_no, 'notes', e.notes,
             'usual_route_code', ur.route_code, 'usual_stop_no', us.stop_no)
           ORDER BY e.exception_date, e.production_code, r.sort_order NULLS FIRST, e.stop_no, upper(c.customer_name))
      FROM om_route_stop_exceptions e
      JOIN fnd_customers c ON c.customer_id = e.ship_to_customer_id
      LEFT JOIN om_routes r ON r.route_id = e.route_id
      LEFT JOIN om_route_stops us ON us.tenant_id = e.tenant_id AND us.day_of_week = bps.om_route_dow(e.exception_date)
                                 AND us.production_code = e.production_code AND us.ship_to_customer_id = e.ship_to_customer_id
      LEFT JOIN om_routes ur ON ur.route_id = us.route_id
     WHERE e.tenant_id = p_tenant_id AND e.exception_date BETWEEN p_from AND p_to
       AND (v_code IS NULL OR e.production_code = v_code)), '[]'::jsonb));
END $function$;
REVOKE EXECUTE ON FUNCTION bps.om_route_exceptions_get(bigint, date, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.om_route_exceptions_get(bigint, date, date, text) TO authenticated, service_role, bps_dev;
