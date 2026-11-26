'use client';

import { Fragment, useCallback, useEffect, useMemo, useRef, useState, type DragEvent, type KeyboardEvent } from 'react';
import { toast } from 'sonner';
import { CalendarClock, ChevronDown, ChevronRight, List, MoreHorizontal, Plus, Star, UserRound, Users } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuRadioGroup, DropdownMenuRadioItem, DropdownMenuSeparator, DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import { Sheet, SheetContent, SheetTitle } from '@/components/ui/sheet';
import { cn } from '@/lib/utils';
import {
  DUE_GROUP_LABEL, dropTarget, findTask, groupByDue, keyMove,
  type MoveTarget, type SortMode, type TaskItem, type TaskPage, type TaskRail, type TaskView,
} from '@/lib/organizer/tasks';
import { api } from './contacts-ui';
import { TaskRow } from './TaskRow';
import { TaskDetail } from './TaskDetail';

type Sel = { view: Exclude<TaskView, 'LIST'> } | { view: 'LIST'; listId: number };
const SEL_KEY = 'bps.tasks.sel';
const DONE_KEY = 'bps.tasks.completed-open';
const SORTS: { v: SortMode; l: string }[] = [{ v: 'MY_ORDER', l: 'My order' }, { v: 'DATE', l: 'Date' }, { v: 'STARRED', l: 'Starred' }];
const VIEWS = [
  { view: 'UPCOMING' as const, label: 'Upcoming', icon: CalendarClock, empty: 'Nothing has a date yet. Give a task a date to see it here.' },
  { view: 'STARRED' as const, label: 'Starred', icon: Star, empty: 'No starred tasks. Star a task to see it here.' },
  { view: 'ASSIGNED' as const, label: 'Assigned to me', icon: UserRound, empty: 'Nothing is assigned to you.' },
];

const store = {
  get(k: string): string | null { try { return window.localStorage.getItem(k); } catch { return null; } },
  set(k: string, v: string) { try { window.localStorage.setItem(k, v); } catch { /* storage unavailable */ } },
};

function useWide(): boolean {
  const [wide, setWide] = useState(true);
  useEffect(() => {
    const m = window.matchMedia('(min-width: 1280px)');
    const on = () => setWide(m.matches);
    on();
    m.addEventListener('change', on);
    return () => m.removeEventListener('change', on);
  }, []);
  return wide;
}

