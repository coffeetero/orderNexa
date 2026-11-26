-- ============================================================
-- org_task_complete
-- Marks a task done (p_done true) or not done.
-- Done: a main task also ticks its open subtasks. A repeating main task creates its next occurrence: the next date
-- after its date by the repeat rule, moved on to today or later when the task was done late (no backlog of past
-- copies); same list, title, details, time, star, assignee and repeat, at the same place in the list, with fresh
-- (open) copies of its subtasks. The series ends when the next date is after repeat_ends_on. The completed task keeps
-- no repeat rule, so marking it not done again does not repeat twice.
-- Not done: a subtask of a completed main task reopens the main task too.
-- Returns { task_id, is_completed, next_task_id, next_due_label }.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_task_complete(p_tenant_id bigint, p_task_id bigint, p_done boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_me bigint := bps.org_task_check(p_tenant_id, 'W');
  v bps.org_tasks := bps.org_task_row_check(p_tenant_id, p_task_id, 'W');
  v_now timestamp := bps.org_task_now(p_tenant_id);
  v_next date;
  v_new bigint;
BEGIN
  IF COALESCE(p_done, false) THEN
    IF v.is_completed THEN RETURN jsonb_build_object('task_id', v.task_id, 'is_completed', true); END IF;
    UPDATE org_tasks SET is_completed = true, completed_at = now(), completed_by = v_me, updated_by = v_me,
                         repeat_unit = NULL, repeat_interval = NULL, repeat_weekdays = NULL, repeat_starts_on = NULL, repeat_ends_on = NULL
     WHERE task_id = v.task_id;
    IF v.parent_task_id IS NULL THEN
      UPDATE org_tasks SET is_completed = true, completed_at = now(), completed_by = v_me, updated_by = v_me
       WHERE parent_task_id = v.task_id AND NOT is_completed AND deleted_at IS NULL;
    END IF;

    IF v.repeat_unit IS NOT NULL AND v.parent_task_id IS NULL THEN
      v_next := bps.org_task_next_due(v.due_date, v.repeat_unit, v.repeat_interval, v.repeat_weekdays, v.repeat_starts_on);
      WHILE v_next < v_now::date LOOP
        v_next := bps.org_task_next_due(v_next, v.repeat_unit, v.repeat_interval, v.repeat_weekdays, v.repeat_starts_on);
      END LOOP;
      IF v.repeat_ends_on IS NULL OR v_next <= v.repeat_ends_on THEN
        INSERT INTO org_tasks (tenant_id, list_id, title, details, due_date, due_time, is_starred, starred_at, assigned_user_id, position,
                               repeat_unit, repeat_interval, repeat_weekdays, repeat_starts_on, repeat_ends_on, created_by, updated_by)
        VALUES (v.tenant_id, v.list_id, v.title, v.details, v_next, v.due_time, v.is_starred, v.starred_at, v.assigned_user_id, v.position,
                v.repeat_unit, v.repeat_interval, v.repeat_weekdays, v.repeat_starts_on, v.repeat_ends_on, v_me, v_me)
        RETURNING task_id INTO v_new;
        INSERT INTO org_tasks (tenant_id, list_id, parent_task_id, title, details, is_starred, starred_at, assigned_user_id, position, created_by, updated_by)
        SELECT s.tenant_id, s.list_id, v_new, s.title, s.details, s.is_starred, s.starred_at, s.assigned_user_id, s.position, v_me, v_me
          FROM org_tasks s WHERE s.parent_task_id = v.task_id AND s.deleted_at IS NULL;
      END IF;
    END IF;
    RETURN jsonb_build_object('task_id', v.task_id, 'is_completed', true, 'next_task_id', v_new,
                              'next_due_label', CASE WHEN v_new IS NOT NULL THEN bps.org_task_due_label(v_next, v.due_time, v_now::date) END);
  END IF;

  UPDATE org_tasks SET is_completed = false, completed_at = NULL, completed_by = NULL, updated_by = v_me WHERE task_id = v.task_id;
  IF v.parent_task_id IS NOT NULL THEN
    UPDATE org_tasks SET is_completed = false, completed_at = NULL, completed_by = NULL, updated_by = v_me
     WHERE task_id = v.parent_task_id AND is_completed;
  END IF;
  RETURN jsonb_build_object('task_id', v.task_id, 'is_completed', false);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_task_complete(bigint, bigint, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_task_complete(bigint, bigint, boolean) TO authenticated, service_role, bps_dev;
