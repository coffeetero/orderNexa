-- ============================================================
-- om_route_exception_save
-- Records a one-off change for one delivery date + production code (replaces an earlier change for the same ship-to,
-- date and code). p_exception: { exception_date*, production_code*, customer_id*, kind 'SKIP' | 'ROUTE',
--   route_id + stop_no (kind ROUTE: on that route at that stop for the date), notes? }.
-- Honoured by Process run (route stamping) and the route sheet for that date. Returns { exception_id }.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_route_exception_save(p_tenant_id bigint, p_exception jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_me    bigint := bps.om_route_check(p_tenant_id, 'W');
  v_date  date   := NULLIF(btrim(p_exception->>'exception_date'), '')::date;
  v_kind  text   := upper(btrim(COALESCE(p_exception->>'kind', 'SKIP')));
  v_route bigint := NULLIF(p_exception->>'route_id', '')::bigint;
  v_stop  integer := NULLIF(btrim(p_exception->>'stop_no'), '')::integer;
  v_code  text;
  c       bps.fnd_customers;
  v_id    bigint;
BEGIN
  IF v_date IS NULL THEN RAISE EXCEPTION 'A date is required'; END IF;
  v_code := bps.om_route_slot_check(p_tenant_id, bps.om_route_dow(v_date), p_exception->>'production_code');
  c := bps.om_route_ship_to_check(p_tenant_id, NULLIF(p_exception->>'customer_id', '')::bigint);
  IF v_kind = 'SKIP' THEN
    v_route := NULL; v_stop := NULL;
  ELSIF v_kind = 'ROUTE' THEN
    IF v_route IS NULL THEN RAISE EXCEPTION 'Choose the route for that date'; END IF;
    PERFORM bps.om_route_row_check(p_tenant_id, v_route);
    v_stop := GREATEST(COALESCE(v_stop, 1), 1);
  ELSE
    RAISE EXCEPTION 'The change must be SKIP or ROUTE';
  END IF;
  INSERT INTO om_route_stop_exceptions (tenant_id, exception_date, production_code, ship_to_customer_id, route_id, stop_no, notes, created_by, updated_by)
  VALUES (p_tenant_id, v_date, v_code, c.customer_id, v_route, v_stop, NULLIF(btrim(p_exception->>'notes'), ''), v_me, v_me)
  ON CONFLICT (tenant_id, exception_date, production_code, ship_to_customer_id)
  DO UPDATE SET route_id = EXCLUDED.route_id, stop_no = EXCLUDED.stop_no, notes = EXCLUDED.notes, updated_by = v_me
  RETURNING exception_id INTO v_id;
  RETURN jsonb_build_object('exception_id', v_id);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.om_route_exception_save(bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.om_route_exception_save(bigint, jsonb) TO authenticated, service_role, bps_dev;
