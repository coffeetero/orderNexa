-- ============================================================
-- org_task_lists_get
-- The left rail of Organizer › Tasks: the caller's lists (creating their default "My Tasks" on first open) and the
-- company's shared lists, each with open and overdue counts; counts for the Upcoming (due today or overdue), Starred
-- and Assigned to me views; and the active staff users a task can be assigned to.
-- Returns { me, lists: [...], views: { due_now, overdue, starred, assigned }, users: [{ user_id, user_name }] }.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_task_lists_get(p_tenant_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_me bigint := bps.org_task_check(p_tenant_id, 'R');
  v_now timestamp := bps.org_task_now(p_tenant_id);
BEGIN
  INSERT INTO org_task_lists (tenant_id, owner_user_id, list_name, is_default, created_by, updated_by)
  SELECT p_tenant_id, v_me, 'My Tasks', true, v_me, v_me
   WHERE NOT EXISTS (SELECT 1 FROM org_task_lists l WHERE l.tenant_id = p_tenant_id AND l.owner_user_id = v_me AND l.is_default);

  RETURN (
    WITH vis AS (   -- open tasks the caller can see, with their date group
      SELECT t.*, bps.org_task_due_group(t.due_date, t.due_time, v_now) AS g
        FROM org_tasks t
        JOIN org_task_lists l ON l.list_id = t.list_id
        LEFT JOIN org_tasks p ON p.task_id = t.parent_task_id
       WHERE t.tenant_id = p_tenant_id AND t.deleted_at IS NULL AND NOT t.is_completed
         AND (p.task_id IS NULL OR (NOT p.is_completed AND p.deleted_at IS NULL))
         AND (l.is_shared OR l.owner_user_id = v_me OR t.assigned_user_id = v_me OR p.assigned_user_id = v_me)
    )
    SELECT jsonb_build_object(
      'me', v_me,
      'lists', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
                 'list_id', l.list_id, 'list_name', l.list_name, 'is_shared', l.is_shared, 'is_default', l.is_default,
                 'is_mine', l.owner_user_id = v_me, 'owner_name', u.user_name, 'sort_mode', l.sort_mode,
                 'open_count', (SELECT count(*) FROM vis WHERE vis.list_id = l.list_id AND vis.parent_task_id IS NULL),
                 'overdue_count', (SELECT count(*) FROM vis WHERE vis.list_id = l.list_id AND vis.g = 'OVERDUE'))
               ORDER BY l.is_shared, l.is_default DESC, lower(l.list_name), l.list_id)
          FROM org_task_lists l LEFT JOIN fnd_users u ON u.user_id = l.owner_user_id
         WHERE l.tenant_id = p_tenant_id AND (l.is_shared OR l.owner_user_id = v_me)), '[]'::jsonb),
      'views', jsonb_build_object(
        'due_now', (SELECT count(*) FROM vis WHERE vis.g IN ('OVERDUE', 'TODAY')),
        'overdue', (SELECT count(*) FROM vis WHERE vis.g = 'OVERDUE'),
        'starred', (SELECT count(*) FROM vis WHERE vis.is_starred),
        'assigned', (SELECT count(*) FROM vis WHERE vis.assigned_user_id = v_me)),
      'users', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('user_id', u.user_id, 'user_name', COALESCE(u.user_name, u.email)) ORDER BY lower(COALESCE(u.user_name, u.email)))
          FROM fnd_user_tenants ut JOIN fnd_users u ON u.user_id = ut.user_id
         WHERE ut.tenant_id = p_tenant_id AND ut.is_active AND u.is_active AND u.deleted_at IS NULL
           AND u.user_type = 'TENANCY_USER'), '[]'::jsonb)));
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_task_lists_get(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_task_lists_get(bigint) TO authenticated, service_role, bps_dev;
