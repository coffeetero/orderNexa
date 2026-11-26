-- ============================================================
-- org_tasks_get
-- The task list of Organizer › Tasks for one view (each task as org_task_json):
--   LIST     (p_list_id): open top-level tasks with their subtasks, in the list's sort (MY_ORDER: manual; DATE: by due
--            date and time, undated last; STARRED: starred first, most recently starred first), and the 200 most
--            recently completed top-level tasks.
--   UPCOMING : open tasks and subtasks with a date in the lists the caller sees or assigned to them, by date.
--   STARRED  : open starred tasks and subtasks, most recently starred first.
--   ASSIGNED : open tasks and subtasks assigned to the caller, by date (undated last).
--   (the views carry each main task's subtasks too, for the details pane)
-- Returns { view, list: {...} | null, tasks: [...], completed: [...] }.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_tasks_get(p_tenant_id bigint, p_view text, p_list_id bigint DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_me bigint := bps.org_task_check(p_tenant_id, 'R');
  v_now timestamp := bps.org_task_now(p_tenant_id);
  v_view text := upper(COALESCE(p_view, 'LIST'));
  l bps.org_task_lists;
BEGIN
  IF v_view = 'LIST' THEN
    l := bps.org_task_list_check(p_tenant_id, p_list_id, 'R');
    RETURN jsonb_build_object(
      'view', v_view,
      'list', jsonb_build_object('list_id', l.list_id, 'list_name', l.list_name, 'is_shared', l.is_shared,
                                 'is_default', l.is_default, 'is_mine', l.owner_user_id = v_me, 'sort_mode', l.sort_mode,
                                 'owner_name', (SELECT user_name FROM fnd_users WHERE user_id = l.owner_user_id)),
      'tasks', COALESCE((
        SELECT jsonb_agg(bps.org_task_json(t, v_now, true) ORDER BY
                 CASE WHEN l.sort_mode = 'STARRED' THEN NOT t.is_starred END,
                 CASE WHEN l.sort_mode = 'STARRED' THEN t.starred_at END DESC NULLS LAST,
                 CASE WHEN l.sort_mode = 'DATE' THEN t.due_date END NULLS LAST,
                 CASE WHEN l.sort_mode = 'DATE' THEN t.due_time END NULLS FIRST,
                 t.position, t.task_id)
          FROM org_tasks t
         WHERE t.list_id = l.list_id AND t.parent_task_id IS NULL AND NOT t.is_completed AND t.deleted_at IS NULL), '[]'::jsonb),
      'completed', COALESCE((
        SELECT jsonb_agg(bps.org_task_json(c, v_now, true) ORDER BY c.completed_at DESC, c.task_id DESC)
          FROM (SELECT * FROM org_tasks t
                 WHERE t.list_id = l.list_id AND t.parent_task_id IS NULL AND t.is_completed AND t.deleted_at IS NULL
                 ORDER BY t.completed_at DESC LIMIT 200) c), '[]'::jsonb));
  ELSIF v_view IN ('UPCOMING', 'STARRED', 'ASSIGNED') THEN
    RETURN jsonb_build_object(
      'view', v_view, 'list', NULL, 'completed', '[]'::jsonb,
      'tasks', COALESCE((
        SELECT jsonb_agg(bps.org_task_json(t, v_now, true) ORDER BY
                 CASE WHEN v_view = 'STARRED' THEN t.starred_at END DESC NULLS LAST,
                 t.due_date NULLS LAST, t.due_time NULLS FIRST, t.position, t.task_id)
          FROM org_tasks t
          JOIN org_task_lists tl ON tl.list_id = t.list_id
          LEFT JOIN org_tasks p ON p.task_id = t.parent_task_id
         WHERE t.tenant_id = p_tenant_id AND NOT t.is_completed AND t.deleted_at IS NULL
           AND (p.task_id IS NULL OR (NOT p.is_completed AND p.deleted_at IS NULL))
           AND (tl.is_shared OR tl.owner_user_id = v_me OR t.assigned_user_id = v_me OR p.assigned_user_id = v_me)
           AND CASE v_view WHEN 'UPCOMING' THEN t.due_date IS NOT NULL
                           WHEN 'STARRED'  THEN t.is_starred
                           ELSE t.assigned_user_id = v_me END), '[]'::jsonb));
  END IF;
  RAISE EXCEPTION 'Unknown view %', p_view;
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_tasks_get(bigint, text, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_tasks_get(bigint, text, bigint) TO authenticated, service_role, bps_dev;
