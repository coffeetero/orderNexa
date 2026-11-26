-- ============================================================
-- org_calendar_view_get
-- Everything one calendar view shows, worked out in the company's time zone:
--   p_view    : 'day' | 'week' | 'month' | 'agenda' (30 days from the anchor) | 'mini' (month grid, no events)
--   p_anchor  : any date inside the period (NULL = today)
--   p_search  : when given, the events whose title, location or notes contain every word, a year back and a year ahead
--               of today, as an agenda
--   p_calendar_ids : calendars to include (NULL = every calendar the caller can see)
--   p_production   : include the production runs (production date and delivery date of each run, read-only)
-- Returns { view, today, anchor, from, to, prev, next, title, now_minutes, time_zone,
--           days: [{ date, day, dow, label, in_month, is_today }],
--           events: [{ key, kind, event_id, production_run_id, occurrence_date, calendar_id, color, title, location,
--                      all_day, start_date, end_date, start_time, end_time, time_label, short_label, is_recurring }] }
-- Weeks start on Sunday. Times are wall-clock in the company time zone.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_calendar_view_get(
  p_tenant_id bigint, p_view text, p_anchor date DEFAULT NULL, p_search text DEFAULT NULL,
  p_calendar_ids bigint[] DEFAULT NULL, p_production boolean DEFAULT true)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_tz     text := COALESCE(bps.fnd_tenant_time_zone(p_tenant_id), 'America/New_York');
  v_now    timestamp;
  v_today  date;
  v_view   text := lower(COALESCE(p_view, 'month'));
  v_anchor date;
  v_first  date;
  v_from   date;
  v_to     date;
  v_prev   date;
  v_next   date;
  v_title  text;
  v_words  text[];
  v_events jsonb := '[]'::jsonb;
