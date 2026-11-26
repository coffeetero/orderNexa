-- ============================================================
-- om_customer_routes_get
-- Customer Management (read only): a ship-to location's route stops per day of week + production code. A day + code
-- with no stop of its own shows the nearest ancestor's stop it follows (inherited_from). Also its date changes from
-- today on. Staff with delivery.routes or customers.profiles read access.
-- Returns { stops: [{ day_of_week, production_code, production_label, route_code, route_name, stop_no, inherited_from }],
--   changes: [{ exception_date, production_code, kind 'SKIP'|'ROUTE', route_code, stop_no }] }
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_customer_routes_get(p_tenant_id bigint, p_customer_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_is_tenant_staff(p_tenant_id) OR NOT bps.fnd_has_access_any(ARRAY['delivery.routes', 'customers.profiles'], 'R') THEN
    RAISE EXCEPTION 'You do not have access to view routes' USING ERRCODE = '42501';
  END IF;
  IF NOT (bps.fnd_scope_is_all() OR p_customer_id = ANY (COALESCE(bps.fnd_scope_customer_ids(), '{}'::bigint[]))) THEN
    RAISE EXCEPTION 'Customer not found';
  END IF;
  RETURN jsonb_build_object(
    'stops', COALESCE((
      WITH RECURSIVE up AS (
        SELECT c.customer_id, c.customer_parent_id, c.customer_name, 0 AS depth
          FROM fnd_customers c WHERE c.tenant_id = p_tenant_id AND c.customer_id = p_customer_id
        UNION ALL
        SELECT c.customer_id, c.customer_parent_id, c.customer_name, up.depth + 1
          FROM fnd_customers c JOIN up ON c.customer_id = up.customer_parent_id WHERE c.tenant_id = p_tenant_id AND up.depth < 10
      ), pick AS (
        SELECT DISTINCT ON (s.day_of_week, s.production_code) s.day_of_week, s.production_code, s.stop_no, s.route_id, up.depth, up.customer_name
          FROM om_route_stops s JOIN up ON up.customer_id = s.ship_to_customer_id
         WHERE s.tenant_id = p_tenant_id
         ORDER BY s.day_of_week, s.production_code, up.depth
      )
      SELECT jsonb_agg(jsonb_build_object(
               'day_of_week', p.day_of_week, 'production_code', p.production_code, 'production_label', COALESCE(vv.label, p.production_code),
               'route_code', r.route_code, 'route_name', r.route_name, 'route_active', r.is_active, 'stop_no', p.stop_no,
               'inherited_from', CASE WHEN p.depth > 0 THEN p.customer_name END)
             ORDER BY COALESCE(vv.display_order, 1000000), p.production_code,
                      array_position(ARRAY['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'], p.day_of_week))
        FROM pick p
        JOIN om_routes r ON r.route_id = p.route_id
        LEFT JOIN fnd_valuesets vs ON vs.tenant_id = p_tenant_id AND vs.valueset_code = 'PRODUCTIONCODE'
        LEFT JOIN fnd_valueset_values vv ON vv.valueset_id = vs.valueset_id AND vv.tenant_id = p_tenant_id AND vv.value = p.production_code), '[]'::jsonb),
    'changes', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('exception_date', e.exception_date, 'production_code', e.production_code,
                                          'kind', CASE WHEN e.route_id IS NULL THEN 'SKIP' ELSE 'ROUTE' END,
                                          'route_code', r.route_code, 'stop_no', e.stop_no) ORDER BY e.exception_date, e.production_code)
        FROM om_route_stop_exceptions e LEFT JOIN om_routes r ON r.route_id = e.route_id
       WHERE e.tenant_id = p_tenant_id AND e.ship_to_customer_id = p_customer_id AND e.exception_date >= current_date), '[]'::jsonb));
END $function$;
REVOKE EXECUTE ON FUNCTION bps.om_customer_routes_get(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.om_customer_routes_get(bigint, bigint) TO authenticated, service_role, bps_dev;
