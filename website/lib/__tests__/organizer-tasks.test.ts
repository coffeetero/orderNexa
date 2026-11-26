import { describe, expect, it } from 'vitest';
import { dropTarget, findTask, groupByDue, initialsOf, keyMove, type TaskItem } from '@/lib/organizer/tasks';

const task = (id: number, extra: Partial<TaskItem> = {}): TaskItem => ({
  task_id: id, list_id: 1, parent_task_id: null, title: `T${id}`, details: null, due_date: null, due_time: null, due_group: 'NONE', due_label: null,
  is_starred: false, starred_at: null, assigned_user_id: null, assigned_name: null, position: id, is_completed: false, completed_at: null,
  completed_label: null, repeat: null, repeat_label: null, next_due_label: null, list_name: 'My Tasks', list_is_shared: false, parent_title: null,
  subtask_count: 0, subtask_done: 0, subtasks: [], created_by_name: null, created_label: null, ...extra,
});

// 1, 2 (with subtasks 21, 22 and done 23), 3 (repeats), 4
const tasks: TaskItem[] = [
  task(1),
  task(2, { subtask_count: 3, subtask_done: 1, subtasks: [task(21, { parent_task_id: 2 }), task(22, { parent_task_id: 2 }), task(23, { parent_task_id: 2, is_completed: true })] }),
  task(3, { repeat: { unit: 'DAY', interval: 1, weekdays: null, starts_on: '2026-11-25', ends_on: null } }),
  task(4),
];

describe('tasks keyboard moves', () => {
  it('up / down among siblings, not past the ends', () => {
    expect(keyMove(tasks, 2, 'up')).toEqual({ parent_task_id: null, index: 0 });
    expect(keyMove(tasks, 1, 'up')).toBeNull();
    expect(keyMove(tasks, 4, 'down')).toBeNull();
    expect(keyMove(tasks, 21, 'down')).toEqual({ parent_task_id: 2, index: 1 });
    expect(keyMove(tasks, 22, 'down')).toBeNull(); // the completed subtask does not count
  });
  it('indent under the task above, at the end of its open subtasks', () => {
    expect(keyMove(tasks, 4, 'indent')).toEqual({ parent_task_id: 3, index: 0 });
    expect(keyMove(tasks, 1, 'indent')).toBeNull(); // nothing above
    expect(keyMove(tasks, 2, 'indent')).toBeNull(); // has subtasks
    expect(keyMove(tasks, 3, 'indent')).toBeNull(); // repeats
    expect(keyMove(tasks, 21, 'indent')).toBeNull(); // already a subtask
  });
  it('outdent puts a subtask right after its parent', () => {
    expect(keyMove(tasks, 22, 'outdent')).toEqual({ parent_task_id: null, index: 2 });
    expect(keyMove(tasks, 1, 'outdent')).toBeNull();
  });
});

describe('tasks drag and drop', () => {
  it('drops before / after a main task', () => {
    expect(dropTarget(tasks, 4, 1, false)).toEqual({ parent_task_id: null, index: 0 });
    expect(dropTarget(tasks, 1, 3, true)).toEqual({ parent_task_id: null, index: 2 });
  });
  it('dropping on a subtask makes it a subtask, unless it has subtasks or repeats', () => {
    expect(dropTarget(tasks, 4, 21, true)).toEqual({ parent_task_id: 2, index: 1 });
    expect(dropTarget(tasks, 2, 21, true)).toBeNull();
    expect(dropTarget(tasks, 3, 21, false)).toBeNull();
    expect(dropTarget(tasks, 1, 1, false)).toBeNull();
  });
});

describe('tasks helpers', () => {
  it('finds subtasks, groups by due date in order, makes initials', () => {
    expect(findTask(tasks, 22)?.title).toBe('T22');
    const g = groupByDue([task(1, { due_group: 'OVERDUE' }), task(2, { due_group: 'OVERDUE' }), task(3, { due_group: 'TODAY' })]);
    expect(g.map((x) => [x.group, x.items.length])).toEqual([['OVERDUE', 2], ['TODAY', 1]]);
    expect(initialsOf('Maria de la Cruz')).toBe('MC');
    expect(initialsOf(null)).toBe('?');
  });
});
