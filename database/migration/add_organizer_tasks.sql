-- ============================================================
-- Organizer › Tasks: Google Tasks style to-do lists for tenant staff.
--
--   org_task_lists : a user's private lists (each user gets one default "My Tasks", created on first open) and lists
--                    shared with the company (is_shared; every staff member with organizer.tasks sees and edits them).
--   org_tasks      : tasks and one level of subtasks (parent_task_id). Optional due date and time, star, assignee
--                    (a staff user, who sees the task under "Assigned to me" even in a private list), repeat rule,
--                    manual order (position), completed state, soft delete (deleted_at) for Undo.
-- Repeats: completing a repeating top-level task creates the next occurrence in org_task_complete (with fresh
-- copies of its subtasks); the completed one keeps no repeat rule. Dates (overdue / today / next occurrence) are
-- computed in org_task_due_group / org_task_next_due in the tenant's time zone.
-- New access area organizer.tasks (granted to the system Company Administrator role through fnd_tenant_access_seed).
-- Then load: database/functions/org_task_check.sql, org_task_now.sql, org_task_next_due.sql, org_task_due_group.sql,
--            org_task_due_label.sql, org_task_repeat_label.sql, org_task_json.sql, org_task_lists_get.sql, org_task_list_save.sql,
--            org_task_list_delete.sql, org_tasks_get.sql, org_task_save.sql, org_task_complete.sql,
--            org_task_move.sql, org_task_delete.sql, org_tasks_clear_completed.sql
-- ============================================================

INSERT INTO bps.fnd_areas (area_key, module, area_name, audience, display_order)
VALUES ('organizer.tasks', 'Organizer', 'Tasks', 'TENANT', 730)
ON CONFLICT (area_key) DO NOTHING;

DO $$ DECLARE t record; BEGIN
  FOR t IN SELECT tenant_id FROM bps.fnd_tenants LOOP PERFORM bps.fnd_tenant_access_seed(t.tenant_id); END LOOP;
END $$;

-- ── org_task_lists ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS bps.org_task_lists (
  list_id       bigint PRIMARY KEY DEFAULT nextval('bps.fnd_entity_id_seq'),
  tenant_id     bigint  NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  owner_user_id bigint  NOT NULL REFERENCES bps.fnd_users(user_id) ON DELETE CASCADE,
  list_name     text    NOT NULL CONSTRAINT chk_org_task_lists_list_name CHECK (btrim(list_name) <> '' AND length(list_name) <= 80),
  is_shared     boolean NOT NULL DEFAULT false,
  is_default    boolean NOT NULL DEFAULT false,
  sort_mode     text    NOT NULL DEFAULT 'MY_ORDER' CONSTRAINT chk_org_task_lists_sort_mode CHECK (sort_mode IN ('MY_ORDER', 'DATE', 'STARRED')),
  created_at    timestamptz NOT NULL DEFAULT now(),
  created_by    bigint,
  updated_at    timestamptz NOT NULL DEFAULT now(),
  updated_by    bigint,
  CONSTRAINT chk_org_task_lists_default_private CHECK (NOT (is_default AND is_shared))
);
COMMENT ON TABLE  bps.org_task_lists IS 'Organizer › Tasks lists: private to owner_user_id, or shared with the company (is_shared).';
COMMENT ON COLUMN bps.org_task_lists.is_default IS 'The owner''s "My Tasks" list: created on first open, cannot be deleted or shared.';
COMMENT ON COLUMN bps.org_task_lists.sort_mode  IS 'MY_ORDER (manual, drag to reorder) | DATE (grouped by due date) | STARRED (starred first).';
CREATE UNIQUE INDEX IF NOT EXISTS uq_org_task_lists_default ON bps.org_task_lists (tenant_id, owner_user_id) WHERE is_default;
CREATE INDEX IF NOT EXISTS idx_org_task_lists_owner ON bps.org_task_lists (tenant_id, owner_user_id);

