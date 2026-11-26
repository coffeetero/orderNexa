-- ============================================================
-- org_task_move
-- Reorders an open task (drag and drop, Alt+Up/Down, Tab / Shift+Tab): puts it at p_index (0 = first) among the open
-- tasks under p_parent_task_id (NULL = the list's main tasks) and renumbers that group. Giving a parent makes it a
-- subtask (indent); NULL makes a subtask a main task (outdent). One level only: a task that has subtasks, or that
-- repeats, cannot become a subtask. The parent must be an open main task in the same list.
-- Returns { task_id, parent_task_id, position }.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_task_move(p_tenant_id bigint, p_task_id bigint, p_parent_task_id bigint, p_index integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_me bigint := bps.org_task_check(p_tenant_id, 'W');
  v bps.org_tasks := bps.org_task_row_check(p_tenant_id, p_task_id, 'W');
  p bps.org_tasks;
BEGIN
  IF v.is_completed THEN RAISE EXCEPTION 'Completed tasks cannot be moved; mark it not done first'; END IF;
  IF p_parent_task_id IS NOT NULL THEN
    p := bps.org_task_row_check(p_tenant_id, p_parent_task_id, 'W');
    IF p.task_id = v.task_id OR p.parent_task_id IS NOT NULL OR p.list_id <> v.list_id OR p.is_completed THEN
      RAISE EXCEPTION 'A task can only go under an open main task of the same list';
    END IF;
    IF EXISTS (SELECT 1 FROM org_tasks s WHERE s.parent_task_id = v.task_id AND s.deleted_at IS NULL) THEN
      RAISE EXCEPTION 'This task has subtasks, so it cannot become a subtask';
    END IF;
    IF v.repeat_unit IS NOT NULL THEN RAISE EXCEPTION 'A repeating task cannot become a subtask'; END IF;
  END IF;

  PERFORM 1 FROM org_task_lists WHERE list_id = v.list_id FOR UPDATE;   -- one reorder at a time per list
  WITH sib AS (
    SELECT s.task_id, row_number() OVER (ORDER BY s.position, s.task_id) - 1 AS rn
      FROM org_tasks s
     WHERE s.list_id = v.list_id AND s.parent_task_id IS NOT DISTINCT FROM p_parent_task_id
       AND NOT s.is_completed AND s.deleted_at IS NULL AND s.task_id <> v.task_id
  ), k AS (SELECT LEAST(GREATEST(COALESCE(p_index, 0), 0), (SELECT count(*) FROM sib)) AS idx)
  UPDATE org_tasks t SET position = CASE WHEN sib.rn < k.idx THEN sib.rn ELSE sib.rn + 1 END, updated_by = v_me
    FROM sib, k WHERE t.task_id = sib.task_id AND t.position IS DISTINCT FROM CASE WHEN sib.rn < k.idx THEN sib.rn ELSE sib.rn + 1 END;

  UPDATE org_tasks SET parent_task_id = p_parent_task_id, updated_by = v_me,
         position = LEAST(GREATEST(COALESCE(p_index, 0), 0),
                          (SELECT count(*) FROM org_tasks s WHERE s.list_id = v.list_id AND s.parent_task_id IS NOT DISTINCT FROM p_parent_task_id
                              AND NOT s.is_completed AND s.deleted_at IS NULL AND s.task_id <> v.task_id))
   WHERE task_id = v.task_id
  RETURNING * INTO v;
  RETURN jsonb_build_object('task_id', v.task_id, 'parent_task_id', v.parent_task_id, 'position', v.position);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_task_move(bigint, bigint, bigint, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_task_move(bigint, bigint, bigint, integer) TO authenticated, service_role, bps_dev;