BEGIN
  PERFORM bps.org_calendar_check(p_tenant_id, 'R');
  v_now    := now() AT TIME ZONE v_tz;
  v_today  := v_now::date;
  v_anchor := COALESCE(p_anchor, v_today);
  v_words  := array_remove(regexp_split_to_array(lower(btrim(COALESCE(p_search, ''))), '\s+'), '');
  IF cardinality(v_words) > 0 THEN v_view := 'search'; END IF;
  IF v_view NOT IN ('day', 'week', 'month', 'agenda', 'mini', 'search') THEN RAISE EXCEPTION 'Unknown calendar view %', p_view; END IF;

  v_first := date_trunc('month', v_anchor)::date;
  CASE v_view
    WHEN 'day' THEN
      v_from := v_anchor; v_to := v_anchor; v_prev := v_anchor - 1; v_next := v_anchor + 1;
      v_title := to_char(v_anchor, 'Dy, FMMon FMDD, YYYY');
    WHEN 'week' THEN
      v_from := v_anchor - extract(dow FROM v_anchor)::int; v_to := v_from + 6; v_prev := v_anchor - 7; v_next := v_anchor + 7;
      v_title := CASE
        WHEN extract(year FROM v_from) <> extract(year FROM v_to) THEN to_char(v_from, 'FMMon FMDD, YYYY') || ' – ' || to_char(v_to, 'FMMon FMDD, YYYY')
        WHEN extract(month FROM v_from) <> extract(month FROM v_to) THEN to_char(v_from, 'FMMon FMDD') || ' – ' || to_char(v_to, 'FMMon FMDD, YYYY')
        ELSE to_char(v_from, 'FMMon FMDD') || ' – ' || to_char(v_to, 'FMDD, YYYY') END;
    WHEN 'agenda' THEN
      v_from := v_anchor; v_to := v_anchor + 29; v_prev := v_anchor - 30; v_next := v_anchor + 30;
      v_title := to_char(v_from, 'FMMon FMDD') || ' – ' || to_char(v_to, 'FMMon FMDD, YYYY');
    WHEN 'search' THEN
      v_from := v_today - 365; v_to := v_today + 365; v_prev := v_anchor; v_next := v_anchor;
      v_title := 'Search results';
    ELSE -- month, mini: whole weeks around the month
      v_from := v_first - extract(dow FROM v_first)::int;
      v_to   := v_from + 7 * ceil((extract(dow FROM v_first)::int + extract(day FROM (v_first + interval '1 month - 1 day'))::int) / 7.0)::int - 1;
      v_prev := (v_anchor - interval '1 month')::date; v_next := (v_anchor + interval '1 month')::date;
      v_title := to_char(v_first, 'FMMonth YYYY');
  END CASE;

  IF v_view <> 'mini' THEN
    WITH occ AS (
      SELECT e.event_id, o.d, e.calendar_id, c.calendar_color, e.title, e.location, e.notes, e.all_day,
             o.d AS sd, o.d + (e.end_date - e.start_date) AS ed, e.start_time, e.end_time, e.repeat_freq <> 'NONE' AS rec
        FROM org_events e
        JOIN org_calendars c ON c.calendar_id = e.calendar_id
        CROSS JOIN LATERAL bps.org_event_occurrences(e, v_from, v_to) o(d)
       WHERE e.tenant_id = p_tenant_id
         AND (p_calendar_ids IS NULL OR e.calendar_id = ANY (p_calendar_ids))
         AND e.start_date <= v_to
         AND (e.repeat_freq <> 'NONE' OR e.end_date >= v_from)
         AND (e.repeat_until IS NULL OR e.repeat_until + (e.end_date - e.start_date) >= v_from)
         AND (cardinality(v_words) = 0 OR (SELECT bool_and(lower(concat_ws(' ', e.title, e.location, e.notes)) LIKE '%' || w || '%')
                                             FROM unnest(v_words) w))
    ), runs AS (
      SELECT r.production_run_id, x.kind, x.d, r.production_code, r.run_status
        FROM om_production_runs r
        CROSS JOIN LATERAL (VALUES ('PRODUCTION', r.production_date), ('DELIVERY', r.delivery_date)) x(kind, d)
       WHERE p_production AND r.tenant_id = p_tenant_id AND x.d BETWEEN v_from AND v_to
    ), items AS (
      SELECT jsonb_build_object(
               'key', o.event_id || ':' || o.d, 'kind', 'EVENT', 'event_id', o.event_id, 'production_run_id', NULL,
               'occurrence_date', o.d, 'calendar_id', o.calendar_id, 'color', o.calendar_color, 'title', o.title,
               'location', o.location, 'all_day', o.all_day, 'start_date', o.sd, 'end_date', o.ed,
               'start_time', to_char(o.start_time, 'HH24:MI'), 'end_time', to_char(o.end_time, 'HH24:MI'),
               'time_label', CASE
                 WHEN o.all_day AND o.ed > o.sd THEN to_char(o.sd, 'FMMM/FMDD') || ' – ' || to_char(o.ed, 'FMMM/FMDD')
                 WHEN o.all_day THEN 'All day'
                 WHEN o.ed > o.sd THEN to_char(o.sd, 'FMMM/FMDD ') || to_char(o.start_time, 'FMHH12:MI AM')
                                       || ' – ' || to_char(o.ed, 'FMMM/FMDD ') || to_char(o.end_time, 'FMHH12:MI AM')
                 WHEN to_char(o.start_time, 'AM') = to_char(o.end_time, 'AM')
                   THEN to_char(o.start_time, 'FMHH12:MI') || ' – ' || to_char(o.end_time, 'FMHH12:MI AM')
                 ELSE to_char(o.start_time, 'FMHH12:MI AM') || ' – ' || to_char(o.end_time, 'FMHH12:MI AM') END,
               'short_label', CASE WHEN o.all_day THEN NULL ELSE replace(to_char(o.start_time, 'FMHH12:MIam'), ':00', '') END,
               'is_recurring', o.rec, 'day_label', to_char(o.sd, 'Dy FMMM/FMDD/YYYY')) AS j,
             o.sd AS sort_d, NOT o.all_day AS sort_a, o.start_time AS sort_t, lower(o.title) AS sort_n
        FROM occ o
      UNION ALL
      SELECT jsonb_build_object(
               'key', r.kind || ':' || r.production_run_id, 'kind', r.kind, 'event_id', NULL,
               'production_run_id', r.production_run_id, 'occurrence_date', r.d, 'calendar_id', NULL, 'color', 'gray',
               'title', CASE r.kind WHEN 'PRODUCTION' THEN 'Production · ' ELSE 'Delivery · ' END || r.production_code,
               'location', NULL, 'all_day', true, 'start_date', r.d, 'end_date', r.d, 'start_time', NULL, 'end_time', NULL,
               'time_label', 'All day', 'short_label', NULL, 'is_recurring', false, 'run_status', r.run_status, 'day_label', to_char(r.d, 'Dy FMMM/FMDD/YYYY')),
             r.d, false, NULL::time, CASE r.kind WHEN 'PRODUCTION' THEN '0' ELSE '1' END || r.production_code
        FROM runs r
       WHERE cardinality(v_words) = 0
          OR (SELECT bool_and(lower(r.kind || ' ' || r.production_code) LIKE '%' || w || '%') FROM unnest(v_words) w)
    )
    SELECT COALESCE(jsonb_agg(j ORDER BY sort_d, sort_a, sort_t NULLS FIRST, sort_n), '[]'::jsonb) INTO v_events FROM items;
  END IF;

  RETURN jsonb_build_object(
    'view', v_view, 'today', v_today, 'anchor', v_anchor, 'from', v_from, 'to', v_to, 'prev', v_prev, 'next', v_next,
    'title', v_title, 'time_zone', v_tz,
    'now_minutes', extract(hour FROM v_now)::int * 60 + extract(minute FROM v_now)::int,
    'days', CASE WHEN v_view = 'search' THEN '[]'::jsonb ELSE (
      SELECT jsonb_agg(jsonb_build_object(
               'date', d::date, 'day', extract(day FROM d)::int, 'dow', extract(dow FROM d)::int,
               'label', to_char(d, 'Dy FMMM/FMDD'), 'in_month', date_trunc('month', d) = v_first, 'is_today', d::date = v_today)
             ORDER BY d)
        FROM generate_series(v_from::timestamp, v_to::timestamp, interval '1 day') d) END,
    'events', v_events);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_calendar_view_get(bigint, text, date, text, bigint[], boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_calendar_view_get(bigint, text, date, text, bigint[], boolean) TO authenticated, service_role, bps_dev;
