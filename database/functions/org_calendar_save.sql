-- ============================================================
-- org_calendar_save
-- Creates or changes a calendar. p_payload: { calendar_id (omit for new), calendar_name, calendar_color, visibility }.
-- A private calendar belongs to whoever made it private; only that person sees it and can share it again.
-- Names are unique among the calendars the caller can see, ignoring case. Returns the calendar.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_calendar_save(p_tenant_id bigint, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_user  bigint := bps.fnd_current_user_id();
  v_id    bigint := NULLIF(p_payload ->> 'calendar_id', '')::bigint;
  v_name  text   := NULLIF(btrim(p_payload ->> 'calendar_name'), '');
  v_color text   := COALESCE(NULLIF(lower(btrim(p_payload ->> 'calendar_color')), ''), 'accent');
  v_vis   text   := COALESCE(NULLIF(upper(btrim(p_payload ->> 'visibility')), ''), 'SHARED');
  v_cur   org_calendars;
BEGIN
  PERFORM bps.org_calendar_check(p_tenant_id, 'W');
  IF v_name IS NULL THEN RAISE EXCEPTION 'Give the calendar a name'; END IF;
  IF length(v_name) > 60 THEN RAISE EXCEPTION 'Calendar names are limited to 60 characters'; END IF;
  IF v_color NOT IN ('accent', 'blue', 'green', 'amber', 'red', 'gray') THEN v_color := 'accent'; END IF;
  IF v_vis NOT IN ('SHARED', 'PRIVATE') THEN RAISE EXCEPTION 'Visibility must be SHARED or PRIVATE'; END IF;
  IF EXISTS (SELECT 1 FROM org_calendars WHERE tenant_id = p_tenant_id AND lower(calendar_name) = lower(v_name)
                                           AND calendar_id IS DISTINCT FROM v_id) THEN
    RAISE EXCEPTION 'A calendar named % already exists', v_name;
  END IF;

  IF v_id IS NULL THEN
    INSERT INTO org_calendars (tenant_id, calendar_name, calendar_color, visibility, owner_user_id, display_order, created_by, updated_by)
    VALUES (p_tenant_id, v_name, v_color, v_vis, v_user,
            COALESCE((SELECT max(display_order) FROM org_calendars WHERE tenant_id = p_tenant_id), 0) + 10, v_user, v_user)
    RETURNING calendar_id INTO v_id;
  ELSE
    SELECT * INTO v_cur FROM org_calendars WHERE tenant_id = p_tenant_id AND calendar_id = v_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Calendar not found'; END IF;
    UPDATE org_calendars
       SET calendar_name = v_name, calendar_color = v_color, visibility = v_vis,
           owner_user_id = CASE WHEN v_vis = 'PRIVATE' AND v_cur.visibility = 'SHARED' THEN v_user ELSE owner_user_id END,
           updated_by = v_user
     WHERE calendar_id = v_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'You cannot change this calendar'; END IF;
  END IF;

  RETURN (SELECT jsonb_build_object('calendar_id', c.calendar_id, 'calendar_name', c.calendar_name,
                                    'calendar_color', c.calendar_color, 'visibility', c.visibility)
            FROM org_calendars c WHERE c.calendar_id = v_id);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_calendar_save(bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_calendar_save(bigint, jsonb) TO authenticated, service_role, bps_dev;
