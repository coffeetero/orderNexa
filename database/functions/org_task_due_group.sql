-- ============================================================
-- org_task_due_group
-- Where an open task falls by its due date, against the tenant's local date and time (p_now):
--   OVERDUE (an earlier day, or today with a time already passed) | TODAY | TOMORROW | NEXT_7_DAYS | LATER | NONE.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_task_due_group(p_due_date date, p_due_time time, p_now timestamp)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO 'bps', 'public'
AS $function$
  SELECT CASE
    WHEN p_due_date IS NULL THEN 'NONE'
    WHEN p_due_date < p_now::date OR (p_due_date = p_now::date AND p_due_time IS NOT NULL AND p_due_time < p_now::time) THEN 'OVERDUE'
    WHEN p_due_date = p_now::date THEN 'TODAY'
    WHEN p_due_date = p_now::date + 1 THEN 'TOMORROW'
    WHEN p_due_date <= p_now::date + 7 THEN 'NEXT_7_DAYS'
    ELSE 'LATER' END
$function$;
REVOKE EXECUTE ON FUNCTION bps.org_task_due_group(date, time, timestamp) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_task_due_group(date, time, timestamp) TO authenticated, service_role, bps_dev;
