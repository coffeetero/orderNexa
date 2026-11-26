-- ============================================================
-- org_task_list_save
-- Creates or changes a task list. p_list: { list_id?, list_name?, is_shared?, sort_mode? } (keys left out stay as
-- they are). A new list belongs to the caller. Anyone with Tasks write access can rename or re-sort a shared list;
-- only its owner can share or stop sharing it. The default "My Tasks" list cannot be shared.
-- Returns { list_id, list_name, is_shared, is_default, sort_mode }.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_task_list_save(p_tenant_id bigint, p_list jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_me bigint := bps.org_task_check(p_tenant_id, 'W');
  v bps.org_task_lists;
  v_name text := NULLIF(btrim(p_list ->> 'list_name'), '');
  v_sort text := upper(NULLIF(p_list ->> 'sort_mode', ''));
BEGIN
  IF p_list ? 'list_name' AND v_name IS NULL THEN RAISE EXCEPTION 'Give the list a name'; END IF;
  IF length(v_name) > 80 THEN RAISE EXCEPTION 'A list name can be at most 80 characters'; END IF;
  IF v_sort IS NOT NULL AND v_sort NOT IN ('MY_ORDER', 'DATE', 'STARRED') THEN RAISE EXCEPTION 'Unknown sort %', v_sort; END IF;

  IF NULLIF(p_list ->> 'list_id', '') IS NULL THEN
    IF v_name IS NULL THEN RAISE EXCEPTION 'Give the list a name'; END IF;
    INSERT INTO org_task_lists (tenant_id, owner_user_id, list_name, is_shared, sort_mode, created_by, updated_by)
    VALUES (p_tenant_id, v_me, v_name, COALESCE((p_list ->> 'is_shared')::boolean, false), COALESCE(v_sort, 'MY_ORDER'), v_me, v_me)
    RETURNING * INTO v;
  ELSE
    v := bps.org_task_list_check(p_tenant_id, (p_list ->> 'list_id')::bigint, 'W');
    IF p_list ? 'is_shared' AND (p_list ->> 'is_shared')::boolean IS DISTINCT FROM v.is_shared THEN
      IF v.owner_user_id <> v_me THEN RAISE EXCEPTION 'Only % can change who sees this list',
        COALESCE((SELECT user_name FROM fnd_users WHERE user_id = v.owner_user_id), 'its owner'); END IF;
      IF v.is_default THEN RAISE EXCEPTION 'My Tasks is always private; share another list'; END IF;
    END IF;
    UPDATE org_task_lists SET
      list_name = COALESCE(v_name, list_name),
      is_shared = CASE WHEN p_list ? 'is_shared' THEN COALESCE((p_list ->> 'is_shared')::boolean, false) ELSE is_shared END,
      sort_mode = COALESCE(v_sort, sort_mode),
      updated_by = v_me
     WHERE list_id = v.list_id
    RETURNING * INTO v;
  END IF;
  RETURN jsonb_build_object('list_id', v.list_id, 'list_name', v.list_name, 'is_shared', v.is_shared,
                            'is_default', v.is_default, 'sort_mode', v.sort_mode);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_task_list_save(bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_task_list_save(bigint, jsonb) TO authenticated, service_role, bps_dev;
