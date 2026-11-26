-- ============================================================
-- SQL tests for Organizer › Tasks: date rules (next occurrence, due groups, labels), default list, lists (private /
-- shared, rename, sort, delete), tasks (quick add at the top, partial save, star, assign, validation), subtasks (one
-- level), complete / reopen, repeating tasks (next occurrence in the database, subtasks copied, late completion,
-- end date), move / indent / outdent, delete + undo, clear completed, the views, privacy and access.
-- One transaction, ROLLED BACK; local DB only:
--   docker exec -i supabase_db_bps-local psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 < database/tests/organizer_tasks_test.sql
-- Assumes the Alpine Bakery migration: staff user 200000174045 (Company Administrator), customer user 200000174046.
-- Creates staff users "zz tasks other" (Company Administrator) and "zz tasks none" (no role) inside the transaction.
-- ============================================================
BEGIN;
SET search_path = bps, public;
CREATE TEMP TABLE _t (name text, ok boolean);
CREATE TEMP TABLE _v (k text PRIMARY KEY, v text);
GRANT ALL ON _t, _v TO PUBLIC;

-- pure date rules
INSERT INTO _t VALUES
  ('daily: every 3 days', org_task_next_due('2026-11-25', 'DAY', 3, NULL, '2026-11-25') = '2026-11-28'),
  ('weekly on Mon, Thu: Thu -> Mon', org_task_next_due('2026-11-26', 'WEEK', 1, '{1,4}', '2026-11-26') = '2026-11-30'),
  ('every 2 weeks on Mon, Thu skips the off week', org_task_next_due('2026-11-26', 'WEEK', 2, '{1,4}', '2026-11-26') = '2026-12-07'),
  ('weekly without weekdays keeps the start weekday', org_task_next_due('2026-11-25', 'WEEK', 1, NULL, '2026-11-25') = '2026-12-02'),
  ('monthly on the 31st: Jan 31 -> Feb 28', org_task_next_due('2026-01-31', 'MONTH', 1, NULL, '2026-01-31') = '2026-02-28'),
  ('monthly on the 31st returns to the 31st after February', org_task_next_due('2026-02-28', 'MONTH', 1, NULL, '2026-01-31') = '2026-03-31'),
  ('every 3 months', org_task_next_due('2026-01-15', 'MONTH', 3, NULL, '2026-01-15') = '2026-04-15'),
  ('yearly on Feb 29 -> Feb 28, then Feb 29 in a leap year', org_task_next_due('2024-02-29', 'YEAR', 1, NULL, '2024-02-29') = '2025-02-28'
                                                           AND org_task_next_due('2027-02-28', 'YEAR', 1, NULL, '2024-02-29') = '2028-02-29'),
  ('due groups', org_task_due_group('2026-11-24', NULL, '2026-11-25 09:00') = 'OVERDUE'
              AND org_task_due_group('2026-11-25', '08:00', '2026-11-25 09:00') = 'OVERDUE'
              AND org_task_due_group('2026-11-25', '10:00', '2026-11-25 09:00') = 'TODAY'
              AND org_task_due_group('2026-11-26', NULL, '2026-11-25 09:00') = 'TOMORROW'
              AND org_task_due_group('2026-12-02', NULL, '2026-11-25 09:00') = 'NEXT_7_DAYS'
              AND org_task_due_group('2026-12-03', NULL, '2026-11-25 09:00') = 'LATER'
              AND org_task_due_group(NULL, NULL, '2026-11-25 09:00') = 'NONE'),
  ('due labels', org_task_due_label('2026-11-25', '14:30', '2026-11-25') = 'Today, 2:30 PM'
              AND org_task_due_label('2026-11-24', NULL, '2026-11-25') = 'Yesterday'
              AND org_task_due_label('2026-11-30', NULL, '2026-11-25') = 'Mon, Nov 30'
              AND org_task_due_label('2027-01-04', NULL, '2026-11-25') = 'Jan 4, 2027'),
  ('repeat labels', org_task_repeat_label('DAY', 1, NULL, '2026-11-25', NULL) = 'Daily'
                 AND org_task_repeat_label('WEEK', 2, '{1,4}', '2026-11-26', NULL) = 'Every 2 weeks on Mon, Thu'
                 AND org_task_repeat_label('MONTH', 1, NULL, '2026-01-31', '2026-12-31') = 'Monthly on day 31, until Dec 31, 2026');

