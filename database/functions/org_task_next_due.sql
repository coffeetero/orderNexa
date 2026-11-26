-- ============================================================
-- org_task_next_due
-- The next date of a repeating task strictly after p_due.
--   DAY   : every p_interval days.
--   WEEK  : every p_interval weeks on p_weekdays (ISO 1 = Mon .. 7 = Sun; NULL = the weekday of p_starts_on), counting
--           weeks from the week of p_starts_on.
--   MONTH : every p_interval months on the day of p_starts_on (a 31st falls on a shorter month's last day, then
--           returns to the 31st); YEAR likewise every 12 * p_interval months.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_task_next_due(p_due date, p_unit text, p_interval integer, p_weekdays smallint[], p_starts_on date)
RETURNS date
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  n int := GREATEST(COALESCE(p_interval, 1), 1);
  s date := COALESCE(p_starts_on, p_due);
  d date;
  wd smallint[];
  wk date;
  k int;
BEGIN
  IF p_due IS NULL OR p_unit IS NULL THEN RETURN NULL; END IF;
  IF p_unit = 'DAY' THEN
    RETURN p_due + n;
  ELSIF p_unit = 'WEEK' THEN
    wd := COALESCE(NULLIF(p_weekdays, '{}'), ARRAY[extract(isodow FROM s)::smallint]);
    wk := s - (extract(isodow FROM s)::int - 1);              -- Monday of the series' first week
    FOR i IN 1 .. 7 * n + 7 LOOP
      d := p_due + i;
      IF extract(isodow FROM d)::smallint = ANY (wd) AND (((d - wk) / 7) % n) = 0 THEN RETURN d; END IF;
    END LOOP;
    RETURN p_due + 7 * n;
  ELSIF p_unit IN ('MONTH', 'YEAR') THEN
    IF p_unit = 'YEAR' THEN n := n * 12; END IF;
    k := (extract(year FROM p_due)::int * 12 + extract(month FROM p_due)::int) - (extract(year FROM s)::int * 12 + extract(month FROM s)::int);
    k := GREATEST(k - (k % n), 0);                            -- the occurrence at or before p_due
    LOOP
      d := (s + make_interval(months => k))::date;
      EXIT WHEN d > p_due;
      k := k + n;
    END LOOP;
    RETURN d;
  END IF;
  RAISE EXCEPTION 'Unknown repeat unit %', p_unit;
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_task_next_due(date, text, integer, smallint[], date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_task_next_due(date, text, integer, smallint[], date) TO authenticated, service_role, bps_dev;
