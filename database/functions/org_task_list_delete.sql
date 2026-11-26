-- ============================================================
-- org_task_list_delete
-- Deletes a task list with all its tasks. The default "My Tasks" list cannot be deleted. A shared list can be deleted
-- by its owner or by someone with Tasks delete access. Returns { list_id, task_count } (tasks removed).
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_task_list_delete(p_tenant_id bigint, p_list_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_me bigint := bps.org_task_check(p_tenant_id, 'W');
  v bps.org_task_lists := bps.org_task_list_check(p_tenant_id, p_list_id, 'W');
  n int;
BEGIN
  IF v.is_default THEN RAISE EXCEPTION 'My Tasks cannot be deleted'; END IF;
  IF v.owner_user_id <> v_me AND NOT bps.fnd_has_access('organizer.tasks', 'D') THEN
    RAISE EXCEPTION 'Only % can delete this shared list',
      COALESCE((SELECT user_name FROM fnd_users WHERE user_id = v.owner_user_id), 'its owner') USING ERRCODE = '42501';
  END IF;
  SELECT count(*) INTO n FROM org_tasks WHERE list_id = v.list_id AND deleted_at IS NULL;
  DELETE FROM org_task_lists WHERE list_id = v.list_id;
  RETURN jsonb_build_object('list_id', v.list_id, 'task_count', n);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_task_list_delete(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_task_list_delete(bigint, bigint) TO authenticated, service_role, bps_dev;