DO $$
DECLARE t bigint := 200000000002; u2 bigint; u3 bigint;
BEGIN
  INSERT INTO fnd_users (tenant_id, auth_user_id, user_name, user_type) VALUES (t, 'aaaaaaaa-0000-4000-8000-0000000000d2', 'zz tasks other', 'TENANCY_USER') RETURNING user_id INTO u2;
  INSERT INTO fnd_user_tenants (tenant_id, user_id) VALUES (t, u2);
  INSERT INTO fnd_user_roles (tenant_id, user_id, role_id) SELECT t, u2, role_id FROM fnd_roles WHERE tenant_id = t AND role_name = 'Company Administrator';
  INSERT INTO fnd_users (tenant_id, auth_user_id, user_name, user_type) VALUES (t, 'aaaaaaaa-0000-4000-8000-0000000000d3', 'zz tasks none', 'TENANCY_USER') RETURNING user_id INTO u3;
  INSERT INTO fnd_user_tenants (tenant_id, user_id) VALUES (t, u3);
  INSERT INTO _v VALUES ('u2', u2), ('lists_before', (SELECT count(*) FROM org_task_lists)), ('tasks_before', (SELECT count(*) FROM org_tasks));
END $$;

CREATE TEMP TABLE _as (k text PRIMARY KEY, auth uuid);
GRANT ALL ON _as TO PUBLIC;
INSERT INTO _as VALUES ('one', '9b9b43b7-5a4c-4cbd-b5f4-b0585cbc393b'), ('other', 'aaaaaaaa-0000-4000-8000-0000000000d2'),
                       ('none', 'aaaaaaaa-0000-4000-8000-0000000000d3'), ('customer', '006f6c23-5efa-4f31-b0f3-b36ad4d587e7');

-- 1) staff administrator
SELECT set_config('request.jwt.claims', (bps.bps_access_token_hook(jsonb_build_object('user_id', auth,
  'claims', jsonb_build_object('role', 'authenticated', 'sub', auth, 'app_metadata', '{}'::jsonb))) -> 'claims')::text, true) FROM _as WHERE k = 'one' \g /dev/null
SET LOCAL ROLE authenticated;
DO $$
DECLARE
  t bigint := 200000000002; r jsonb; my bigint; sh bigint; pv bigint; a bigint; b bigint; c bigint; s1 bigint; s2 bigint; rp bigint; nx bigint;
  d boolean; today date := bps.org_task_now(200000000002)::date; u2 bigint := (SELECT v FROM _v WHERE k = 'u2');
