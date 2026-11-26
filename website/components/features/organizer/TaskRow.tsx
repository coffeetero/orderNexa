'use client';

import type { DragEvent, KeyboardEvent } from 'react';
import { Check, GripVertical, ListTree, Repeat, Star } from 'lucide-react';
import { cn } from '@/lib/utils';
import { initialsOf, type TaskItem } from '@/lib/organizer/tasks';

/** The round complete / not complete button. */
export function TaskCheck({ task, onToggle, disabled, small }: { task: TaskItem; onToggle: () => void; disabled?: boolean; small?: boolean }) {
  return (
    <button type="button" disabled={disabled} tabIndex={-1} aria-label={task.is_completed ? `Mark "${task.title}" not done` : `Mark "${task.title}" done`}
      onClick={(e) => { e.stopPropagation(); onToggle(); }}
      className={cn('grid shrink-0 place-items-center rounded-full border-2 transition-colors disabled:cursor-default',
        small ? 'h-4 w-4' : 'mt-0.5 h-[18px] w-[18px]',
        task.is_completed ? 'border-primary bg-primary text-primary-foreground' : 'border-input hover:border-primary')}>
      {task.is_completed && <Check className={small ? 'h-2.5 w-2.5' : 'h-3 w-3'} strokeWidth={3} />}
    </button>
  );
}

const dueClass = (t: TaskItem) =>
  t.is_completed ? '' : t.due_group === 'OVERDUE' ? 'font-medium text-destructive' : t.due_group === 'TODAY' ? 'font-medium text-warning' : '';

/** One task in the list: drag handle, check, title with its date / repeat / subtasks / list, assignee, star. */
export function TaskRow({
  task, selected, showList, draggable, canEdit, dropMark,
  onSelect, onToggle, onStar, onKeyDown, onDragStart, onDragOver, onDrop, onDragEnd,
}: {
  task: TaskItem; selected: boolean; showList: boolean; draggable: boolean; canEdit: boolean; dropMark: 'before' | 'after' | null;
  onSelect: () => void; onToggle: () => void; onStar: () => void;
  onKeyDown: (e: KeyboardEvent<HTMLDivElement>) => void;
  onDragStart: (e: DragEvent<HTMLDivElement>) => void;
  onDragOver: (e: DragEvent<HTMLDivElement>) => void;
  onDrop: (e: DragEvent<HTMLDivElement>) => void;
  onDragEnd: () => void;
}) {
  const isSub = task.parent_task_id !== null;
  return (
    <div
      role="option" aria-selected={selected} tabIndex={selected ? 0 : -1} data-task-id={task.task_id}
      draggable={draggable} onDragStart={onDragStart} onDragOver={onDragOver} onDrop={onDrop} onDragEnd={onDragEnd}
      onClick={onSelect} onKeyDown={onKeyDown}
      className={cn('group relative flex cursor-pointer items-start gap-2 border-b py-1.5 pr-3 text-sm outline-none hover:bg-muted/40 focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring',
        isSub && !showList ? 'pl-10' : 'pl-1',
        selected && 'bg-accent shadow-[inset_3px_0_0_hsl(var(--primary))] hover:bg-accent')}>
      {dropMark && <span className={cn('pointer-events-none absolute inset-x-0 h-0.5 bg-primary', dropMark === 'before' ? '-top-px' : '-bottom-px')} />}
      <span className={cn('mt-0.5 w-4 shrink-0 text-muted-foreground', draggable ? 'cursor-grab opacity-0 group-hover:opacity-100' : 'invisible')} aria-hidden>
        <GripVertical className="h-4 w-4" />
      </span>
      <TaskCheck task={task} disabled={!canEdit} onToggle={onToggle} />
      <span className="min-w-0 flex-1">
        <span className={cn('block break-words', task.is_completed && 'text-muted-foreground line-through')}>{task.title}</span>
        {(task.due_label || task.repeat || task.subtask_count > 0 || showList || task.completed_label || (task.details && !task.is_completed)) && (
          <span className="mt-0.5 flex flex-wrap items-center gap-x-3 gap-y-0.5 text-xs text-muted-foreground">
            {task.is_completed && task.completed_label ? <span>{task.completed_label}</span>
              : task.due_label && <span className={dueClass(task)}>{task.due_label}</span>}
            {task.repeat && <span className="inline-flex items-center" title={task.repeat_label ?? 'Repeats'}><Repeat className="h-3 w-3" aria-label="Repeats" /></span>}
            {task.subtask_count > 0 && (
              <span className="inline-flex items-center gap-0.5 tabular-nums" title="Subtasks done"><ListTree className="h-3 w-3" aria-hidden />{task.subtask_done}/{task.subtask_count}</span>
            )}
            {showList && <span className="truncate">{isSub && task.parent_title ? `${task.list_name} › ${task.parent_title}` : task.list_name}</span>}
            {!showList && task.details && !task.is_completed && <span className="max-w-[24rem] truncate">{task.details}</span>}
          </span>
        )}
      </span>
      {task.assigned_user_id !== null && (
        <span title={`Assigned to ${task.assigned_name ?? ''}`} aria-label={`Assigned to ${task.assigned_name ?? ''}`}
          className="-mt-0.5 grid h-6 w-6 shrink-0 place-items-center rounded-full bg-muted text-xs font-semibold text-muted-foreground">
          {initialsOf(task.assigned_name)}
        </span>
      )}
      {!task.is_completed && (
        <button type="button" tabIndex={-1} disabled={!canEdit} aria-label={task.is_starred ? 'Remove star' : 'Star'} aria-pressed={task.is_starred}
          onClick={(e) => { e.stopPropagation(); onStar(); }}
          className={cn('mt-px shrink-0', task.is_starred ? 'text-warning' : 'text-muted-foreground opacity-0 hover:text-foreground group-hover:opacity-100 group-focus-visible:opacity-100 [@media(hover:none)]:opacity-100')}>
          <Star className={cn('h-4 w-4', task.is_starred && 'fill-current')} />
        </button>
      )}
    </div>
  );
}
