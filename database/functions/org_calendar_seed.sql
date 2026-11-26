-- ============================================================
-- org_calendar_seed
-- Gives a company its starting shared calendars (Company, Deliveries & catering, Staff, Closed & holidays) when it has
-- no shared calendar yet. Called by the migration and the first time the Calendar opens. Returns how many were added.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_calendar_seed(p_tenant_id bigint)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_n integer;
BEGIN
  PERFORM bps.org_calendar_check(p_tenant_id, 'R');
  IF EXISTS (SELECT 1 FROM org_calendars WHERE tenant_id = p_tenant_id AND visibility = 'SHARED') THEN RETURN 0; END IF;
  INSERT INTO org_calendars (tenant_id, calendar_name, calendar_color, visibility, display_order, created_by, updated_by)
  SELECT p_tenant_id, x.name, x.color, 'SHARED', x.ord, bps.fnd_current_user_id(), bps.fnd_current_user_id()
    FROM (VALUES ('Company', 'accent', 10), ('Deliveries & catering', 'blue', 20), ('Staff', 'green', 30),
                 ('Closed & holidays', 'red', 40)) x(name, color, ord);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_calendar_seed(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_calendar_seed(bigint) TO authenticated, service_role, bps_dev;
