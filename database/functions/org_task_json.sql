-- ============================================================
-- org_task_json
-- Internal: one task as the Tasks screen shows it, with the date rules worked out against p_now (tenant local time):
-- due_group / due_label, repeat_label and the next date, list, parent title, assignee, completed label, creator, and
-- for a top-level task its subtasks (open first in manual order, then completed) when p_with_subtasks.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_task_json(p_task bps.org_tasks, p_now timestamp, p_with_subtasks boolean)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'bps', 'public'
AS $function$
BEGIN
  RETURN (SELECT jsonb_build_object(
    'task_id', t.task_id, 'list_id', t.list_id, 'parent_task_id', t.parent_task_id,
    'title', t.title, 'details', t.details,
    'due_date', t.due_date, 'due_time', to_char(t.due_time, 'HH24:MI'),
    'due_group', CASE WHEN t.is_completed THEN 'NONE' ELSE bps.org_task_due_group(t.due_date, t.due_time, p_now) END,
    'due_label', bps.org_task_due_label(t.due_date, t.due_time, p_now::date),
    'is_starred', t.is_starred, 'starred_at', t.starred_at,
    'assigned_user_id', t.assigned_user_id, 'assigned_name', au.user_name,
    'position', t.position,
    'is_completed', t.is_completed, 'completed_at', t.completed_at,
    'completed_label', CASE WHEN t.completed_at IS NULL THEN NULL
                            ELSE 'Completed ' || bps.org_task_due_label((t.completed_at AT TIME ZONE COALESCE(bps.fnd_tenant_time_zone(t.tenant_id), 'America/New_York'))::date, NULL, p_now::date) END,
    'repeat', CASE WHEN t.repeat_unit IS NULL THEN NULL ELSE jsonb_build_object(
                'unit', t.repeat_unit, 'interval', t.repeat_interval, 'weekdays', to_jsonb(t.repeat_weekdays),
                'starts_on', t.repeat_starts_on, 'ends_on', t.repeat_ends_on) END,
    'repeat_label', bps.org_task_repeat_label(t.repeat_unit, t.repeat_interval, t.repeat_weekdays, t.repeat_starts_on, t.repeat_ends_on),
    'next_due_label', CASE WHEN t.repeat_unit IS NULL THEN NULL ELSE
                        bps.org_task_due_label(bps.org_task_next_due(t.due_date, t.repeat_unit, t.repeat_interval, t.repeat_weekdays, t.repeat_starts_on), NULL, p_now::date) END,
    'list_name', l.list_name, 'list_is_shared', l.is_shared,
    'parent_title', (SELECT p.title FROM org_tasks p WHERE p.task_id = t.parent_task_id),
    'subtask_count', (SELECT count(*) FROM org_tasks s WHERE s.parent_task_id = t.task_id AND s.deleted_at IS NULL),
    'subtask_done', (SELECT count(*) FROM org_tasks s WHERE s.parent_task_id = t.task_id AND s.deleted_at IS NULL AND s.is_completed),
    'subtasks', CASE WHEN p_with_subtasks AND t.parent_task_id IS NULL THEN COALESCE((
                  SELECT jsonb_agg(bps.org_task_json(s, p_now, false) ORDER BY s.is_completed, s.position, s.task_id)
                    FROM org_tasks s WHERE s.parent_task_id = t.task_id AND s.deleted_at IS NULL), '[]'::jsonb) ELSE '[]'::jsonb END,
    'created_by_name', cu.user_name,
    'created_label', bps.org_task_due_label((t.created_at AT TIME ZONE COALESCE(bps.fnd_tenant_time_zone(t.tenant_id), 'America/New_York'))::date, NULL, p_now::date))
  FROM (SELECT p_task.*) t
  JOIN org_task_lists l ON l.list_id = t.list_id
  LEFT JOIN fnd_users au ON au.user_id = t.assigned_user_id
  LEFT JOIN fnd_users cu ON cu.user_id = t.created_by);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_task_json(bps.org_tasks, timestamp, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION bps.org_task_json(bps.org_tasks, timestamp, boolean) TO service_role, bps_dev;
