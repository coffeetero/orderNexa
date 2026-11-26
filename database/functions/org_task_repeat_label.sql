-- ============================================================
-- org_task_repeat_label
-- Plain-words repeat rule: "Daily", "Every 2 weeks on Mon, Thu", "Monthly on day 31", "Yearly on Nov 26",
-- with ", until Dec 31, 2026" when it ends. NULL when the task does not repeat.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_task_repeat_label(p_unit text, p_interval integer, p_weekdays smallint[], p_starts_on date, p_ends_on date)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO 'bps', 'public'
AS $function$
  SELECT CASE WHEN p_unit IS NULL THEN NULL ELSE
    CASE WHEN COALESCE(p_interval, 1) = 1
         THEN CASE p_unit WHEN 'DAY' THEN 'Daily' WHEN 'WEEK' THEN 'Weekly' WHEN 'MONTH' THEN 'Monthly' ELSE 'Yearly' END
         ELSE 'Every ' || p_interval || ' ' || CASE p_unit WHEN 'DAY' THEN 'days' WHEN 'WEEK' THEN 'weeks' WHEN 'MONTH' THEN 'months' ELSE 'years' END
    END
    || CASE p_unit
         WHEN 'WEEK' THEN ' on ' || (SELECT string_agg((ARRAY['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])[w], ', ' ORDER BY w)
                                       FROM unnest(COALESCE(NULLIF(p_weekdays, '{}'), ARRAY[extract(isodow FROM p_starts_on)::smallint])) w)
         WHEN 'MONTH' THEN ' on day ' || extract(day FROM p_starts_on)
         WHEN 'YEAR' THEN ' on ' || to_char(p_starts_on, 'Mon FMDD')
         ELSE '' END
    || COALESCE(', until ' || to_char(p_ends_on, 'Mon FMDD, YYYY'), '') END
$function$;
REVOKE EXECUTE ON FUNCTION bps.org_task_repeat_label(text, integer, smallint[], date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_task_repeat_label(text, integer, smallint[], date, date) TO authenticated, service_role, bps_dev;