export function TasksBoard({ tenantId, canEdit }: { tenantId: number; canEdit: boolean }) {
  const [rail, setRail] = useState<TaskRail | null>(null);
  const [sel, setSel] = useState<Sel | null>(null);
  const [page, setPage] = useState<TaskPage | null>(null);
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [sheetOpen, setSheetOpen] = useState(false);
  const [doneOpen, setDoneOpen] = useState(false);
  const [quick, setQuick] = useState('');
  const [listDialog, setListDialog] = useState<{ mode: 'new' | 'rename'; name: string; shared: boolean } | null>(null);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [drag, setDrag] = useState<{ id: number; overId: number | null; after: boolean } | null>(null);
  const focusAfter = useRef<number | null>(null);
  const addChain = useRef<Promise<void>>(Promise.resolve());
  const wide = useWide();
  const tasksUrl = '/api/organizer/tasks';

  const loadRail = useCallback(() => api<TaskRail>(`${tasksUrl}/lists?tenant_id=${tenantId}`)
    .then((r) => { setRail(r); return r; })
    .catch((e: Error) => { toast.error(e.message); return null; }), [tenantId]);

  const loadPage = useCallback((s: Sel) => {
    const q = s.view === 'LIST' ? `view=LIST&list_id=${s.listId}` : `view=${s.view}`;
    return api<TaskPage>(`${tasksUrl}?tenant_id=${tenantId}&${q}`).then(setPage).catch((e: Error) => toast.error(e.message));
  }, [tenantId]);

  // First load: the rail, then the remembered view or My Tasks.
  useEffect(() => {
    setDoneOpen(store.get(DONE_KEY) === '1');
    loadRail().then((r) => {
      if (!r) return;
      let s: Sel | null = null;
      try { s = JSON.parse(store.get(SEL_KEY) ?? 'null') as Sel | null; } catch { s = null; }
      const saved = s;
      if (!saved || (saved.view === 'LIST' && !r.lists.some((l) => l.list_id === saved.listId))) {
        s = { view: 'LIST', listId: (r.lists.find((l) => l.is_default) ?? r.lists[0]).list_id };
      }
      setSel(s);
    });
  }, [loadRail]);
  useEffect(() => { if (sel) { setPage(null); loadPage(sel); store.set(SEL_KEY, JSON.stringify(sel)); } }, [sel, loadPage]);

  const refresh = useCallback(() => { if (sel) loadPage(sel); loadRail(); }, [sel, loadPage, loadRail]);

  const choose = (s: Sel) => { setSelectedId(null); setSheetOpen(false); setSel(s); };
  const list = page?.list ?? null;
  const sortMode: SortMode = list?.sort_mode ?? 'MY_ORDER';
  const canReorder = canEdit && page?.view === 'LIST' && sortMode === 'MY_ORDER';
  const showList = page !== null && page.view !== 'LIST';
  const tasks = useMemo(() => page?.tasks ?? [], [page]);
  const completed = useMemo(() => page?.completed ?? [], [page]);
  const selected = selectedId === null ? null : findTask(tasks, selectedId) ?? findTask(completed, selectedId);

  // Rows in screen order (open subtasks under their task in a list; flat in the cross-list views).
  const rows = useMemo(() => {
    const out: TaskItem[] = [];
    for (const t of tasks) {
      out.push(t);
      if (page?.view === 'LIST') for (const s of t.subtasks) if (!s.is_completed) out.push(s);
    }
    return out;
  }, [tasks, page]);
  const visible = useMemo(() => (doneOpen ? [...rows, ...completed] : rows), [rows, completed, doneOpen]);
  const grouped = page?.view === 'UPCOMING' || (page?.view === 'LIST' && sortMode === 'DATE');

  useEffect(() => {
    if (focusAfter.current === null) return;
    const el = document.querySelector<HTMLElement>(`[data-task-id="${focusAfter.current}"]`);
    if (el) { el.focus(); focusAfter.current = null; }
  });

  const patchLocal = (id: number, fn: (t: TaskItem) => TaskItem) => setPage((p) => p && {
    ...p,
    tasks: p.tasks.map((t) => (t.task_id === id ? fn(t) : { ...t, subtasks: t.subtasks.map((s) => (s.task_id === id ? fn(s) : s)) })),
    completed: p.completed.map((t) => (t.task_id === id ? fn(t) : { ...t, subtasks: t.subtasks.map((s) => (s.task_id === id ? fn(s) : s)) })),
  });

  const fail = (e: unknown) => { toast.error((e as Error).message); };

  const save = async (patch: Record<string, unknown>) => {
    try { await api(tasksUrl, 'POST', { tenant_id: tenantId, task: patch }); } catch (e) { fail(e); }
    refresh();
  };

  const toggle = async (t: TaskItem) => {
    if (!canEdit) return;
    patchLocal(t.task_id, (x) => ({ ...x, is_completed: !x.is_completed }));
    try {
      const r = await api<{ next_due_label?: string | null }>(`${tasksUrl}/${t.task_id}`, 'PATCH', { tenant_id: tenantId, completed: !t.is_completed });
      if (r.next_due_label) toast.success(`Repeats: next one ${r.next_due_label}`);
    } catch (e) { fail(e); }
    refresh();
  };

  const star = (t: TaskItem) => {
    if (!canEdit) return;
    patchLocal(t.task_id, (x) => ({ ...x, is_starred: !x.is_starred }));
    save({ task_id: t.task_id, is_starred: !t.is_starred });
  };

  /** nextId: the row the keyboard moved to (Delete key); otherwise the selection falls back to the parent task. */
  const remove = async (t: TaskItem, nextId?: number | null) => {
    try {
      await api(`${tasksUrl}/${t.task_id}?tenant_id=${tenantId}`, 'DELETE');
      if (nextId !== undefined) setSelectedId(nextId);
      else if (selectedId === t.task_id) { setSelectedId(t.parent_task_id); if (t.parent_task_id === null) setSheetOpen(false); }
      toast('Task deleted', {
        duration: 8000,
        action: {
          label: 'Undo',
          onClick: () => { api(`${tasksUrl}/${t.task_id}`, 'PATCH', { tenant_id: tenantId, restore: true }).then(refresh).catch(fail); },
        },
      });
    } catch (e) { fail(e); }
    refresh();
  };

  const move = async (id: number, target: MoveTarget | null) => {
    if (!target) return;
    focusAfter.current = id;
    try { await api(`${tasksUrl}/${id}`, 'PATCH', { tenant_id: tenantId, move: target }); } catch (e) { fail(e); }
    refresh();
  };

  const addQuick = () => {
    const title = quick.trim();
    if (!title || !page || !rail) return;
    const task: Record<string, unknown> = { title };
    if (page.view === 'LIST' && list) task.list_id = list.list_id;
    if (page.view === 'STARRED') task.is_starred = true;
    if (page.view === 'ASSIGNED') task.assigned_user_id = rail.me;
    setQuick('');
    // One add at a time, so fast typing keeps the order (each new task goes on top).
    addChain.current = addChain.current.then(() => api(tasksUrl, 'POST', { tenant_id: tenantId, task }).then(refresh, (e) => { fail(e); setQuick(title); }));
  };

  const addSubtask = async (parentId: number, title: string) => {
    try { await api(tasksUrl, 'POST', { tenant_id: tenantId, task: { parent_task_id: parentId, title } }); } catch (e) { fail(e); }
    refresh();
  };

  const open = (id: number) => { setSelectedId(id); if (!wide) setSheetOpen(true); };

  const onRowKey = (t: TaskItem) => (e: KeyboardEvent<HTMLDivElement>) => {
    const i = visible.findIndex((x) => x.task_id === t.task_id);
    const go = (j: number) => { const n = visible[j]; if (n) { setSelectedId(n.task_id); focusAfter.current = n.task_id; } };
    if (e.altKey && ['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(e.key)) {
      e.preventDefault();
      if (canReorder) {
        const a = ({ ArrowUp: 'up', ArrowDown: 'down', ArrowLeft: 'outdent', ArrowRight: 'indent' } as const)[e.key as 'ArrowUp'];
        move(t.task_id, keyMove(tasks, t.task_id, a));
      }
      return;
    }
    if (e.key === 'ArrowDown') { e.preventDefault(); go(i + 1); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); go(i - 1); }
    else if (e.key === 'Enter') { e.preventDefault(); open(t.task_id); }
    else if (e.key === ' ') { e.preventDefault(); toggle(t); }
    else if (e.key.toLowerCase() === 's' && !e.metaKey && !e.ctrlKey && !t.is_completed) { e.preventDefault(); star(t); }
    else if ((e.key === 'Delete' || e.key === 'Backspace') && canEdit) {
      e.preventDefault();
      const j = i + 1 < visible.length ? i + 1 : i - 1;
      go(j);
      remove(t, visible[j]?.task_id ?? null);
    }
  };

  const dragHandlers = (t: TaskItem) => ({
    onDragStart: (e: DragEvent<HTMLDivElement>) => { e.dataTransfer.effectAllowed = 'move'; e.dataTransfer.setData('text/plain', String(t.task_id)); setDrag({ id: t.task_id, overId: null, after: false }); },
    onDragOver: (e: DragEvent<HTMLDivElement>) => {
      if (!drag) return;
      const r = e.currentTarget.getBoundingClientRect();
      const after = e.clientY > r.top + r.height / 2;
      if (!dropTarget(tasks, drag.id, t.task_id, after)) return;
      e.preventDefault();
      if (drag.overId !== t.task_id || drag.after !== after) setDrag({ ...drag, overId: t.task_id, after });
    },
    onDrop: (e: DragEvent<HTMLDivElement>) => {
      e.preventDefault();
      if (drag) move(drag.id, dropTarget(tasks, drag.id, t.task_id, drag.after));
      setDrag(null);
    },
    onDragEnd: () => setDrag(null),
  });

  const renderRow = (t: TaskItem) => (
    <TaskRow key={t.task_id} task={t} selected={selectedId === t.task_id} showList={showList} canEdit={canEdit}
      draggable={canReorder && !t.is_completed}
      dropMark={drag && drag.overId === t.task_id ? (drag.after ? 'after' : 'before') : null}
      onSelect={() => open(t.task_id)} onToggle={() => toggle(t)} onStar={() => star(t)} onKeyDown={onRowKey(t)} {...dragHandlers(t)} />
  );

  const saveList = async (patch: Record<string, unknown>) => {
    try {
      const r = await api<{ list_id: number }>(`${tasksUrl}/lists`, 'POST', { tenant_id: tenantId, list: patch });
      if (!patch.list_id) choose({ view: 'LIST', listId: r.list_id });
      else refresh();
      loadRail();
      return true;
    } catch (e) { fail(e); return false; }
  };
  const clearCompleted = async () => {
    if (!list) return;
    try {
      const r = await api<{ task_count: number }>(`${tasksUrl}/lists`, 'POST', { tenant_id: tenantId, clear_completed: list.list_id });
      toast.success(r.task_count === 1 ? '1 completed task deleted' : `${r.task_count} completed tasks deleted`);
    } catch (e) { fail(e); }
    refresh();
  };
  const deleteList = async () => {
    if (!list || !rail) return;
    try {
      await api(`${tasksUrl}/lists?tenant_id=${tenantId}&id=${list.list_id}`, 'DELETE');
      const def = rail.lists.find((l) => l.is_default);
      if (def) choose({ view: 'LIST', listId: def.list_id });
      loadRail();
    } catch (e) { fail(e); }
  };

  const title = page?.view === 'LIST' ? list?.list_name : VIEWS.find((v) => v.view === page?.view)?.label;
  const subtitle = page?.view === 'LIST' && list
    ? (list.is_shared ? `Shared with the company${list.is_mine ? '' : ` · ${list.owner_name ?? ''}`}` : 'Only you')
    : 'All your lists';
  const selKey = (s: Sel | null) => (s === null ? '' : s.view === 'LIST' ? `L${s.listId}` : s.view);
  const mine = rail?.lists.filter((l) => !l.is_shared) ?? [];
  const shared = rail?.lists.filter((l) => l.is_shared) ?? [];

  const navBtn = (key: string, label: string, Icon: typeof List, count: number, overdue: number, onClick: () => void) => (
    <button key={key} type="button" onClick={onClick} aria-current={selKey(sel) === key ? 'page' : undefined}
      className={cn('flex h-8 w-full items-center gap-2 rounded-md px-2 text-left text-sm hover:bg-muted/60 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
        selKey(sel) === key && 'bg-accent font-medium text-accent-foreground')}>
      <Icon className="h-4 w-4 shrink-0 text-muted-foreground" aria-hidden />
      <span className="min-w-0 flex-1 truncate">{label}</span>
      {overdue > 0 && (
        <span className="h-2 w-2 shrink-0 rounded-full bg-destructive" title={`${overdue} overdue`}><span className="sr-only">{overdue} overdue</span></span>
      )}
      {count > 0 && <span className="text-xs tabular-nums text-muted-foreground">{count}</span>}
    </button>
  );

  const detail = selected && rail ? (
    <TaskDetail key={selected.task_id} task={selected} rail={rail} lists={rail.lists} canEdit={canEdit}
      onSave={(p) => save({ task_id: selected.task_id, ...p })} onToggle={toggle} onDelete={remove} onOpen={open}
      onAddSubtask={(t) => addSubtask(selected.task_id, t)} />
  ) : null;

  return (
    <div className="flex h-[calc(100dvh-7.5rem)] min-h-[32rem] gap-3 p-2 sm:p-3">
      {/* Views and lists */}
      <nav aria-label="Task views and lists" className="hidden w-52 shrink-0 flex-col overflow-y-auto rounded-lg border bg-card p-2 md:flex">
        <h1 className="px-2 pb-2 pt-1 text-lg font-semibold">Tasks</h1>
        {rail && VIEWS.map((v) => navBtn(v.view, v.label, v.icon,
          v.view === 'UPCOMING' ? rail.views.due_now : v.view === 'STARRED' ? rail.views.starred : rail.views.assigned,
          v.view === 'UPCOMING' ? rail.views.overdue : 0, () => choose({ view: v.view })))}
        <div className="mt-3 flex items-center justify-between px-2 pb-1 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
          My lists
          {canEdit && (
            <button type="button" aria-label="New list" title="New list" className="rounded p-0.5 hover:bg-muted hover:text-foreground"
              onClick={() => setListDialog({ mode: 'new', name: '', shared: false })}><Plus className="h-4 w-4" /></button>
          )}
        </div>
        {mine.map((l) => navBtn(`L${l.list_id}`, l.list_name, List, l.open_count, l.overdue_count, () => choose({ view: 'LIST', listId: l.list_id })))}
        {shared.length > 0 && <div className="mt-3 px-2 pb-1 text-xs font-semibold uppercase tracking-wide text-muted-foreground">Company lists</div>}
        {shared.map((l) => navBtn(`L${l.list_id}`, l.list_name, Users, l.open_count, l.overdue_count, () => choose({ view: 'LIST', listId: l.list_id })))}
      </nav>

      {/* Task list */}
      <section aria-label={title ?? 'Tasks'} className="flex min-w-0 flex-1 flex-col rounded-lg border bg-card">
        <div className="flex min-h-10 flex-wrap items-center gap-x-3 gap-y-1 border-b px-3 py-1.5">
          <div className="min-w-0 md:hidden">
            <label htmlFor="tasks-pick" className="sr-only">View or list</label>
            <select id="tasks-pick" className="h-9 max-w-[11rem] rounded-md border border-input bg-background px-2 text-sm font-semibold" value={selKey(sel)}
              onChange={(e) => { const v = e.target.value; choose(v.startsWith('L') ? { view: 'LIST', listId: Number(v.slice(1)) } : { view: v as 'UPCOMING' }); }}>
              {VIEWS.map((v) => <option key={v.view} value={v.view}>{v.label}</option>)}
              {rail?.lists.map((l) => <option key={l.list_id} value={`L${l.list_id}`}>{l.list_name}{l.is_shared ? ' (shared)' : ''}</option>)}
            </select>
          </div>
          <div className="hidden min-w-0 items-baseline gap-2 md:flex">
            <h2 className="truncate text-sm font-semibold">{title ?? 'Tasks'}</h2>
            <span className="truncate text-xs text-muted-foreground">{subtitle}</span>
          </div>
          <span className="flex-1" />
          {page?.view === 'LIST' && list && (
            <>
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <Button variant="outline" size="sm" className="h-8">Sort: {SORTS.find((s) => s.v === sortMode)?.l}<ChevronDown className="ml-1 h-4 w-4" /></Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end">
                  <DropdownMenuRadioGroup value={sortMode} onValueChange={(v) => saveList({ list_id: list.list_id, sort_mode: v })}>
                    {SORTS.map((s) => <DropdownMenuRadioItem key={s.v} value={s.v} disabled={!canEdit}>{s.l}</DropdownMenuRadioItem>)}
                  </DropdownMenuRadioGroup>
                </DropdownMenuContent>
              </DropdownMenu>
              {canEdit && (
                <DropdownMenu>
                  <DropdownMenuTrigger asChild>
                    <Button variant="outline" size="sm" className="h-8 w-8 p-0" aria-label="List options"><MoreHorizontal className="h-4 w-4" /></Button>
                  </DropdownMenuTrigger>
                  <DropdownMenuContent align="end">
                    <DropdownMenuItem onSelect={() => setListDialog({ mode: 'rename', name: list.list_name, shared: list.is_shared })}>Rename list…</DropdownMenuItem>
                    {list.is_mine && !list.is_default && (
                      <DropdownMenuItem onSelect={() => saveList({ list_id: list.list_id, is_shared: !list.is_shared })}>
                        {list.is_shared ? 'Make private' : 'Share with the company'}
                      </DropdownMenuItem>
                    )}
                    <DropdownMenuItem disabled={completed.length === 0} onSelect={clearCompleted}>Delete completed tasks</DropdownMenuItem>
                    {!list.is_default && (
                      <>
                        <DropdownMenuSeparator />
                        <DropdownMenuItem className="text-destructive focus:text-destructive" onSelect={() => setConfirmDelete(true)}>Delete list…</DropdownMenuItem>
                      </>
                    )}
                  </DropdownMenuContent>
                </DropdownMenu>
              )}
            </>
          )}
        </div>

        {canEdit && page && page.view !== 'UPCOMING' && (
          <div className="flex items-center gap-2 border-b px-3 py-1.5">
            <Plus className="h-4 w-4 shrink-0 text-primary" aria-hidden />
            <Input id="tasks-quick-add" aria-label="Add a task" placeholder="Add a task, press Enter" value={quick} maxLength={500} className="h-9"
              onChange={(e) => setQuick(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); addQuick(); } }} />
          </div>
        )}

        <div role="listbox" aria-label="Tasks" className="flex-1 overflow-y-auto">
          {page === null ? <p className="p-3 text-sm text-muted-foreground">Loading…</p>
            : rows.length === 0 && completed.length === 0 ? (
              <p className="p-3 text-sm text-muted-foreground">
                {page.view === 'LIST' ? 'No tasks yet. Type one above and press Enter.' : VIEWS.find((v) => v.view === page.view)?.empty}
              </p>
            ) : grouped ? groupByDue(tasks).map((g) => (
              <Fragment key={g.group}>
                <div className={cn('sticky top-0 z-10 border-b bg-muted/80 px-3 py-0.5 text-xs font-semibold backdrop-blur', g.group === 'OVERDUE' ? 'text-destructive' : 'text-muted-foreground')}>
                  {DUE_GROUP_LABEL[g.group]}
                </div>
                {g.items.flatMap((t) => [t, ...(page.view === 'LIST' ? t.subtasks.filter((s) => !s.is_completed) : [])]).map(renderRow)}
              </Fragment>
            )) : rows.map(renderRow)}
          {completed.length > 0 && (
            <>
              <button type="button" aria-expanded={doneOpen}
                onClick={() => { setDoneOpen(!doneOpen); store.set(DONE_KEY, doneOpen ? '0' : '1'); }}
                className="flex w-full items-center gap-1.5 border-b px-3 py-2 text-left text-sm font-medium text-muted-foreground hover:bg-muted/40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring">
                {doneOpen ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}Completed ({completed.length})
              </button>
              {doneOpen && completed.map(renderRow)}
            </>
          )}
        </div>
        {canReorder && rows.length > 1 && (
          <div className="hidden truncate border-t px-3 py-1 text-xs text-muted-foreground lg:block"
            title="Drag or Alt+Up/Down to move · Alt+Right/Left to indent or outdent · Space done · S star · Delete removes (with Undo)">
            Drag or Alt+↑↓ to move · Alt+→← indent · Space done · S star · Del delete
          </div>
        )}
      </section>

      {/* Details */}
      {wide && (
        <aside aria-label="Task details" className="hidden w-[22rem] shrink-0 rounded-lg border bg-card xl:block">
          {detail ?? <p className="p-4 text-sm text-muted-foreground">Select a task to see its details.</p>}
        </aside>
      )}
      {!wide && (
        <Sheet open={sheetOpen && selected !== null} onOpenChange={setSheetOpen}>
          <SheetContent className="w-full p-0 sm:max-w-md">
            <SheetTitle className="sr-only">Task details</SheetTitle>
            <div className="h-full pt-8">{detail}</div>
          </SheetContent>
        </Sheet>
      )}

      <Dialog open={listDialog !== null} onOpenChange={(o) => { if (!o) setListDialog(null); }}>
        <DialogContent className="sm:max-w-sm">
          <DialogHeader><DialogTitle>{listDialog?.mode === 'new' ? 'New list' : 'Rename list'}</DialogTitle></DialogHeader>
          <form className="space-y-3" onSubmit={async (e) => {
            e.preventDefault();
            if (!listDialog?.name.trim()) return;
            const ok = await saveList(listDialog.mode === 'new'
              ? { list_name: listDialog.name, is_shared: listDialog.shared }
              : { list_id: list?.list_id, list_name: listDialog.name });
            if (ok) setListDialog(null);
          }}>
            <div>
              <label htmlFor="task-list-name" className="mb-1 block text-xs font-medium text-muted-foreground">Name *</label>
              <Input id="task-list-name" autoFocus maxLength={80} value={listDialog?.name ?? ''}
                onChange={(e) => setListDialog((d) => d && { ...d, name: e.target.value })} />
            </div>
            {listDialog?.mode === 'new' && (
              <label className="flex items-center gap-2 text-sm">
                <input type="checkbox" id="task-list-shared" className="h-4 w-4 accent-primary" checked={listDialog.shared}
                  onChange={(e) => setListDialog((d) => d && { ...d, shared: e.target.checked })} />
                Share with the company (every staff member with Tasks can see and edit it)
              </label>
            )}
            <DialogFooter className="gap-2 sm:gap-0">
              <Button type="button" variant="outline" onClick={() => setListDialog(null)}>Cancel</Button>
              <Button type="submit" disabled={!listDialog?.name.trim()}>{listDialog?.mode === 'new' ? 'Create list' : 'Save name'}</Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      <AlertDialog open={confirmDelete} onOpenChange={setConfirmDelete}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete “{list?.list_name}”?</AlertDialogTitle>
            <AlertDialogDescription>
              The list and all {(rail?.lists.find((l) => l.list_id === list?.list_id)?.open_count ?? 0) + completed.length} of its tasks are deleted
              {list?.is_shared ? ' for everyone' : ''}. This cannot be undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction className="bg-destructive text-destructive-foreground hover:bg-destructive/90" onClick={deleteList}>Delete list</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
