-- ============================================================
-- org_task_save
-- Creates or changes a task. Only the keys sent are changed, so the screen can save one field at a time.
-- p_task: { task_id?, list_id?, parent_task_id? (create only), title, details, due_date ('YYYY-MM-DD' | null),
--           due_time ('HH:MM' | null), is_starred, assigned_user_id, repeat: null | { unit: DAY|WEEK|MONTH|YEAR,
--           interval, weekdays: [1..7] (WEEK), ends_on } }
-- Rules: a new task goes to the top of its list (a new subtask to the bottom of its parent), in the caller's My Tasks
-- when no list is given; one level of subtasks; subtasks do not repeat; a repeating task needs a date (today when
-- none) and a weekly one starts on its first chosen weekday; changing a repeating task's date restarts the series
-- there; moving a task to another list takes its subtasks along; the assignee must be an active staff user.
-- Returns the task (org_task_json, with subtasks).
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_task_save(p_tenant_id bigint, p_task jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_me bigint := bps.org_task_check(p_tenant_id, 'W');
  v_now timestamp := bps.org_task_now(p_tenant_id);
  v_new boolean := NULLIF(p_task ->> 'task_id', '') IS NULL;
  v bps.org_tasks;
  p bps.org_tasks;
  r jsonb := p_task -> 'repeat';
  v_list bigint;
  v_wd smallint[];
BEGIN
  IF v_new THEN
    v.tenant_id := p_tenant_id;
    IF NULLIF(p_task ->> 'parent_task_id', '') IS NOT NULL THEN
      p := bps.org_task_row_check(p_tenant_id, (p_task ->> 'parent_task_id')::bigint, 'W');
      IF p.parent_task_id IS NOT NULL THEN RAISE EXCEPTION 'A subtask cannot have subtasks of its own'; END IF;
      v.parent_task_id := p.task_id;
      v.list_id := p.list_id;
      PERFORM 1 FROM org_task_lists WHERE list_id = v.list_id FOR UPDATE;   -- one position at a time per list
      v.position := COALESCE((SELECT max(s.position) + 1 FROM org_tasks s WHERE s.parent_task_id = p.task_id AND s.deleted_at IS NULL), 0);
    ELSE
      v.list_id := COALESCE((SELECT (bps.org_task_list_check(p_tenant_id, (p_task ->> 'list_id')::bigint, 'W')).list_id
                              WHERE NULLIF(p_task ->> 'list_id', '') IS NOT NULL),
                            (SELECT l.list_id FROM org_task_lists l WHERE l.tenant_id = p_tenant_id AND l.owner_user_id = v_me AND l.is_default));
      IF v.list_id IS NULL THEN RAISE EXCEPTION 'Choose a list for the task'; END IF;
      PERFORM 1 FROM org_task_lists WHERE list_id = v.list_id FOR UPDATE;   -- one position at a time per list
      v.position := COALESCE((SELECT min(s.position) - 1 FROM org_tasks s
                               WHERE s.list_id = v.list_id AND s.parent_task_id IS NULL AND NOT s.is_completed AND s.deleted_at IS NULL), 0);
    END IF;
    v.task_id := nextval('bps.fnd_entity_id_seq');
    v.is_starred := false;
    v.is_completed := false;
    v.created_at := now();
    v.updated_at := now();
    v.created_by := v_me;
    IF NOT p_task ? 'title' THEN RAISE EXCEPTION 'Give the task a title'; END IF;
  ELSE
    v := bps.org_task_row_check(p_tenant_id, (p_task ->> 'task_id')::bigint, 'W');
    -- move to another list (top-level tasks only; subtasks follow)
    IF NULLIF(p_task ->> 'list_id', '') IS NOT NULL AND (p_task ->> 'list_id')::bigint <> v.list_id THEN
      IF v.parent_task_id IS NOT NULL THEN RAISE EXCEPTION 'Move the main task; its subtasks go with it'; END IF;
      PERFORM bps.org_task_list_check(p_tenant_id, v.list_id, 'W');
      v_list := (bps.org_task_list_check(p_tenant_id, (p_task ->> 'list_id')::bigint, 'W')).list_id;
      PERFORM 1 FROM org_task_lists WHERE list_id = v_list FOR UPDATE;   -- one position at a time per list
      v.position := COALESCE((SELECT min(s.position) - 1 FROM org_tasks s
                               WHERE s.list_id = v_list AND s.parent_task_id IS NULL AND NOT s.is_completed AND s.deleted_at IS NULL), 0);
      v.list_id := v_list;
    END IF;
  END IF;

  IF p_task ? 'title' THEN
    v.title := NULLIF(btrim(regexp_replace(p_task ->> 'title', '\s+', ' ', 'g')), '');
    IF v.title IS NULL THEN RAISE EXCEPTION 'Give the task a title'; END IF;
    IF length(v.title) > 500 THEN RAISE EXCEPTION 'A task title can be at most 500 characters'; END IF;
  END IF;
  IF p_task ? 'details' THEN
    v.details := NULLIF(btrim(p_task ->> 'details'), '');
    IF length(v.details) > 8000 THEN RAISE EXCEPTION 'Details can be at most 8,000 characters'; END IF;
  END IF;
  IF p_task ? 'due_date' THEN v.due_date := NULLIF(p_task ->> 'due_date', '')::date; END IF;
  IF p_task ? 'due_time' THEN v.due_time := NULLIF(p_task ->> 'due_time', '')::time; END IF;
  IF p_task ? 'is_starred' THEN
    IF COALESCE((p_task ->> 'is_starred')::boolean, false) THEN
      IF NOT v.is_starred THEN v.starred_at := now(); END IF;
      v.is_starred := true;
    ELSE
      v.is_starred := false;
      v.starred_at := NULL;
    END IF;
  END IF;
  IF p_task ? 'assigned_user_id' THEN
    v.assigned_user_id := NULLIF(p_task ->> 'assigned_user_id', '')::bigint;
    IF v.assigned_user_id IS NOT NULL AND NOT EXISTS (
         SELECT 1 FROM fnd_user_tenants ut JOIN fnd_users u ON u.user_id = ut.user_id
          WHERE ut.tenant_id = p_tenant_id AND ut.user_id = v.assigned_user_id AND ut.is_active AND u.is_active
            AND u.deleted_at IS NULL AND u.user_type = 'TENANCY_USER') THEN
      RAISE EXCEPTION 'Tasks can be assigned only to active staff users';
    END IF;
  END IF;

  IF p_task ? 'repeat' THEN
    IF r IS NULL OR jsonb_typeof(r) = 'null' THEN
      v.repeat_unit := NULL; v.repeat_interval := NULL; v.repeat_weekdays := NULL; v.repeat_starts_on := NULL; v.repeat_ends_on := NULL;
    ELSE
      IF v.parent_task_id IS NOT NULL THEN RAISE EXCEPTION 'Subtasks cannot repeat; set the repeat on the main task'; END IF;
      v.repeat_unit := upper(r ->> 'unit');
      IF v.repeat_unit IS NULL OR v.repeat_unit NOT IN ('DAY', 'WEEK', 'MONTH', 'YEAR') THEN RAISE EXCEPTION 'Choose how often the task repeats'; END IF;
      v.repeat_interval := COALESCE(NULLIF(r ->> 'interval', '')::int, 1);
      IF v.repeat_interval NOT BETWEEN 1 AND 999 THEN RAISE EXCEPTION 'Repeat every 1 to 999 %s', lower(v.repeat_unit); END IF;
      v_wd := NULL;
      IF v.repeat_unit = 'WEEK' AND jsonb_typeof(r -> 'weekdays') = 'array' THEN
        SELECT array_agg(DISTINCT w ORDER BY w) INTO v_wd FROM (SELECT x::smallint AS w FROM jsonb_array_elements_text(r -> 'weekdays') x) s;
        IF EXISTS (SELECT 1 FROM unnest(v_wd) w WHERE w NOT BETWEEN 1 AND 7) THEN RAISE EXCEPTION 'Weekdays are 1 (Mon) to 7 (Sun)'; END IF;
      END IF;
      v.repeat_weekdays := v_wd;
      v.repeat_ends_on := NULLIF(r ->> 'ends_on', '')::date;
      v.due_date := COALESCE(v.due_date, v_now::date);
      v.repeat_starts_on := NULL;   -- set below
    END IF;
  END IF;

  IF v.repeat_unit IS NOT NULL THEN
    IF v.due_date IS NULL THEN RAISE EXCEPTION 'A repeating task needs a date; stop the repeat to clear it'; END IF;
    IF v.repeat_starts_on IS NULL OR p_task ? 'due_date' THEN
      IF v.repeat_unit = 'WEEK' AND v.repeat_weekdays IS NOT NULL THEN   -- start on the first chosen weekday
        WHILE NOT extract(isodow FROM v.due_date)::smallint = ANY (v.repeat_weekdays) LOOP v.due_date := v.due_date + 1; END LOOP;
      END IF;
      v.repeat_starts_on := v.due_date;
    END IF;
    IF v.repeat_ends_on IS NOT NULL AND v.repeat_ends_on < v.due_date THEN RAISE EXCEPTION 'The repeat cannot end before the task''s date'; END IF;
  END IF;
  IF v.due_date IS NULL THEN v.due_time := NULL; END IF;
  v.updated_by := v_me;

  IF v_new THEN
    INSERT INTO org_tasks SELECT v.*;
  ELSE
    UPDATE org_tasks SET list_id = v.list_id, title = v.title, details = v.details, due_date = v.due_date, due_time = v.due_time,
                         is_starred = v.is_starred, starred_at = v.starred_at, assigned_user_id = v.assigned_user_id,
                         position = v.position, repeat_unit = v.repeat_unit, repeat_interval = v.repeat_interval,
                         repeat_weekdays = v.repeat_weekdays, repeat_starts_on = v.repeat_starts_on, repeat_ends_on = v.repeat_ends_on,
                         updated_by = v_me
     WHERE task_id = v.task_id;
    UPDATE org_tasks SET list_id = v.list_id, updated_by = v_me WHERE parent_task_id = v.task_id AND list_id <> v.list_id;
  END IF;
  SELECT * INTO v FROM org_tasks WHERE task_id = v.task_id;
  RETURN bps.org_task_json(v, v_now, true);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_task_save(bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_task_save(bigint, jsonb) TO authenticated, service_role, bps_dev;
