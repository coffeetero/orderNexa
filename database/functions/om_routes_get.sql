-- ============================================================
-- om_routes_get
-- Routes Maintenance: the tenant's routes with their stop counts for every day of the week for one production code
-- (NULL = the first active code), the staff users who can be default drivers and the production codes with labels.
-- Returns { production_code, production_codes: [{ code, label }], staff: [{ user_id, user_name }],
--   routes: [{ route_id, route_code, route_name, sort_order, is_active, default_driver_user_id, driver_name, start_time,
--              notes, counts: { MON: n, ..., SUN: n } }] }   (routes by sort order, then code)
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_routes_get(p_tenant_id bigint, p_production_code text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_me    bigint := bps.om_route_check(p_tenant_id, 'R');
  v_codes jsonb;
  v_code  text := NULLIF(upper(btrim(p_production_code)), '');
BEGIN
  SELECT COALESCE(jsonb_agg(jsonb_build_object('code', x.production_code, 'label', x.label) ORDER BY x.ord, x.production_code), '[]'::jsonb)
    INTO v_codes
    FROM (SELECT pc.production_code, COALESCE(vv.label, pc.production_code) AS label, COALESCE(vv.display_order, 1000000) AS ord
            FROM om_production_codes pc
            LEFT JOIN fnd_valuesets vs ON vs.tenant_id = pc.tenant_id AND vs.valueset_code = 'PRODUCTIONCODE'
            LEFT JOIN fnd_valueset_values vv ON vv.valueset_id = vs.valueset_id AND vv.tenant_id = pc.tenant_id AND vv.value = pc.production_code
           WHERE pc.tenant_id = p_tenant_id AND (pc.is_active OR pc.production_code = v_code)) x;
  IF v_code IS NULL THEN
    v_code := v_codes->0->>'code';
  ELSIF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_codes) c WHERE c->>'code' = v_code) THEN
    RAISE EXCEPTION 'Unknown production time %', p_production_code;
  END IF;

  RETURN jsonb_build_object(
    'production_code', v_code,
    'production_codes', v_codes,
    'staff', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('user_id', u.user_id, 'user_name', COALESCE(u.user_name, u.email)) ORDER BY lower(COALESCE(u.user_name, u.email)))
        FROM fnd_user_tenants ut JOIN fnd_users u ON u.user_id = ut.user_id
       WHERE ut.tenant_id = p_tenant_id AND ut.is_active AND u.is_active AND u.deleted_at IS NULL AND u.user_type = 'TENANCY_USER'), '[]'::jsonb),
    'routes', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'route_id', r.route_id, 'route_code', r.route_code, 'route_name', r.route_name, 'sort_order', r.sort_order,
               'is_active', r.is_active, 'default_driver_user_id', r.default_driver_user_id,
               'driver_name', COALESCE(u.user_name, u.email), 'start_time', to_char(r.start_time, 'HH24:MI'), 'notes', r.notes,
               'counts', (SELECT jsonb_object_agg(d.dow, COALESCE(c.n, 0))
                            FROM unnest(ARRAY['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN']) AS d(dow)
                            LEFT JOIN (SELECT s.day_of_week, count(*) AS n FROM om_route_stops s
                                        WHERE s.route_id = r.route_id AND s.production_code = v_code GROUP BY s.day_of_week) c
                              ON c.day_of_week = d.dow))
             ORDER BY r.sort_order, upper(r.route_code))
        FROM om_routes r
        LEFT JOIN fnd_users u ON u.user_id = r.default_driver_user_id
       WHERE r.tenant_id = p_tenant_id), '[]'::jsonb));
END $function$;
REVOKE EXECUTE ON FUNCTION bps.om_routes_get(bigint, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.om_routes_get(bigint, text) TO authenticated, service_role, bps_dev;
