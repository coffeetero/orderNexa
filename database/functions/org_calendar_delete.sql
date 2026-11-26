-- ============================================================
-- org_calendar_delete
-- Deletes a calendar and every event on it. Returns { calendar_id, events_deleted }.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_calendar_delete(p_tenant_id bigint, p_calendar_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_events integer;
BEGIN
  PERFORM bps.org_calendar_check(p_tenant_id, 'D');
  IF NOT EXISTS (SELECT 1 FROM org_calendars WHERE tenant_id = p_tenant_id AND calendar_id = p_calendar_id) THEN
    RAISE EXCEPTION 'Calendar not found';
  END IF;
  SELECT count(*) INTO v_events FROM org_events WHERE calendar_id = p_calendar_id;
  DELETE FROM org_calendars WHERE tenant_id = p_tenant_id AND calendar_id = p_calendar_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'You cannot delete this calendar'; END IF;
  RETURN jsonb_build_object('calendar_id', p_calendar_id, 'events_deleted', v_events);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_calendar_delete(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_calendar_delete(bigint, bigint) TO authenticated, service_role, bps_dev;
