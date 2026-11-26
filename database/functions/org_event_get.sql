-- ============================================================
-- org_event_get
-- One event (the whole series for a repeating event) as the event dialog edits it, with its calendar, who made and
-- last changed it, and a plain description of the repeat ("Weekly on Mon, Wed until 12/31/2026").
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_event_get(p_tenant_id bigint, p_event_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v   org_events;
  v_r jsonb;
BEGIN
  PERFORM bps.org_calendar_check(p_tenant_id, 'R');
  SELECT * INTO v FROM org_events WHERE tenant_id = p_tenant_id AND event_id = p_event_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Event not found'; END IF;
  SELECT jsonb_build_object(
           'event_id', v.event_id, 'calendar_id', v.calendar_id, 'calendar_name', c.calendar_name,
           'calendar_color', c.calendar_color, 'visibility', c.visibility, 'title', v.title, 'location', v.location,
           'notes', v.notes, 'all_day', v.all_day, 'start_date', v.start_date, 'end_date', v.end_date,
           'start_time', to_char(v.start_time, 'HH24:MI'), 'end_time', to_char(v.end_time, 'HH24:MI'),
           'repeat_freq', v.repeat_freq, 'repeat_interval', v.repeat_interval,
           'repeat_days', COALESCE(to_jsonb(v.repeat_days), '[]'::jsonb),
           'repeat_until', v.repeat_until, 'repeat_count', v.repeat_count,
           'repeat_label', CASE v.repeat_freq WHEN 'NONE' THEN NULL ELSE
             CASE WHEN v.repeat_interval = 1 THEN initcap(v.repeat_freq)
                  ELSE 'Every ' || v.repeat_interval || ' ' || CASE v.repeat_freq WHEN 'DAILY' THEN 'days' WHEN 'WEEKLY' THEN 'weeks'
                                                                                  WHEN 'MONTHLY' THEN 'months' ELSE 'years' END END
             || CASE WHEN v.repeat_freq = 'WEEKLY' THEN ' on ' || (
                       SELECT string_agg((ARRAY['Mon','Tue','Wed','Thu','Fri','Sat','Sun'])[d], ', ' ORDER BY d)
                         FROM unnest(COALESCE(v.repeat_days, ARRAY[extract(isodow FROM v.start_date)::smallint])) d) ELSE '' END
             || CASE WHEN v.repeat_until IS NOT NULL THEN ' until ' || to_char(v.repeat_until, 'FMMM/FMDD/YYYY')
                     WHEN v.repeat_count IS NOT NULL THEN ', ' || v.repeat_count || ' times' ELSE '' END END,
           'created_by_name', cu.user_name, 'created_at', v.created_at,
           'updated_by_name', uu.user_name, 'updated_at', v.updated_at)
    INTO v_r
    FROM org_calendars c
    LEFT JOIN fnd_users cu ON cu.user_id = v.created_by
    LEFT JOIN fnd_users uu ON uu.user_id = v.updated_by
   WHERE c.calendar_id = v.calendar_id;
  RETURN v_r;
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_event_get(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_event_get(bigint, bigint) TO authenticated, service_role, bps_dev;
