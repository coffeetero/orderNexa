-- ============================================================
-- org_event_occurrences
-- The start dates of an event's occurrences that touch p_from..p_to (an occurrence lasts end_date - start_date days).
-- Repeats: DAILY every n days; WEEKLY on repeat_days (ISO 1 Mon .. 7 Sun; default the start weekday) every n weeks
-- (weeks start on Sunday); MONTHLY on the start day of the month every n months (months without that day are skipped);
-- YEARLY on the start month and day every n years (Feb 29 only in leap years). The series ends at repeat_until or after
-- repeat_count occurrences (removed occurrences still count, as in iCalendar). Removed occurrences
-- (org_event_exceptions) are left out.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_event_occurrences(p_event bps.org_events, p_from date, p_to date)
RETURNS SETOF date
LANGUAGE sql
STABLE
SET search_path TO 'bps', 'public'
AS $function$
  WITH lim AS (
    SELECT LEAST(p_to, COALESCE(p_event.repeat_until, p_to)) AS hi,
           p_event.end_date - p_event.start_date AS len,
           CASE p_event.repeat_freq WHEN 'YEARLY' THEN 12 ELSE 1 END * p_event.repeat_interval AS months
  ), cand AS (
    SELECT p_event.start_date AS d WHERE p_event.repeat_freq = 'NONE'
    UNION ALL
    SELECT g::date FROM lim, generate_series(p_event.start_date::timestamp, lim.hi::timestamp, make_interval(days => p_event.repeat_interval)) g
     WHERE p_event.repeat_freq = 'DAILY'
    UNION ALL
    SELECT g::date FROM lim, generate_series(p_event.start_date::timestamp, lim.hi::timestamp, interval '1 day') g
     WHERE p_event.repeat_freq = 'WEEKLY'
       AND extract(isodow FROM g)::smallint = ANY (COALESCE(p_event.repeat_days, ARRAY[extract(isodow FROM p_event.start_date)::smallint]))
       AND (((g::date - extract(dow FROM g)::int) - (p_event.start_date - extract(dow FROM p_event.start_date)::int)) / 7)
           % p_event.repeat_interval = 0
    UNION ALL
    SELECT m.d FROM lim, LATERAL (
             SELECT (p_event.start_date + make_interval(months => k * lim.months))::date AS d
               FROM generate_series(0, ((extract(year FROM lim.hi) * 12 + extract(month FROM lim.hi))
                                       - (extract(year FROM p_event.start_date) * 12 + extract(month FROM p_event.start_date)))::int
                                       / lim.months) k) m
     WHERE p_event.repeat_freq IN ('MONTHLY', 'YEARLY')
       AND extract(day FROM m.d) = extract(day FROM p_event.start_date)
  ), numbered AS (
    SELECT d, row_number() OVER (ORDER BY d) AS n FROM cand
  )
  SELECT n.d
    FROM numbered n, lim
   WHERE (p_event.repeat_count IS NULL OR p_event.repeat_freq = 'NONE' OR n.n <= p_event.repeat_count)
     AND n.d <= p_to AND n.d + lim.len >= p_from
     AND NOT EXISTS (SELECT 1 FROM bps.org_event_exceptions x WHERE x.event_id = p_event.event_id AND x.occurrence_date = n.d)
   ORDER BY n.d
$function$;
REVOKE EXECUTE ON FUNCTION bps.org_event_occurrences(bps.org_events, date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_event_occurrences(bps.org_events, date, date) TO authenticated, service_role, bps_dev;
