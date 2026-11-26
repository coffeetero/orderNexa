-- ============================================================
-- org_calendar_check
-- Internal: checks the caller works in p_tenant_id and has Organizer › Calendar access for p_action
-- ('R' view, 'W' add/change, 'D' delete). Raises a readable error otherwise.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_calendar_check(p_tenant_id bigint, p_action text)
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path TO 'bps', 'public'
AS $function$
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_is_trusted() AND NOT bps.fnd_has_access('organizer.calendar', p_action) THEN
    RAISE EXCEPTION 'You do not have access to % the calendar',
      CASE upper(p_action) WHEN 'R' THEN 'view' WHEN 'D' THEN 'delete from' ELSE 'change' END USING ERRCODE = '42501';
  END IF;
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_calendar_check(bigint, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_calendar_check(bigint, text) TO authenticated, service_role, bps_dev;
