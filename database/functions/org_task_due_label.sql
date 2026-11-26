-- ============================================================
-- org_task_due_label
-- How Tasks shows a date: Yesterday / Today / Tomorrow, else "Mon, Nov 30" this year or "Nov 30, 2027" another year;
-- with ", 10:00 AM" when a time is set. NULL without a date.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_task_due_label(p_date date, p_time time, p_today date)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO 'bps', 'public'
AS $function$
  SELECT CASE WHEN p_date IS NULL THEN NULL ELSE
    CASE p_date - p_today
      WHEN -1 THEN 'Yesterday' WHEN 0 THEN 'Today' WHEN 1 THEN 'Tomorrow'
      ELSE CASE WHEN extract(year FROM p_date) = extract(year FROM p_today) THEN to_char(p_date, 'Dy, Mon FMDD')
                ELSE to_char(p_date, 'Mon FMDD, YYYY') END
    END || COALESCE(', ' || to_char(p_time, 'FMHH12:MI AM'), '') END
$function$;
REVOKE EXECUTE ON FUNCTION bps.org_task_due_label(date, time, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_task_due_label(date, time, date) TO authenticated, service_role, bps_dev;