-- ── org_tasks ──────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS bps.org_tasks (
  task_id          bigint PRIMARY KEY DEFAULT nextval('bps.fnd_entity_id_seq'),
  tenant_id        bigint  NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  list_id          bigint  NOT NULL REFERENCES bps.org_task_lists(list_id) ON DELETE CASCADE,
  parent_task_id   bigint  REFERENCES bps.org_tasks(task_id) ON DELETE CASCADE,
  title            text    NOT NULL CONSTRAINT chk_org_tasks_title CHECK (btrim(title) <> '' AND length(title) <= 500),
  details          text    CONSTRAINT chk_org_tasks_details CHECK (length(details) <= 8000),
  due_date         date,
  due_time         time,
  is_starred       boolean NOT NULL DEFAULT false,
  starred_at       timestamptz,
  assigned_user_id bigint  REFERENCES bps.fnd_users(user_id) ON DELETE SET NULL,
  position         integer NOT NULL DEFAULT 0,
  is_completed     boolean NOT NULL DEFAULT false,
  completed_at     timestamptz,
  completed_by     bigint,
  repeat_unit      text    CONSTRAINT chk_org_tasks_repeat_unit CHECK (repeat_unit IN ('DAY', 'WEEK', 'MONTH', 'YEAR')),
  repeat_interval  integer CONSTRAINT chk_org_tasks_repeat_interval CHECK (repeat_interval BETWEEN 1 AND 999),
  repeat_weekdays  smallint[] CONSTRAINT chk_org_tasks_repeat_weekdays CHECK (repeat_weekdays <@ ARRAY[1, 2, 3, 4, 5, 6, 7]::smallint[]),
  repeat_starts_on date,
  repeat_ends_on   date,
  deleted_at       timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  created_by       bigint,
  updated_at       timestamptz NOT NULL DEFAULT now(),
  updated_by       bigint,
  CONSTRAINT chk_org_tasks_time_needs_date CHECK (due_time IS NULL OR due_date IS NOT NULL),
  CONSTRAINT chk_org_tasks_repeat_complete CHECK (
    (repeat_unit IS NULL AND repeat_interval IS NULL AND repeat_weekdays IS NULL AND repeat_starts_on IS NULL AND repeat_ends_on IS NULL)
    OR (repeat_unit IS NOT NULL AND repeat_interval IS NOT NULL AND repeat_starts_on IS NOT NULL AND due_date IS NOT NULL AND parent_task_id IS NULL)),
  CONSTRAINT chk_org_tasks_completed CHECK (is_completed = (completed_at IS NOT NULL))
);
COMMENT ON TABLE  bps.org_tasks IS 'Organizer › Tasks: tasks and one level of subtasks (parent_task_id).';
COMMENT ON COLUMN bps.org_tasks.due_time         IS 'Optional time on due_date, in the tenant''s time zone.';
COMMENT ON COLUMN bps.org_tasks.assigned_user_id IS 'Staff user the task is for; they see it under Assigned to me even when the list is private.';
COMMENT ON COLUMN bps.org_tasks.position         IS 'Manual order among siblings (open tasks of a list, or subtasks of a parent); lower first.';
COMMENT ON COLUMN bps.org_tasks.repeat_weekdays  IS 'For WEEK repeats: ISO weekdays 1 (Mon) .. 7 (Sun); NULL = the weekday of repeat_starts_on.';
COMMENT ON COLUMN bps.org_tasks.repeat_starts_on IS 'First date of the series; anchors month-end days and every-N-weeks cycles.';
COMMENT ON COLUMN bps.org_tasks.repeat_ends_on   IS 'No occurrence is created after this date (NULL = never ends).';
COMMENT ON COLUMN bps.org_tasks.deleted_at       IS 'Soft delete so the screen can offer Undo; deleted rows are hidden everywhere.';
CREATE INDEX IF NOT EXISTS idx_org_tasks_list     ON bps.org_tasks (list_id, is_completed, position) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_org_tasks_parent   ON bps.org_tasks (parent_task_id) WHERE parent_task_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_org_tasks_assigned ON bps.org_tasks (tenant_id, assigned_user_id) WHERE assigned_user_id IS NOT NULL AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_org_tasks_due      ON bps.org_tasks (tenant_id, due_date) WHERE due_date IS NOT NULL AND NOT is_completed AND deleted_at IS NULL;

DROP TRIGGER IF EXISTS trg_org_task_lists_set_updated ON bps.org_task_lists;
CREATE TRIGGER trg_org_task_lists_set_updated BEFORE UPDATE ON bps.org_task_lists
  FOR EACH ROW EXECUTE FUNCTION bps.fn_set_updated_at_ts_only();
DROP TRIGGER IF EXISTS trg_org_tasks_set_updated ON bps.org_tasks;
CREATE TRIGGER trg_org_tasks_set_updated BEFORE UPDATE ON bps.org_tasks
  FOR EACH ROW EXECUTE FUNCTION bps.fn_set_updated_at_ts_only();

-- ── Row security (the org_task* functions are SECURITY DEFINER and check access themselves) ──
-- A list is visible to its owner, or to everyone with Tasks access when shared. A task is visible when its list is,
-- or when it is assigned to the caller.
ALTER TABLE bps.org_task_lists ENABLE ROW LEVEL SECURITY;
ALTER TABLE bps.org_tasks      ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON bps.org_task_lists, bps.org_tasks TO authenticated;

DROP POLICY IF EXISTS pol_org_task_lists_read ON bps.org_task_lists;
CREATE POLICY pol_org_task_lists_read ON bps.org_task_lists FOR SELECT TO authenticated USING (
  (SELECT bps.fnd_is_trusted())
  OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('organizer.tasks', 'R'))
      AND (is_shared OR owner_user_id = (SELECT bps.fnd_current_user_id()))));

DROP POLICY IF EXISTS pol_org_tasks_read ON bps.org_tasks;
CREATE POLICY pol_org_tasks_read ON bps.org_tasks FOR SELECT TO authenticated USING (
  (SELECT bps.fnd_is_trusted())
  OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('organizer.tasks', 'R'))
      AND (assigned_user_id = (SELECT bps.fnd_current_user_id())
           OR EXISTS (SELECT 1 FROM bps.org_task_lists l WHERE l.list_id = org_tasks.list_id
                         AND (l.is_shared OR l.owner_user_id = (SELECT bps.fnd_current_user_id()))))));
