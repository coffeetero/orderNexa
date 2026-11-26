-- ============================================================
-- org_calendars_get
-- The calendars the caller can see (shared ones and their own private ones), with the company time zone, today in that
-- zone and what the caller may do. Adds the starting calendars the first time a company opens the Calendar.
-- Row security decides what is listed.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_calendars_get(p_tenant_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_user bigint := bps.fnd_current_user_id();
  v_tz   text   := COALESCE(bps.fnd_tenant_time_zone(p_tenant_id), 'America/New_York');
BEGIN
  PERFORM bps.org_calendar_check(p_tenant_id, 'R');
  PERFORM bps.org_calendar_seed(p_tenant_id);
  RETURN jsonb_build_object(
    'time_zone', v_tz,
    'today', (now() AT TIME ZONE v_tz)::date,
    'can_edit', bps.fnd_is_trusted() OR bps.fnd_has_access('organizer.calendar', 'W'),
    'can_delete', bps.fnd_is_trusted() OR bps.fnd_has_access('organizer.calendar', 'D'),
    'calendars', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'calendar_id', c.calendar_id, 'calendar_name', c.calendar_name, 'calendar_color', c.calendar_color,
               'visibility', c.visibility, 'is_owner', c.owner_user_id IS NOT NULL AND c.owner_user_id = v_user,
               'owner_name', u.user_name)
             ORDER BY c.visibility DESC, c.display_order, lower(c.calendar_name))
        FROM org_calendars c LEFT JOIN fnd_users u ON u.user_id = c.owner_user_id
       WHERE c.tenant_id = p_tenant_id), '[]'::jsonb));
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_calendars_get(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_calendars_get(bigint) TO authenticated, service_role, bps_dev;
