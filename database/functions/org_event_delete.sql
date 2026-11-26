-- ============================================================
-- org_event_delete
-- Deletes an event. For a repeating event p_scope says how much:
--   ALL (default) : the whole series
--   ONE           : only the occurrence on p_occurrence_date
--   FOLLOWING     : that occurrence and every later one (the series ends the day before)
-- Returns { event_id, result: 'DELETED' | 'OCCURRENCE_REMOVED' | 'SERIES_ENDED' }.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_event_delete(p_tenant_id bigint, p_event_id bigint, p_scope text DEFAULT 'ALL',
                                                p_occurrence_date date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_scope text := COALESCE(NULLIF(upper(btrim(p_scope)), ''), 'ALL');
  v       org_events;
BEGIN
  PERFORM bps.org_calendar_check(p_tenant_id, 'D');
  SELECT * INTO v FROM org_events WHERE tenant_id = p_tenant_id AND event_id = p_event_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Event not found'; END IF;

  IF v.repeat_freq <> 'NONE' AND p_occurrence_date IS NOT NULL AND v_scope = 'ONE' THEN
    INSERT INTO org_event_exceptions (tenant_id, event_id, occurrence_date, created_by)
    VALUES (p_tenant_id, v.event_id, p_occurrence_date, bps.fnd_current_user_id())
    ON CONFLICT DO NOTHING;
    RETURN jsonb_build_object('event_id', v.event_id, 'result', 'OCCURRENCE_REMOVED');
  END IF;
  IF v.repeat_freq <> 'NONE' AND p_occurrence_date IS NOT NULL AND v_scope = 'FOLLOWING' AND p_occurrence_date > v.start_date THEN
    UPDATE org_events SET repeat_until = p_occurrence_date - 1, repeat_count = NULL, updated_by = bps.fnd_current_user_id()
     WHERE event_id = v.event_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'You cannot change this event'; END IF;
    RETURN jsonb_build_object('event_id', v.event_id, 'result', 'SERIES_ENDED');
  END IF;

  DELETE FROM org_events WHERE event_id = v.event_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'You cannot delete this event'; END IF;
  RETURN jsonb_build_object('event_id', v.event_id, 'result', 'DELETED');
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_event_delete(bigint, bigint, text, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_event_delete(bigint, bigint, text, date) TO authenticated, service_role, bps_dev;
