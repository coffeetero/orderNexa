-- ============================================================
-- om_route_stops_renumber
-- Internal: renumbers one route's stops for a day of week + production code to 1..n, keeping their order
-- (stop_no, then oldest first). Called by the Routes Maintenance functions after every add, move, remove and copy.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_route_stops_renumber(p_tenant_id bigint, p_route_id bigint, p_dow text, p_code text)
RETURNS integer
LANGUAGE plpgsql
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  n integer;
BEGIN
  WITH o AS (
    SELECT route_stop_id, row_number() OVER (ORDER BY stop_no, route_stop_id)::int AS rn
      FROM om_route_stops
     WHERE tenant_id = p_tenant_id AND route_id = p_route_id AND day_of_week = p_dow AND production_code = p_code
  )
  UPDATE om_route_stops s SET stop_no = o.rn FROM o WHERE s.route_stop_id = o.route_stop_id AND s.stop_no <> o.rn;
  SELECT count(*) INTO n FROM om_route_stops
   WHERE tenant_id = p_tenant_id AND route_id = p_route_id AND day_of_week = p_dow AND production_code = p_code;
  RETURN n;
END $function$;
REVOKE EXECUTE ON FUNCTION bps.om_route_stops_renumber(bigint, bigint, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION bps.om_route_stops_renumber(bigint, bigint, text, text) TO service_role, bps_dev;
