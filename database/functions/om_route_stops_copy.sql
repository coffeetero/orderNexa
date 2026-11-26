-- ============================================================
-- om_route_stops_copy
-- Copies one route's stops for a day of week + production code (with windows and driver notes) to other days and/or
-- codes of the same route. p_targets: [{ day_of_week, production_code }] (the source itself is ignored).
-- p_mode 'REPLACE': the target gets exactly the source's stops (its own stops are removed first);
--        'MERGE'  : the target keeps its stops; source stops it lacks are added at the end in source order.
-- A ship-to already on another route on a target day + code is skipped (one route per ship-to) and reported.
-- Returns { targets, copied, skipped: [{ day_of_week, production_code, customer_name, route_code }] }.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_route_stops_copy(p_tenant_id bigint, p_route_id bigint, p_dow text, p_code text,
                                                   p_targets jsonb, p_mode text DEFAULT 'REPLACE')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_me      bigint := bps.om_route_check(p_tenant_id, 'W');
  v_code    text   := bps.om_route_slot_check(p_tenant_id, p_dow, p_code);
  v_dow     text   := upper(btrim(p_dow));
  v         bps.om_routes := bps.om_route_row_check(p_tenant_id, p_route_id);
  v_mode    text   := upper(btrim(COALESCE(p_mode, 'REPLACE')));
  t         record;
  v_targets integer := 0;
  v_copied  integer := 0;
  v_n       integer;
  v_skipped jsonb := '[]'::jsonb;
BEGIN
  IF v_mode NOT IN ('REPLACE', 'MERGE') THEN RAISE EXCEPTION 'Copy mode must be REPLACE or MERGE'; END IF;
  IF p_targets IS NULL OR jsonb_typeof(p_targets) <> 'array' OR jsonb_array_length(p_targets) = 0 THEN
    RAISE EXCEPTION 'Choose at least one day or production time to copy to';
  END IF;
  PERFORM 1 FROM om_routes WHERE route_id = v.route_id FOR UPDATE;

  FOR t IN
    SELECT DISTINCT upper(btrim(x->>'day_of_week')) AS dow, upper(btrim(x->>'production_code')) AS code
      FROM jsonb_array_elements(p_targets) x
  LOOP
    PERFORM bps.om_route_slot_check(p_tenant_id, t.dow, t.code);
    CONTINUE WHEN t.dow = v_dow AND t.code = v_code;
    v_targets := v_targets + 1;
    IF v_mode = 'REPLACE' THEN
      DELETE FROM om_route_stops WHERE route_id = v.route_id AND day_of_week = t.dow AND production_code = t.code;
    END IF;

    SELECT v_skipped || COALESCE(jsonb_agg(jsonb_build_object('day_of_week', t.dow, 'production_code', t.code,
                                                              'customer_name', c.customer_name, 'route_code', r.route_code)
                                           ORDER BY s.stop_no), '[]'::jsonb)
      INTO v_skipped
      FROM om_route_stops s
      JOIN om_route_stops o ON o.tenant_id = s.tenant_id AND o.day_of_week = t.dow AND o.production_code = t.code
                           AND o.ship_to_customer_id = s.ship_to_customer_id AND o.route_id <> v.route_id
      JOIN om_routes r ON r.route_id = o.route_id
      JOIN fnd_customers c ON c.customer_id = s.ship_to_customer_id
     WHERE s.route_id = v.route_id AND s.day_of_week = v_dow AND s.production_code = v_code;

    INSERT INTO om_route_stops (tenant_id, route_id, day_of_week, production_code, ship_to_customer_id, stop_no,
                                window_from, window_to, driver_notes, created_by, updated_by)
    SELECT p_tenant_id, v.route_id, t.dow, t.code, s.ship_to_customer_id,
           (SELECT COALESCE(max(x.stop_no), 0) FROM om_route_stops x
             WHERE x.route_id = v.route_id AND x.day_of_week = t.dow AND x.production_code = t.code)
           + row_number() OVER (ORDER BY s.stop_no),
           s.window_from, s.window_to, s.driver_notes, v_me, v_me
      FROM om_route_stops s
     WHERE s.route_id = v.route_id AND s.day_of_week = v_dow AND s.production_code = v_code
       AND NOT EXISTS (SELECT 1 FROM om_route_stops o
                        WHERE o.tenant_id = p_tenant_id AND o.day_of_week = t.dow AND o.production_code = t.code
                          AND o.ship_to_customer_id = s.ship_to_customer_id);
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_copied := v_copied + v_n;
    PERFORM bps.om_route_stops_renumber(p_tenant_id, v.route_id, t.dow, t.code);
  END LOOP;
  RETURN jsonb_build_object('targets', v_targets, 'copied', v_copied, 'skipped', v_skipped);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.om_route_stops_copy(bigint, bigint, text, text, jsonb, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.om_route_stops_copy(bigint, bigint, text, text, jsonb, text) TO authenticated, service_role, bps_dev;
