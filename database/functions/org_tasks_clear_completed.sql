-- ============================================================
-- org_tasks_clear_completed
-- "Delete completed tasks" in a list's menu: deletes the list's completed main tasks with their subtasks.
-- Returns { list_id, task_count } (main tasks removed).
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_tasks_clear_completed(p_tenant_id bigint, p_list_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_me bigint := bps.org_task_check(p_tenant_id, 'W');
  l bps.org_task_lists := bps.org_task_list_check(p_tenant_id, p_list_id, 'W');
  n int;
BEGIN
  WITH done AS (
    UPDATE org_tasks SET deleted_at = now(), updated_by = v_me
     WHERE list_id = l.list_id AND parent_task_id IS NULL AND is_completed AND deleted_at IS NULL
    RETURNING task_id)
  SELECT count(*) INTO n FROM done;
  UPDATE org_tasks s SET deleted_at = p.deleted_at, updated_by = v_me
    FROM org_tasks p
   WHERE s.parent_task_id = p.task_id AND p.list_id = l.list_id AND p.deleted_at IS NOT NULL AND s.deleted_at IS NULL;
  RETURN jsonb_build_object('list_id', l.list_id, 'task_count', n);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_tasks_clear_completed(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_tasks_clear_completed(bigint, bigint) TO authenticated, service_role, bps_dev;
