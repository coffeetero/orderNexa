-- ============================================================
-- org_task_check, org_task_list_check, org_task_row_check
-- Internal access checks for Organizer › Tasks (called only from the SECURITY DEFINER org_task* functions).
-- p_action: 'R' read, 'W' write, 'D' delete (organizer.tasks access).
--   org_task_check      : the tenant is the active one and the caller has the access; returns the caller's user_id.
--   org_task_list_check : the list is the caller's own or shared with the company; returns it.
--   org_task_row_check  : the task (not deleted) is in such a list, or it or its parent is assigned to the caller.
-- Another user's private list is never visible, not even to an administrator: tasks are personal.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_task_check(p_tenant_id bigint, p_action text)
RETURNS bigint
LANGUAGE plpgsql
STABLE
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_me bigint := bps.fnd_current_user_id();
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF v_me IS NULL OR NOT bps.fnd_has_access('organizer.tasks', p_action) THEN
    RAISE EXCEPTION 'You do not have access to % tasks',
      CASE upper(p_action) WHEN 'R' THEN 'view' WHEN 'D' THEN 'delete' ELSE 'edit' END USING ERRCODE = '42501';
  END IF;
  RETURN v_me;
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_task_check(bigint, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION bps.org_task_check(bigint, text) TO service_role, bps_dev;

CREATE OR REPLACE FUNCTION bps.org_task_list_check(p_tenant_id bigint, p_list_id bigint, p_action text)
RETURNS bps.org_task_lists
LANGUAGE plpgsql
STABLE
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_me bigint := bps.org_task_check(p_tenant_id, p_action);
  v bps.org_task_lists;
BEGIN
  SELECT * INTO v FROM org_task_lists l WHERE l.tenant_id = p_tenant_id AND l.list_id = p_list_id;
  IF NOT FOUND OR NOT (v.is_shared OR v.owner_user_id = v_me) THEN
    RAISE EXCEPTION 'List not found';
  END IF;
  RETURN v;
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_task_list_check(bigint, bigint, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION bps.org_task_list_check(bigint, bigint, text) TO service_role, bps_dev;

CREATE OR REPLACE FUNCTION bps.org_task_row_check(p_tenant_id bigint, p_task_id bigint, p_action text)
RETURNS bps.org_tasks
LANGUAGE plpgsql
STABLE
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_me bigint := bps.org_task_check(p_tenant_id, p_action);
  v bps.org_tasks;
BEGIN
  SELECT * INTO v FROM org_tasks t WHERE t.tenant_id = p_tenant_id AND t.task_id = p_task_id AND t.deleted_at IS NULL;
  IF NOT FOUND
     OR NOT (COALESCE(v.assigned_user_id = v_me, false)
             OR EXISTS (SELECT 1 FROM org_task_lists l WHERE l.list_id = v.list_id AND (l.is_shared OR l.owner_user_id = v_me))
             OR EXISTS (SELECT 1 FROM org_tasks p WHERE p.task_id = v.parent_task_id AND p.assigned_user_id = v_me)) THEN
    RAISE EXCEPTION 'Task not found';
  END IF;
  RETURN v;
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_task_row_check(bigint, bigint, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION bps.org_task_row_check(bigint, bigint, text) TO service_role, bps_dev;
