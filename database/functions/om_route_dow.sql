-- ============================================================
-- om_route_dow
-- Day-of-week key used by Routes Maintenance for a date: MON, TUE, WED, THU, FRI, SAT or SUN (not locale dependent).
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_route_dow(p_date date)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO 'bps', 'public'
AS $function$
  SELECT (ARRAY['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'])[extract(isodow FROM p_date)::int];
$function$;
GRANT EXECUTE ON FUNCTION bps.om_route_dow(date) TO authenticated, service_role, bps_dev;
