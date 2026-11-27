-- ============================================================
-- om_route_save
-- Creates (no route_id) or updates a route. p_route: { route_id?, route_code*, route_name*, sort_order?, is_active?,
--   default_driver_user_id?, start_time? 'HH:MM', notes? }. A new route without sort_order goes last.
-- The default driver must be an active staff user of the company. Codes are unique per company (any case).
-- Returns { route_id, route_code, route_name, sort_order, is_active, default_driver_user_id, start_time, notes }.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_route_save(p_tenant_id bigint, p_route jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_me     bigint := bps.om_route_check(p_tenant_id, 'W');
  v_id     bigint := NULLIF(p_route->>'route_id', '')::bigint;
  v_code   text   := NULLIF(btrim(p_route->>'route_code'), '');
  v_name   text   := NULLIF(btrim(p_route->>'route_name'), '');
  v_sort   integer := NULLIF(btrim(p_route->>'sort_order'), '')::integer;
  v_driver bigint := NULLIF(p_route->>'default_driver_user_id', '')::bigint;
  v_start  time   := NULLIF(btrim(p_route->>'start_time'), '')::time;
  v_notes  text   := NULLIF(btrim(p_route->>'notes'), '');
  v_active boolean := COALESCE((p_route->>'is_active')::boolean, true);
  v        bps.om_routes;
BEGIN
  IF v_code IS NULL THEN RAISE EXCEPTION 'A route code is required'; END IF;
  IF v_name IS NULL THEN RAISE EXCEPTION 'A route name is required'; END IF;
  IF v_driver IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM fnd_user_tenants ut JOIN fnd_users u ON u.user_id = ut.user_id
       WHERE ut.tenant_id = p_tenant_id AND ut.user_id = v_driver AND ut.is_active AND u.is_active AND u.deleted_at IS NULL
         AND u.user_type = 'TENANCY_USER') THEN
    RAISE EXCEPTION 'The driver must be an active staff user of this company';
  END IF;
  IF EXISTS (SELECT 1 FROM om_routes WHERE tenant_id = p_tenant_id AND upper(route_code) = upper(v_code) AND route_id IS DISTINCT FROM v_id) THEN
    RAISE EXCEPTION 'Route code % is already used', v_code;
  END IF;

  IF v_id IS NULL THEN
    INSERT INTO om_routes (tenant_id, route_code, route_name, sort_order, is_active, default_driver_user_id, start_time, notes, created_by, updated_by)
    VALUES (p_tenant_id, v_code, v_name,
            COALESCE(v_sort, (SELECT COALESCE(max(sort_order), 0) + 1 FROM om_routes WHERE tenant_id = p_tenant_id)),
            v_active, v_driver, v_start, v_notes, v_me, v_me)
    RETURNING * INTO v;
  ELSE
    PERFORM bps.om_route_row_check(p_tenant_id, v_id);
    UPDATE om_routes SET route_code = v_code, route_name = v_name, sort_order = COALESCE(v_sort, sort_order), is_active = v_active,
                         default_driver_user_id = v_driver, start_time = v_start, notes = v_notes, updated_by = v_me
     WHERE route_id = v_id
    RETURNING * INTO v;
  END IF;
  RETURN jsonb_build_object('route_id', v.route_id, 'route_code', v.route_code, 'route_name', v.route_name, 'sort_order', v.sort_order,
                            'is_active', v.is_active, 'default_driver_user_id', v.default_driver_user_id,
                            'start_time', to_char(v.start_time, 'HH24:MI'), 'notes', v.notes);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.om_route_save(bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.om_route_save(bigint, jsonb) TO authenticated, service_role, bps_dev;
