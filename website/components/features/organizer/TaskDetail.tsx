'use client';

import { useEffect, useState } from 'react';
import { ChevronLeft, Plus, Repeat, Star, Trash2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { cn } from '@/lib/utils';
import type { RepeatUnit, TaskItem, TaskList, TaskRail } from '@/lib/organizer/tasks';
import { TaskCheck } from './TaskRow';

const selectCls = 'h-9 w-full rounded-md border border-input bg-background px-2 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring';
const WEEKDAYS = [{ d: 1, l: 'M', n: 'Monday' }, { d: 2, l: 'T', n: 'Tuesday' }, { d: 3, l: 'W', n: 'Wednesday' }, { d: 4, l: 'T', n: 'Thursday' },
  { d: 5, l: 'F', n: 'Friday' }, { d: 6, l: 'S', n: 'Saturday' }, { d: 7, l: 'S', n: 'Sunday' }];
const UNITS: { v: RepeatUnit; one: string; many: string }[] = [
  { v: 'DAY', one: 'day', many: 'days' }, { v: 'WEEK', one: 'week', many: 'weeks' },
  { v: 'MONTH', one: 'month', many: 'months' }, { v: 'YEAR', one: 'year', many: 'years' },
];

type Patch = Record<string, unknown>;

/** The details pane: every field saves on its own when it changes (as in Google Tasks). */
export function TaskDetail({ task, rail, lists, canEdit, onSave, onToggle, onDelete, onOpen, onAddSubtask }: {
  task: TaskItem; rail: TaskRail; lists: TaskList[]; canEdit: boolean;
  onSave: (patch: Patch) => void;
  onToggle: (t: TaskItem) => void;
  onDelete: (t: TaskItem) => void;
  onOpen: (id: number) => void;
  onAddSubtask: (title: string) => void;
}) {
  const [title, setTitle] = useState(task.title);
  const [details, setDetails] = useState(task.details ?? '');
  const [sub, setSub] = useState('');
  const [every, setEvery] = useState(String(task.repeat?.interval ?? 1));
  useEffect(() => { setTitle(task.title); setDetails(task.details ?? ''); setEvery(String(task.repeat?.interval ?? 1)); }, [task]);

  const r = task.repeat;
  const isSub = task.parent_task_id !== null;
  const ro = !canEdit;
  const saveRepeat = (next: Partial<{ unit: RepeatUnit; interval: number; weekdays: number[] | null; ends_on: string | null }> | null) => {
    if (next === null) { onSave({ repeat: null }); return; }
    const base = { unit: r?.unit ?? 'WEEK', interval: r?.interval ?? 1, weekdays: r?.weekdays ?? null, ends_on: r?.ends_on ?? null };
    onSave({ repeat: { ...base, ...next } });
  };
  // No weekdays saved means the weekday of the series' first date.
  const days = r?.weekdays ?? (r ? [new Date(`${r.starts_on}T00:00:00`).getDay() || 7] : []);
  const toggleDay = (d: number) => {
    const cur = days;
    const next = cur.includes(d) ? cur.filter((x) => x !== d) : [...cur, d].sort();
    saveRepeat({ weekdays: next.length ? next : null });
  };

  return (
    <div className="flex h-full min-h-0 flex-col">
      <div className="flex h-10 shrink-0 items-center gap-1 border-b px-3">
        {isSub ? (
          <button type="button" className="flex min-w-0 items-center gap-1 text-xs font-medium text-primary hover:underline" onClick={() => onOpen(task.parent_task_id as number)}>
            <ChevronLeft className="h-4 w-4 shrink-0" /><span className="truncate">{task.parent_title}</span>
          </button>
        ) : <h2 className="text-sm font-semibold">Details</h2>}
        <span className="flex-1" />
        <Button variant="ghost" size="sm" className="h-8 w-8 p-0" disabled={ro} aria-pressed={task.is_starred}
          aria-label={task.is_starred ? 'Remove star' : 'Star'} onClick={() => onSave({ is_starred: !task.is_starred })}>
          <Star className={cn('h-4 w-4', task.is_starred ? 'fill-current text-warning' : 'text-muted-foreground')} />
        </Button>
      </div>

      <div className="flex-1 space-y-3 overflow-y-auto p-3">
        <div className="flex items-start gap-2">
          <TaskCheck task={task} disabled={ro} onToggle={() => onToggle(task)} />
          <input id="task-title" aria-label="Title" value={title} readOnly={ro} maxLength={500}
            className={cn('w-full border-0 border-b border-transparent bg-transparent pb-1 text-base font-semibold focus:border-ring focus:outline-none',
              task.is_completed && 'text-muted-foreground line-through')}
            onChange={(e) => setTitle(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') (e.target as HTMLInputElement).blur(); if (e.key === 'Escape') { setTitle(task.title); (e.target as HTMLInputElement).blur(); } }}
            onBlur={() => { if (title.trim() && title !== task.title) onSave({ title }); else setTitle(task.title); }} />
        </div>

        <div>
          <label htmlFor="task-details" className="mb-1 block text-xs font-medium text-muted-foreground">Details</label>
          <Textarea id="task-details" rows={3} value={details} readOnly={ro} placeholder="Add details" className="min-h-[4.5rem] text-sm"
            onChange={(e) => setDetails(e.target.value)} onBlur={() => { if (details !== (task.details ?? '')) onSave({ details }); }} />
        </div>

        <div className="grid grid-cols-[1fr_7.5rem] gap-2">
          <div>
            <label htmlFor="task-date" className="mb-1 block text-xs font-medium text-muted-foreground">Date</label>
            <Input id="task-date" type="date" className="h-9" value={task.due_date ?? ''} readOnly={ro}
              onChange={(e) => onSave({ due_date: e.target.value || null })} />
          </div>
          <div>
            <label htmlFor="task-time" className="mb-1 block text-xs font-medium text-muted-foreground">Time</label>
            <Input id="task-time" type="time" className="h-9" value={task.due_time ?? ''} readOnly={ro} disabled={!task.due_date}
              onChange={(e) => onSave({ due_time: e.target.value || null })} />
          </div>
        </div>
        {task.due_label && !task.is_completed && (
          <p className={cn('-mt-1 text-xs', task.due_group === 'OVERDUE' ? 'text-destructive' : task.due_group === 'TODAY' ? 'text-warning' : 'text-muted-foreground')}>
            {task.due_group === 'OVERDUE' ? 'Overdue · ' : ''}{task.due_label}
          </p>
        )}

        {!isSub && (
          <div className="space-y-1.5">
            <label htmlFor="task-repeat" className="block text-xs font-medium text-muted-foreground">Repeat</label>
            <div className="grid grid-cols-[4.5rem_1fr] gap-2">
              <Input id="task-interval" aria-label="Repeat every" type="number" min={1} max={999} className="h-9" value={every}
                disabled={!r || ro} onChange={(e) => setEvery(e.target.value)}
                onBlur={() => { const n = Number(every); if (r && n >= 1 && n <= 999 && n !== r.interval) saveRepeat({ interval: n }); else setEvery(String(r?.interval ?? 1)); }} />
              <select id="task-repeat" className={selectCls} value={r?.unit ?? ''} disabled={ro}
                onChange={(e) => (e.target.value ? saveRepeat({ unit: e.target.value as RepeatUnit, weekdays: null }) : saveRepeat(null))}>
                <option value="">Does not repeat</option>
                {UNITS.map((u) => <option key={u.v} value={u.v}>{(r?.interval ?? 1) === 1 ? u.one : u.many}</option>)}
              </select>
            </div>
            {r?.unit === 'WEEK' && (
              <div className="flex gap-1" role="group" aria-label="Repeat on">
                {WEEKDAYS.map((w) => {
                  const on = days.includes(w.d);
                  return (
                    <button key={w.d} type="button" disabled={ro} aria-pressed={on} aria-label={w.n} title={w.n} onClick={() => toggleDay(w.d)}
                      className={cn('h-8 w-8 rounded-full border text-xs font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                        on ? 'border-primary bg-primary text-primary-foreground' : 'border-input bg-background hover:bg-accent')}>{w.l}</button>
                  );
                })}
              </div>
            )}
            {r && (
              <div className="grid grid-cols-[auto_1fr] items-center gap-2">
                <label htmlFor="task-ends" className="text-xs text-muted-foreground">Ends</label>
                <Input id="task-ends" type="date" className="h-9" value={r.ends_on ?? ''} readOnly={ro}
                  onChange={(e) => saveRepeat({ ends_on: e.target.value || null })} />
              </div>
            )}
            {task.repeat_label && (
              <p className="flex items-center gap-1 text-xs text-muted-foreground">
                <Repeat className="h-3 w-3" />{task.repeat_label}{task.next_due_label ? ` · next: ${task.next_due_label}` : ''}
              </p>
            )}
          </div>
        )}

        <div className="grid grid-cols-2 gap-2">
          {!isSub && (
            <div>
              <label htmlFor="task-list" className="mb-1 block text-xs font-medium text-muted-foreground">List</label>
              <select id="task-list" className={selectCls} value={task.list_id} disabled={ro} onChange={(e) => onSave({ list_id: Number(e.target.value) })}>
                {!lists.some((l) => l.list_id === task.list_id) && <option value={task.list_id}>{task.list_name}</option>}
                {lists.map((l) => <option key={l.list_id} value={l.list_id}>{l.list_name}{l.is_shared ? ' (shared)' : ''}</option>)}
              </select>
            </div>
          )}
          <div className={cn(isSub && 'col-span-2')}>
            <label htmlFor="task-assignee" className="mb-1 block text-xs font-medium text-muted-foreground">Assigned to</label>
            <select id="task-assignee" className={selectCls} value={task.assigned_user_id ?? ''} disabled={ro}
              onChange={(e) => onSave({ assigned_user_id: e.target.value ? Number(e.target.value) : null })}>
              <option value="">Nobody</option>
              {task.assigned_user_id !== null && !rail.users.some((u) => u.user_id === task.assigned_user_id) && (
                <option value={task.assigned_user_id}>{task.assigned_name ?? 'Former user'}</option>
              )}
              {rail.users.map((u) => <option key={u.user_id} value={u.user_id}>{u.user_id === rail.me ? `${u.user_name} (me)` : u.user_name}</option>)}
            </select>
          </div>
        </div>

        {!isSub && (
          <div>
            <div className="mb-1 flex items-baseline justify-between">
              <span className="text-xs font-medium text-muted-foreground">Subtasks</span>
              {task.subtask_count > 0 && <span className="text-xs tabular-nums text-muted-foreground">{task.subtask_done} of {task.subtask_count} done</span>}
            </div>
            <ul className="rounded-md border">
              {task.subtasks.map((s) => (
                <li key={s.task_id} className="flex items-center gap-2 border-b px-2 py-1.5 last:border-b-0">
                  <TaskCheck task={s} small disabled={ro} onToggle={() => onToggle(s)} />
                  <button type="button" className={cn('min-w-0 flex-1 truncate text-left text-sm hover:underline', s.is_completed && 'text-muted-foreground line-through')}
                    onClick={() => onOpen(s.task_id)}>{s.title}</button>
                  {s.due_label && !s.is_completed && <span className={cn('shrink-0 text-xs', s.due_group === 'OVERDUE' ? 'text-destructive' : 'text-muted-foreground')}>{s.due_label}</span>}
                </li>
              ))}
              {canEdit && (
                <li className="flex items-center gap-2 px-2 py-1">
                  <Plus className="h-4 w-4 shrink-0 text-primary" />
                  <input id="task-add-subtask" aria-label="Add a subtask" placeholder="Add a subtask, press Enter" value={sub} maxLength={500}
                    className="h-7 w-full bg-transparent text-sm placeholder:text-muted-foreground focus:outline-none"
                    onChange={(e) => setSub(e.target.value)}
                    onKeyDown={(e) => { if (e.key === 'Enter' && sub.trim()) { onAddSubtask(sub.trim()); setSub(''); } }} />
                </li>
              )}
            </ul>
          </div>
        )}
      </div>

      <div className="flex shrink-0 items-center gap-2 border-t px-3 py-2 text-xs text-muted-foreground">
        <span className="min-w-0 flex-1 truncate">
          {task.is_completed && task.completed_label ? `${task.completed_label} · ` : ''}
          Added {task.created_label}{task.created_by_name ? ` by ${task.created_by_name}` : ''}
        </span>
        {canEdit && (
          <Button variant="outline" size="sm" className="h-8 text-destructive" onClick={() => onDelete(task)}>
            <Trash2 className="mr-1 h-4 w-4" />Delete
          </Button>
        )}
      </div>
    </div>
  );
}
