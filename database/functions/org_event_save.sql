-- ============================================================
-- org_event_save
-- Creates or changes an event. p_payload:
--   { event_id (omit for new), calendar_id, title, location, notes, all_day, start_date, start_time ('HH:MI'),
--     end_date, end_time, repeat_freq (NONE|DAILY|WEEKLY|MONTHLY|YEARLY), repeat_interval, repeat_days ([1..7], ISO),
--     repeat_until, repeat_count,
--     scope (ALL|ONE|FOLLOWING, for a repeating event), occurrence_date (the occurrence that was opened) }
-- Changing a repeating event:
--   ALL       : the series changes; a date moved in the dialog moves the whole series by the same number of days.
--   ONE       : that occurrence is removed from the series and saved as its own event.
--   FOLLOWING : the series ends the day before the occurrence; a new series starts from the payload.
-- Returns { event_id } of the event that now holds the change.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_event_save(p_tenant_id bigint, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_user   bigint  := bps.fnd_current_user_id();
  v_id     bigint  := NULLIF(p_payload ->> 'event_id', '')::bigint;
  v_cal    bigint  := NULLIF(p_payload ->> 'calendar_id', '')::bigint;
  v_title  text    := NULLIF(btrim(p_payload ->> 'title'), '');
  v_loc    text    := NULLIF(btrim(p_payload ->> 'location'), '');
  v_notes  text    := NULLIF(btrim(p_payload ->> 'notes'), '');
  v_allday boolean := COALESCE((p_payload ->> 'all_day')::boolean, false);
  v_sd     date    := NULLIF(p_payload ->> 'start_date', '')::date;
  v_ed     date    := NULLIF(p_payload ->> 'end_date', '')::date;
  v_st     time    := NULLIF(p_payload ->> 'start_time', '')::time;
  v_et     time    := NULLIF(p_payload ->> 'end_time', '')::time;
  v_freq   text    := COALESCE(NULLIF(upper(btrim(p_payload ->> 'repeat_freq')), ''), 'NONE');
  v_int    integer := COALESCE(NULLIF(p_payload ->> 'repeat_interval', '')::integer, 1);
  v_days   smallint[];
  v_until  date    := NULLIF(p_payload ->> 'repeat_until', '')::date;
  v_count  integer := NULLIF(p_payload ->> 'repeat_count', '')::integer;
  v_scope  text    := COALESCE(NULLIF(upper(btrim(p_payload ->> 'scope')), ''), 'ALL');
  v_occ    date    := NULLIF(p_payload ->> 'occurrence_date', '')::date;
  v_cur    org_events;
  v_shift  integer;
BEGIN
  PERFORM bps.org_calendar_check(p_tenant_id, 'W');
  IF v_title IS NULL THEN RAISE EXCEPTION 'Give the event a title'; END IF;
  IF length(v_title) > 200 THEN RAISE EXCEPTION 'Titles are limited to 200 characters'; END IF;
  IF length(v_loc) > 200 THEN RAISE EXCEPTION 'Locations are limited to 200 characters'; END IF;
  IF length(v_notes) > 4000 THEN RAISE EXCEPTION 'Notes are limited to 4,000 characters'; END IF;
  IF v_cal IS NULL OR NOT EXISTS (SELECT 1 FROM org_calendars WHERE tenant_id = p_tenant_id AND calendar_id = v_cal) THEN
    RAISE EXCEPTION 'Pick a calendar';
  END IF;
  IF v_sd IS NULL THEN RAISE EXCEPTION 'Give the event a start date'; END IF;
  v_ed := COALESCE(v_ed, v_sd);
  IF v_allday THEN
    v_st := NULL; v_et := NULL;
    IF v_ed < v_sd THEN RAISE EXCEPTION 'The event ends before it starts'; END IF;
  ELSE
    IF v_st IS NULL OR v_et IS NULL THEN RAISE EXCEPTION 'Give the event a start and end time, or make it all day'; END IF;
    IF v_ed < v_sd OR (v_ed = v_sd AND v_et < v_st) THEN RAISE EXCEPTION 'The event ends before it starts'; END IF;
  END IF;
  IF v_ed - v_sd > 366 THEN RAISE EXCEPTION 'An event can last at most a year'; END IF;

  IF v_freq NOT IN ('NONE', 'DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY') THEN RAISE EXCEPTION 'Unknown repeat %', v_freq; END IF;
  IF v_freq = 'NONE' THEN
    v_int := 1; v_until := NULL; v_count := NULL;
  ELSE
    IF v_int < 1 OR v_int > 99 THEN RAISE EXCEPTION 'Repeat every 1 to 99'; END IF;
    IF v_until IS NOT NULL THEN v_count := NULL; END IF;
    IF v_count IS NOT NULL AND (v_count < 1 OR v_count > 999) THEN RAISE EXCEPTION 'Repeat 1 to 999 times'; END IF;
  END IF;
  IF v_freq = 'WEEKLY' THEN
    SELECT array_agg(DISTINCT d::smallint ORDER BY d::smallint) INTO v_days
      FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(p_payload -> 'repeat_days') = 'array' THEN p_payload -> 'repeat_days' ELSE '[]'::jsonb END) d
     WHERE d ~ '^[1-7]$';
    v_days := COALESCE(v_days, ARRAY[extract(isodow FROM v_sd)::smallint]);
  END IF;

  IF v_id IS NOT NULL THEN
    SELECT * INTO v_cur FROM org_events WHERE tenant_id = p_tenant_id AND event_id = v_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Event not found'; END IF;
    IF v_cur.repeat_freq = 'NONE' OR v_occ IS NULL OR v_scope NOT IN ('ONE', 'FOLLOWING')
       OR (v_scope = 'FOLLOWING' AND v_occ <= v_cur.start_date) THEN
      -- The whole event or series. Moving the opened occurrence moves the series by the same number of days.
      IF v_cur.repeat_freq <> 'NONE' AND v_occ IS NOT NULL THEN
        v_shift := v_sd - v_occ;
        v_ed := v_cur.start_date + v_shift + (v_ed - v_sd);
        v_sd := v_cur.start_date + v_shift;
      END IF;
      IF v_until IS NOT NULL AND v_until < v_sd THEN RAISE EXCEPTION 'The repeat ends before the event starts'; END IF;
      UPDATE org_events
         SET calendar_id = v_cal, title = v_title, location = v_loc, notes = v_notes, all_day = v_allday,
             start_date = v_sd, start_time = v_st, end_date = v_ed, end_time = v_et,
             repeat_freq = v_freq, repeat_interval = v_int, repeat_days = v_days, repeat_until = v_until,
             repeat_count = v_count, updated_by = v_user
       WHERE event_id = v_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'You cannot change this event'; END IF;
      RETURN jsonb_build_object('event_id', v_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM bps.org_event_occurrences(v_cur, v_occ, v_occ) o WHERE o = v_occ) THEN
      RAISE EXCEPTION 'That date is not part of the repeating event';
    END IF;
    IF v_scope = 'ONE' THEN
      INSERT INTO org_event_exceptions (tenant_id, event_id, occurrence_date, created_by) VALUES (p_tenant_id, v_id, v_occ, v_user);
      v_freq := 'NONE'; v_int := 1; v_days := NULL; v_until := NULL; v_count := NULL;
    ELSE -- FOLLOWING
      UPDATE org_events SET repeat_until = v_occ - 1, repeat_count = NULL, updated_by = v_user WHERE event_id = v_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'You cannot change this event'; END IF;
    END IF;
  END IF;

  IF v_until IS NOT NULL AND v_until < v_sd THEN RAISE EXCEPTION 'The repeat ends before the event starts'; END IF;
  INSERT INTO org_events (tenant_id, calendar_id, title, location, notes, all_day, start_date, start_time, end_date, end_time,
                          repeat_freq, repeat_interval, repeat_days, repeat_until, repeat_count, created_by, updated_by)
  VALUES (p_tenant_id, v_cal, v_title, v_loc, v_notes, v_allday, v_sd, v_st, v_ed, v_et,
          v_freq, v_int, v_days, v_until, v_count, v_user, v_user)
  RETURNING event_id INTO v_id;
  RETURN jsonb_build_object('event_id', v_id);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_event_save(bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_event_save(bigint, jsonb) TO authenticated, service_role, bps_dev;
