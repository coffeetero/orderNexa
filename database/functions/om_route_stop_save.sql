-- ============================================================
-- om_route_stop_save
-- Saves a stop's delivery window and driver notes. p_stop: { window_from 'HH:MM' | '', window_to, driver_notes }.
-- Keys left out keep their value. Returns { route_stop_id, window_from, window_to, driver_notes }.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_route_stop_save(p_tenant_id bigint, p_route_stop_id bigint, p_stop jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_me bigint := bps.om_route_check(p_tenant_id, 'W');
  v    bps.om_route_stops;
BEGIN
  SELECT * INTO v FROM om_route_stops WHERE tenant_id = p_tenant_id AND route_stop_id = p_route_stop_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Stop not found'; END IF;
  IF p_stop ? 'window_from' THEN v.window_from := NULLIF(btrim(p_stop->>'window_from'), '')::time; END IF;
  IF p_stop ? 'window_to' THEN v.window_to := NULLIF(btrim(p_stop->>'window_to'), '')::time; END IF;
  IF p_stop ? 'driver_notes' THEN v.driver_notes := NULLIF(btrim(p_stop->>'driver_notes'), ''); END IF;
  IF v.window_from IS NOT NULL AND v.window_to IS NOT NULL AND v.window_to < v.window_from THEN
    RAISE EXCEPTION 'The window ends before it starts';
  END IF;
  UPDATE om_route_stops SET window_from = v.window_from, window_to = v.window_to, driver_notes = v.driver_notes, updated_by = v_me
   WHERE route_stop_id = v.route_stop_id;
  RETURN jsonb_build_object('route_stop_id', v.route_stop_id, 'window_from', to_char(v.window_from, 'HH24:MI'),
                            'window_to', to_char(v.window_to, 'HH24:MI'), 'driver_notes', v.driver_notes);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.om_route_stop_save(bigint, bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.om_route_stop_save(bigint, bigint, jsonb) TO authenticated, service_role, bps_dev;
