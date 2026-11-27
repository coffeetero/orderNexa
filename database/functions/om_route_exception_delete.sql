-- ============================================================
-- om_route_exception_delete
-- Removes a one-off date change; the ship-to goes back to its usual stop for that date. Returns { exception_id }.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_route_exception_delete(p_tenant_id bigint, p_exception_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_me bigint := bps.om_route_check(p_tenant_id, 'W');
BEGIN
  DELETE FROM om_route_stop_exceptions WHERE tenant_id = p_tenant_id AND exception_id = p_exception_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Date change not found'; END IF;
  RETURN jsonb_build_object('exception_id', p_exception_id);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.om_route_exception_delete(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.om_route_exception_delete(bigint, bigint) TO authenticated, service_role, bps_dev;
