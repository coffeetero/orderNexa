/** Organizer › Tasks: shapes returned by the org_task* database functions, and the reorder targets for drag and keyboard. */

export type DueGroup = 'OVERDUE' | 'TODAY' | 'TOMORROW' | 'NEXT_7_DAYS' | 'LATER' | 'NONE';
export type RepeatUnit = 'DAY' | 'WEEK' | 'MONTH' | 'YEAR';
export type SortMode = 'MY_ORDER' | 'DATE' | 'STARRED';
export type TaskView = 'LIST' | 'UPCOMING' | 'STARRED' | 'ASSIGNED';

export interface TaskRepeat { unit: RepeatUnit; interval: number; weekdays: number[] | null; starts_on: string; ends_on: string | null }

/** One task (org_task_json). Dates and labels are worked out in the database in the tenant's time zone. */
export interface TaskItem {
  task_id: number; list_id: number; parent_task_id: number | null;
  title: string; details: string | null;
  due_date: string | null; due_time: string | null; due_group: DueGroup; due_label: string | null;
  is_starred: boolean; starred_at: string | null;
  assigned_user_id: number | null; assigned_name: string | null;
  position: number; is_completed: boolean; completed_at: string | null; completed_label: string | null;
  repeat: TaskRepeat | null; repeat_label: string | null; next_due_label: string | null;
  list_name: string; list_is_shared: boolean; parent_title: string | null;
  subtask_count: number; subtask_done: number; subtasks: TaskItem[];
  created_by_name: string | null; created_label: string | null;
}

export interface TaskList {
  list_id: number; list_name: string; is_shared: boolean; is_default: boolean; is_mine: boolean;
  owner_name: string | null; sort_mode: SortMode; open_count: number; overdue_count: number;
}

/** org_task_lists_get */
export interface TaskRail {
  me: number;
  lists: TaskList[];
  views: { due_now: number; overdue: number; starred: number; assigned: number };
  users: { user_id: number; user_name: string }[];
}

/** org_tasks_get */
export interface TaskPage {
  view: TaskView;
  list: (Omit<TaskList, 'open_count' | 'overdue_count'>) | null;
  tasks: TaskItem[];
  completed: TaskItem[];
}

export const DUE_GROUP_LABEL: Record<DueGroup, string> = {
  OVERDUE: 'Overdue', TODAY: 'Today', TOMORROW: 'Tomorrow', NEXT_7_DAYS: 'Next 7 days', LATER: 'Later', NONE: 'No date',
};

/** Groups rows by due_group, keeping their order (the database sorts by date). */
export function groupByDue(tasks: TaskItem[]): { group: DueGroup; items: TaskItem[] }[] {
  const out: { group: DueGroup; items: TaskItem[] }[] = [];
  for (const t of tasks) {
    const last = out[out.length - 1];
    if (last && last.group === t.due_group) last.items.push(t);
    else out.push({ group: t.due_group, items: [t] });
  }
  return out;
}

/** Finds a task (main or subtask) in a page. */
export function findTask(tasks: TaskItem[], id: number): TaskItem | null {
  for (const t of tasks) {
    if (t.task_id === id) return t;
    const s = t.subtasks.find((x) => x.task_id === id);
    if (s) return s;
  }
  return null;
}

export interface MoveTarget { parent_task_id: number | null; index: number }

/** The open siblings of a task: the list's open main tasks, or its parent's open subtasks. */
function siblingsOf(tasks: TaskItem[], t: TaskItem): TaskItem[] {
  if (t.parent_task_id === null) return tasks.filter((x) => !x.is_completed);
  const p = tasks.find((x) => x.task_id === t.parent_task_id);
  return (p?.subtasks ?? []).filter((x) => !x.is_completed);
}

/** Keyboard reorder (Alt+Up/Down, Alt+Right indent, Alt+Left outdent) in "My order". null when the move is not possible. */
export function keyMove(tasks: TaskItem[], id: number, action: 'up' | 'down' | 'indent' | 'outdent'): MoveTarget | null {
  const t = findTask(tasks, id);
  if (!t || t.is_completed) return null;
  const sib = siblingsOf(tasks, t);
  const pos = sib.findIndex((x) => x.task_id === id);
  if (action === 'up') return pos > 0 ? { parent_task_id: t.parent_task_id, index: pos - 1 } : null;
  if (action === 'down') return pos >= 0 && pos < sib.length - 1 ? { parent_task_id: t.parent_task_id, index: pos + 1 } : null;
  if (action === 'indent') {
    if (t.parent_task_id !== null || pos <= 0 || t.subtask_count > 0 || t.repeat) return null;
    const parent = sib[pos - 1];
    return { parent_task_id: parent.task_id, index: parent.subtasks.filter((x) => !x.is_completed).length };
  }
  if (t.parent_task_id === null) return null;
  const mains = tasks.filter((x) => !x.is_completed);
  return { parent_task_id: null, index: mains.findIndex((x) => x.task_id === t.parent_task_id) + 1 };
}

/** Drag and drop: dropping `dragId` before or after `targetId` puts it among the target's siblings. */
export function dropTarget(tasks: TaskItem[], dragId: number, targetId: number, after: boolean): MoveTarget | null {
  if (dragId === targetId) return null;
  const drag = findTask(tasks, dragId);
  const target = findTask(tasks, targetId);
  if (!drag || !target || drag.is_completed || target.is_completed) return null;
  if (target.parent_task_id !== null && (drag.subtask_count > 0 || drag.repeat || target.parent_task_id === dragId)) return null;
  const ids = siblingsOf(tasks, target).map((x) => x.task_id).filter((x) => x !== dragId);
  return { parent_task_id: target.parent_task_id, index: ids.indexOf(targetId) + (after ? 1 : 0) };
}

/** Initials for an assignee badge. */
export function initialsOf(name: string | null): string {
  const parts = (name ?? '').replace(/[^\p{L}\p{N} ]/gu, ' ').trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return '?';
  return (parts[0][0] + (parts.length > 1 ? parts[parts.length - 1][0] : '')).toUpperCase();
}