BEGIN
  r := bps.org_task_lists_get(t);
  my := (SELECT (x ->> 'list_id')::bigint FROM jsonb_array_elements(r -> 'lists') x WHERE (x ->> 'is_default')::boolean);
  INSERT INTO _v VALUES ('my', my);
  INSERT INTO _t VALUES ('first open creates My Tasks', my IS NOT NULL AND (SELECT list_name FROM org_task_lists WHERE list_id = my) = 'My Tasks');
  PERFORM bps.org_task_lists_get(t);
  INSERT INTO _t VALUES ('only one default list per user', (SELECT count(*) FROM org_task_lists WHERE owner_user_id = bps.fnd_current_user_id() AND is_default) = 1);
  INSERT INTO _t VALUES ('assignable users are active staff only', (r -> 'users') @> jsonb_build_array(jsonb_build_object('user_id', u2))
    AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r -> 'users') x JOIN fnd_users u ON u.user_id = (x ->> 'user_id')::bigint WHERE u.user_type <> 'TENANCY_USER'));

  -- lists
  sh := (bps.org_task_list_save(t, '{"list_name":"Zz Office","is_shared":true}') ->> 'list_id')::bigint;
  pv := (bps.org_task_list_save(t, '{"list_name":"Zz Private"}') ->> 'list_id')::bigint;
  INSERT INTO _v VALUES ('sh', sh), ('pv', pv);
  BEGIN PERFORM bps.org_task_list_save(t, jsonb_build_object('list_id', my, 'is_shared', true)); d := false; EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE 'My Tasks is always private%'; END;
  INSERT INTO _t VALUES ('My Tasks cannot be shared', d);
  BEGIN PERFORM bps.org_task_list_delete(t, my); d := false; EXCEPTION WHEN OTHERS THEN d := SQLERRM = 'My Tasks cannot be deleted'; END;
  INSERT INTO _t VALUES ('My Tasks cannot be deleted', d);
  BEGIN PERFORM bps.org_task_list_save(t, '{"list_name":"  "}'); d := false; EXCEPTION WHEN OTHERS THEN d := SQLERRM = 'Give the list a name'; END;
  INSERT INTO _t VALUES ('a list needs a name', d);
  r := bps.org_task_list_save(t, jsonb_build_object('list_id', pv, 'sort_mode', 'date'));
  INSERT INTO _t VALUES ('sort mode saved, name kept', r ->> 'sort_mode' = 'DATE' AND r ->> 'list_name' = 'Zz Private');

  -- quick add: no list -> My Tasks, new tasks go on top
  a := (bps.org_task_save(t, '{"title":"  Zz order   flour "}') ->> 'task_id')::bigint;
  b := (bps.org_task_save(t, jsonb_build_object('list_id', my, 'title', 'Zz call Featherstone', 'due_date', today - 1)) ->> 'task_id')::bigint;
  c := (bps.org_task_save(t, jsonb_build_object('list_id', my, 'title', 'Zz check oven', 'due_date', today, 'due_time', '23:59')) ->> 'task_id')::bigint;
  INSERT INTO _v VALUES ('a', a), ('b', b), ('c', c);
  INSERT INTO _t VALUES ('a task without a list goes to My Tasks, title tidied', (SELECT list_id = my AND title = 'Zz order flour' FROM org_tasks WHERE task_id = a));
  r := bps.org_tasks_get(t, 'LIST', my);
  INSERT INTO _t VALUES ('new tasks go to the top (my order)', (r -> 'tasks' -> 0 ->> 'task_id')::bigint = c AND (r -> 'tasks' -> 2 ->> 'task_id')::bigint = a);
  INSERT INTO _t VALUES ('due groups and labels come from the database', (r -> 'tasks' -> 1 ->> 'due_group') = 'OVERDUE' AND (r -> 'tasks' -> 1 ->> 'due_label') = 'Yesterday'
    AND (r -> 'tasks' -> 0 ->> 'due_label') = 'Today, 11:59 PM');
  BEGIN PERFORM bps.org_task_save(t, '{"title":""}'); d := false; EXCEPTION WHEN OTHERS THEN d := SQLERRM = 'Give the task a title'; END;
  INSERT INTO _t VALUES ('a task needs a title', d);

  -- partial save, star, assign
  r := bps.org_task_save(t, jsonb_build_object('task_id', a, 'details', 'Bay State, 40 bags', 'is_starred', true));
  INSERT INTO _t VALUES ('partial save keeps the title, stars with a time', r ->> 'title' = 'Zz order flour' AND (r ->> 'is_starred')::boolean AND r ->> 'starred_at' IS NOT NULL);
  r := bps.org_task_save(t, jsonb_build_object('task_id', a, 'due_date', NULL));
  INSERT INTO _t VALUES ('clearing the date clears nothing else', r ->> 'details' = 'Bay State, 40 bags' AND r ->> 'due_date' IS NULL);
  BEGIN PERFORM bps.org_task_save(t, jsonb_build_object('task_id', a, 'assigned_user_id', 200000174046)); d := false; EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE '%active staff%'; END;
  INSERT INTO _t VALUES ('a customer user cannot be assigned', d);
  r := bps.org_task_save(t, jsonb_build_object('task_id', b, 'assigned_user_id', u2));
  INSERT INTO _t VALUES ('assign to a staff user', r ->> 'assigned_name' = 'zz tasks other');

  -- subtasks
  s1 := (bps.org_task_save(t, jsonb_build_object('parent_task_id', a, 'title', 'Zz count bags')) ->> 'task_id')::bigint;
  s2 := (bps.org_task_save(t, jsonb_build_object('parent_task_id', a, 'title', 'Zz email order')) ->> 'task_id')::bigint;
  INSERT INTO _v VALUES ('s1', s1), ('s2', s2);
  r := bps.org_tasks_get(t, 'LIST', my);
  INSERT INTO _t VALUES ('subtasks nest under the main task in order', (SELECT x -> 'subtasks' -> 0 ->> 'task_id' = s1::text AND x -> 'subtasks' -> 1 ->> 'task_id' = s2::text AND (x ->> 'subtask_count')::int = 2
       FROM jsonb_array_elements(r -> 'tasks') x WHERE (x ->> 'task_id')::bigint = a)
    AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r -> 'tasks') x WHERE (x ->> 'task_id')::bigint = s1));
  BEGIN PERFORM bps.org_task_save(t, jsonb_build_object('parent_task_id', s1, 'title', 'x')); d := false; EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE 'A subtask cannot have subtasks%'; END;
  INSERT INTO _t VALUES ('one level of subtasks only', d);
  BEGIN PERFORM bps.org_task_save(t, jsonb_build_object('task_id', s1, 'repeat', jsonb_build_object('unit', 'DAY'))); d := false; EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE 'Subtasks cannot repeat%'; END;
  INSERT INTO _t VALUES ('subtasks cannot repeat', d);

  -- complete / reopen
  PERFORM bps.org_task_complete(t, s1, true);
  INSERT INTO _t VALUES ('a subtask completes alone', (SELECT is_completed FROM org_tasks WHERE task_id = s1) AND NOT (SELECT is_completed FROM org_tasks WHERE task_id = a));
  PERFORM bps.org_task_complete(t, a, true);
  INSERT INTO _t VALUES ('completing the main task ticks its subtasks', (SELECT bool_and(is_completed) FROM org_tasks WHERE task_id IN (a, s1, s2)));
  r := bps.org_tasks_get(t, 'LIST', my);
  INSERT INTO _t VALUES ('completed tasks move to the Completed section', jsonb_array_length(r -> 'tasks') = 2 AND (r -> 'completed' -> 0 ->> 'task_id')::bigint = a
    AND r -> 'completed' -> 0 ->> 'completed_label' = 'Completed Today');
  PERFORM bps.org_task_complete(t, s2, false);
  INSERT INTO _t VALUES ('reopening a subtask reopens its main task', NOT (SELECT is_completed FROM org_tasks WHERE task_id = a) AND (SELECT is_completed FROM org_tasks WHERE task_id = s1));

  -- repeating task with subtasks (weekly deep clean)
  r := bps.org_task_save(t, jsonb_build_object('list_id', sh, 'title', 'Zz deep clean', 'due_date', today, 'due_time', '15:00', 'assigned_user_id', u2,
         'repeat', jsonb_build_object('unit', 'WEEK', 'interval', 1, 'weekdays', jsonb_build_array(extract(isodow FROM today)::int))));
  rp := (r ->> 'task_id')::bigint;
  INSERT INTO _t VALUES ('repeat rule saved with its label', r ->> 'repeat_label' = 'Weekly on ' || to_char(today, 'Dy') AND (r -> 'repeat' ->> 'starts_on')::date = today
    AND r ->> 'next_due_label' = bps.org_task_due_label(today + 7, NULL, today));
  PERFORM bps.org_task_save(t, jsonb_build_object('parent_task_id', rp, 'title', 'Zz ovens'));
  PERFORM bps.org_task_save(t, jsonb_build_object('parent_task_id', rp, 'title', 'Zz floors'));
  PERFORM bps.org_task_complete(t, (SELECT task_id FROM org_tasks WHERE parent_task_id = rp AND title = 'Zz ovens'), true);
  r := bps.org_task_complete(t, rp, true);
  nx := (r ->> 'next_task_id')::bigint;
  INSERT INTO _t VALUES ('completing a repeating task creates the next one a week later',
    (SELECT due_date = today + 7 AND due_time = '15:00' AND list_id = sh AND assigned_user_id = u2 AND repeat_unit = 'WEEK' AND NOT is_completed FROM org_tasks WHERE task_id = nx));
  INSERT INTO _t VALUES ('the next one gets fresh copies of the subtasks',
    (SELECT count(*) = 2 AND bool_and(NOT is_completed) FROM org_tasks WHERE parent_task_id = nx));
  INSERT INTO _t VALUES ('the completed one keeps no repeat rule', (SELECT repeat_unit IS NULL AND is_completed FROM org_tasks WHERE task_id = rp));
  PERFORM bps.org_task_complete(t, rp, false);
  INSERT INTO _t VALUES ('reopening the old one does not repeat again', (SELECT count(*) FROM org_tasks WHERE list_id = sh AND title = 'Zz deep clean' AND parent_task_id IS NULL) = 2);

  -- late completion: daily task due 5 days ago -> next is today (no backlog)
  r := bps.org_task_save(t, jsonb_build_object('title', 'Zz wipe slicer', 'due_date', today - 5, 'repeat', jsonb_build_object('unit', 'DAY')));
  r := bps.org_task_complete(t, (r ->> 'task_id')::bigint, true);
  INSERT INTO _t VALUES ('a task done late rolls its next date to today', (SELECT due_date FROM org_tasks WHERE task_id = (r ->> 'next_task_id')::bigint) = today);
  -- end date
  r := bps.org_task_save(t, jsonb_build_object('title', 'Zz last one', 'due_date', today, 'repeat', jsonb_build_object('unit', 'MONTH', 'ends_on', today + 3)));
  r := bps.org_task_complete(t, (r ->> 'task_id')::bigint, true);
  INSERT INTO _t VALUES ('no next occurrence after the end date', r ->> 'next_task_id' IS NULL);
  BEGIN PERFORM bps.org_task_save(t, jsonb_build_object('task_id', nx, 'due_date', NULL)); d := false; EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE 'A repeating task needs a date%'; END;
  INSERT INTO _t VALUES ('a repeating task keeps its date', d);
  r := bps.org_task_save(t, jsonb_build_object('title', 'Zz no date repeat', 'repeat', jsonb_build_object('unit', 'YEAR')));
  INSERT INTO _t VALUES ('repeat without a date starts today', (r ->> 'due_date')::date = today);

  -- move / indent / outdent
  r := bps.org_tasks_get(t, 'LIST', my);
  PERFORM bps.org_task_move(t, a, NULL, 0);
  INSERT INTO _t VALUES ('move to the top', (bps.org_tasks_get(t, 'LIST', my) -> 'tasks' -> 0 ->> 'task_id')::bigint = a);
  PERFORM bps.org_task_move(t, c, b, 0);
  INSERT INTO _t VALUES ('indent makes a subtask', (SELECT parent_task_id FROM org_tasks WHERE task_id = c) = b);
  BEGIN PERFORM bps.org_task_move(t, a, b, 0); d := false; EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE '%has subtasks%'; END;
  INSERT INTO _t VALUES ('a task with subtasks cannot be indented', d);
  BEGIN PERFORM bps.org_task_move(t, nx, b, 0); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('cannot go under a task of another list', d);
  PERFORM bps.org_task_move(t, c, NULL, 1);
  INSERT INTO _t VALUES ('outdent puts it back in the list at the index',
    (SELECT parent_task_id IS NULL FROM org_tasks WHERE task_id = c) AND (bps.org_tasks_get(t, 'LIST', my) -> 'tasks' -> 1 ->> 'task_id')::bigint = c);
  INSERT INTO _t VALUES ('positions are renumbered without gaps',
    (SELECT array_agg(position ORDER BY position) FROM org_tasks WHERE list_id = my AND parent_task_id IS NULL AND NOT is_completed AND deleted_at IS NULL)
      = (SELECT array_agg(g) FROM generate_series(0, (SELECT count(*) - 1 FROM org_tasks WHERE list_id = my AND parent_task_id IS NULL AND NOT is_completed AND deleted_at IS NULL)::int) g));

  -- move to another list takes subtasks
  r := bps.org_task_save(t, jsonb_build_object('task_id', a, 'list_id', pv));
  INSERT INTO _t VALUES ('moving a task to another list takes its subtasks', (SELECT bool_and(list_id = pv) FROM org_tasks WHERE task_id IN (a, s1, s2)));
  BEGIN PERFORM bps.org_task_save(t, jsonb_build_object('task_id', s1, 'list_id', my)); d := false; EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE 'Move the main task%'; END;
  INSERT INTO _t VALUES ('a subtask does not move list alone', d);

  -- delete + undo
  PERFORM bps.org_task_delete(t, a);
  INSERT INTO _t VALUES ('delete hides the task and its subtasks', (SELECT bool_and(deleted_at IS NOT NULL) FROM org_tasks WHERE task_id IN (a, s1, s2))
    AND jsonb_array_length(bps.org_tasks_get(t, 'LIST', pv) -> 'tasks') = 0);
  PERFORM bps.org_task_delete(t, a, true);
  INSERT INTO _t VALUES ('undo brings them back', (SELECT bool_and(deleted_at IS NULL) FROM org_tasks WHERE task_id IN (a, s1, s2)));

  -- views
  r := bps.org_tasks_get(t, 'UPCOMING');
  INSERT INTO _t VALUES ('Upcoming lists dated open tasks by date', (SELECT bool_and(x ->> 'due_date' IS NOT NULL) FROM jsonb_array_elements(r -> 'tasks') x)
    AND (r -> 'tasks' -> 0 ->> 'due_group') = 'OVERDUE');
  r := bps.org_tasks_get(t, 'STARRED');
  INSERT INTO _t VALUES ('Starred view', EXISTS (SELECT 1 FROM jsonb_array_elements(r -> 'tasks') x WHERE (x ->> 'task_id')::bigint = a)
    AND (SELECT bool_and((x ->> 'is_starred')::boolean) FROM jsonb_array_elements(r -> 'tasks') x));
  r := bps.org_task_lists_get(t);
  INSERT INTO _t VALUES ('rail counts', (r -> 'views' ->> 'overdue')::int >= 1
    AND (SELECT (x ->> 'open_count')::int FROM jsonb_array_elements(r -> 'lists') x WHERE (x ->> 'list_id')::bigint = pv) = 1);

  -- clear completed
  PERFORM bps.org_task_complete(t, a, true);
  r := bps.org_tasks_clear_completed(t, pv);
  INSERT INTO _t VALUES ('clear completed removes completed main tasks with subtasks', (r ->> 'task_count')::int = 1
    AND (SELECT bool_and(deleted_at IS NOT NULL) FROM org_tasks WHERE task_id IN (a, s1, s2)));

  -- a private list of mine with a task assigned to the other user
  INSERT INTO _v VALUES ('pvtask', (bps.org_task_save(t, jsonb_build_object('list_id', pv, 'title', 'Zz for other', 'assigned_user_id', u2)) ->> 'task_id'));
  INSERT INTO _v VALUES ('pvsecret', (bps.org_task_save(t, jsonb_build_object('list_id', pv, 'title', 'Zz secret')) ->> 'task_id'));
