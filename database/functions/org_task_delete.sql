-- ============================================================
-- org_task_delete
-- Deletes a task with its subtasks (p_restore false), or brings them back (p_restore true) for the screen's Undo.
-- Deleting only marks the rows (deleted_at); a restore brings back the rows deleted together with the task.
-- Returns { task_id, deleted: true | false }.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_task_delete(p_tenant_id bigint, p_task_id bigint, p_restore boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_me bigint := bps.org_task_check(p_tenant_id, 'W');
  v bps.org_tasks;
  v_at timestamptz;
BEGIN
  IF COALESCE(p_restore, false) THEN
    SELECT * INTO v FROM org_tasks t WHERE t.tenant_id = p_tenant_id AND t.task_id = p_task_id AND t.deleted_at IS NOT NULL;
    IF NOT FOUND THEN RAISE EXCEPTION 'Task not found'; END IF;
    v_at := v.deleted_at;
    UPDATE org_tasks SET deleted_at = NULL, updated_by = v_me WHERE task_id = v.task_id;
    BEGIN
      PERFORM bps.org_task_row_check(p_tenant_id, v.task_id, 'W');   -- the caller must be able to see it
    EXCEPTION WHEN OTHERS THEN
      UPDATE org_tasks SET deleted_at = v_at WHERE task_id = v.task_id;
      RAISE;
    END;
    IF v.parent_task_id IS NOT NULL AND EXISTS (SELECT 1 FROM org_tasks p WHERE p.task_id = v.parent_task_id AND p.deleted_at IS NOT NULL) THEN
      UPDATE org_tasks SET deleted_at = v_at WHERE task_id = v.task_id;
      RAISE EXCEPTION 'Its main task was deleted too; restore that first';
    END IF;
    UPDATE org_tasks SET deleted_at = NULL, updated_by = v_me WHERE parent_task_id = v.task_id AND deleted_at = v_at;
    RETURN jsonb_build_object('task_id', v.task_id, 'deleted', false);
  END IF;

  v := bps.org_task_row_check(p_tenant_id, p_task_id, 'W');
  UPDATE org_tasks SET deleted_at = now(), updated_by = v_me
   WHERE (task_id = v.task_id OR parent_task_id = v.task_id) AND deleted_at IS NULL;
  RETURN jsonb_build_object('task_id', v.task_id, 'deleted', true);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_task_delete(bigint, bigint, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_task_delete(bigint, bigint, boolean) TO authenticated, service_role, bps_dev;