END $$;

-- 2) another staff member
RESET ROLE;
SELECT set_config('request.jwt.claims', (bps.bps_access_token_hook(jsonb_build_object('user_id', auth,
  'claims', jsonb_build_object('role', 'authenticated', 'sub', auth, 'app_metadata', '{}'::jsonb))) -> 'claims')::text, true) FROM _as WHERE k = 'other' \g /dev/null
SET LOCAL ROLE authenticated;
DO $$
DECLARE
  t bigint := 200000000002; r jsonb; d boolean;
  sh bigint := (SELECT v FROM _v WHERE k = 'sh'); pv bigint := (SELECT v FROM _v WHERE k = 'pv');
  pvtask bigint := (SELECT v FROM _v WHERE k = 'pvtask'); pvsecret bigint := (SELECT v FROM _v WHERE k = 'pvsecret');
BEGIN
  r := bps.org_task_lists_get(t);
  INSERT INTO _t VALUES ('others see shared lists, not private ones',
    EXISTS (SELECT 1 FROM jsonb_array_elements(r -> 'lists') x WHERE (x ->> 'list_id')::bigint = sh AND NOT (x ->> 'is_mine')::boolean)
    AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r -> 'lists') x WHERE (x ->> 'list_id')::bigint = pv));
  INSERT INTO _t VALUES ('row security hides the private list too', NOT EXISTS (SELECT 1 FROM org_task_lists WHERE list_id = pv)
    AND EXISTS (SELECT 1 FROM org_tasks WHERE task_id = pvtask) AND NOT EXISTS (SELECT 1 FROM org_tasks WHERE task_id = pvsecret));
  BEGIN PERFORM bps.org_tasks_get(t, 'LIST', pv); d := false; EXCEPTION WHEN OTHERS THEN d := SQLERRM = 'List not found'; END;
  INSERT INTO _t VALUES ('cannot open another user''s private list', d);
  BEGIN PERFORM bps.org_task_save(t, jsonb_build_object('task_id', pvsecret, 'title', 'x')); d := false; EXCEPTION WHEN OTHERS THEN d := SQLERRM = 'Task not found'; END;
  INSERT INTO _t VALUES ('cannot edit a task in another user''s private list', d);
  r := bps.org_tasks_get(t, 'ASSIGNED');
  INSERT INTO _t VALUES ('Assigned to me shows tasks from a private list and a shared list',
    EXISTS (SELECT 1 FROM jsonb_array_elements(r -> 'tasks') x WHERE (x ->> 'task_id')::bigint = pvtask)
    AND EXISTS (SELECT 1 FROM jsonb_array_elements(r -> 'tasks') x WHERE x ->> 'title' = 'Zz deep clean'));
  r := bps.org_task_complete(t, pvtask, true);
  INSERT INTO _t VALUES ('the assignee can complete it', (r ->> 'is_completed')::boolean);
  BEGIN PERFORM bps.org_task_save(t, jsonb_build_object('task_id', pvtask, 'list_id', sh)); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('the assignee cannot move it out of a private list', d);
  BEGIN PERFORM bps.org_task_list_save(t, jsonb_build_object('list_id', sh, 'is_shared', false)); d := false; EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE 'Only % can change who sees%'; END;
  INSERT INTO _t VALUES ('only the owner can stop sharing a list', d);
  r := bps.org_task_list_save(t, jsonb_build_object('list_id', sh, 'list_name', 'Zz Office team'));
  INSERT INTO _t VALUES ('others can rename a shared list', r ->> 'list_name' = 'Zz Office team');
END $$;

-- 3) a staff user without Tasks access, and a customer user
RESET ROLE;
SELECT set_config('request.jwt.claims', (bps.bps_access_token_hook(jsonb_build_object('user_id', auth,
  'claims', jsonb_build_object('role', 'authenticated', 'sub', auth, 'app_metadata', '{}'::jsonb))) -> 'claims')::text, true) FROM _as WHERE k = 'none' \g /dev/null
SET LOCAL ROLE authenticated;
DO $$
DECLARE t bigint := 200000000002; d boolean;
BEGIN
  BEGIN PERFORM bps.org_task_lists_get(t); d := false; EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE 'You do not have access%'; END;
  INSERT INTO _t VALUES ('no Tasks access: cannot open', d);
  BEGIN PERFORM bps.org_task_save(t, '{"title":"x"}'); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('no Tasks access: cannot add', d);
  INSERT INTO _t VALUES ('no Tasks access: rows hidden', (SELECT count(*) FROM org_task_lists) = 0 AND (SELECT count(*) FROM org_tasks) = 0);
  BEGIN PERFORM bps.org_task_check(t, 'R'); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('app users cannot call the internal check', d);
  BEGIN INSERT INTO org_tasks (tenant_id, list_id, title) VALUES (t, 1, 'x'); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('no direct writes to the tables', d);
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claims', (bps.bps_access_token_hook(jsonb_build_object('user_id', auth,
  'claims', jsonb_build_object('role', 'authenticated', 'sub', auth, 'app_metadata', '{}'::jsonb))) -> 'claims')::text, true) FROM _as WHERE k = 'customer' \g /dev/null
SET LOCAL ROLE authenticated;
DO $$ DECLARE t bigint := 200000000002; d boolean; BEGIN
  BEGIN PERFORM bps.org_task_lists_get(t); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('a customer user cannot open Tasks', d);
END $$;

RESET ROLE;
SELECT CASE WHEN ok THEN 'PASS ' ELSE 'FAIL ' END || name AS result FROM _t;
DO $$
DECLARE bad int; total int;
BEGIN
  SELECT count(*) FILTER (WHERE NOT ok OR ok IS NULL), count(*) INTO bad, total FROM _t;
  IF bad > 0 THEN RAISE EXCEPTION '% of % tasks tests failed', bad, total; END IF;
  RAISE NOTICE 'all % tasks tests passed', total;
END $$;
ROLLBACK;
