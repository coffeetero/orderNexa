'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import Link from 'next/link';
import { Check, ChevronLeft, ChevronRight, Keyboard, Layers, Lock, Pencil, Plus, Search, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import {
  DropdownMenu, DropdownMenuCheckboxItem, DropdownMenuContent, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { cn } from '@/lib/utils';
import {
  COLOR_CLASS, fromMinutes, toMinutes, type CalendarRow, type CalendarsData, type CalendarView, type CalItem, type EventDetail, type ViewData,
} from '@/lib/organizer/calendar';
import { api } from './contacts-ui';
import { AgendaView, MiniMonth, MonthView, TimeGridView } from './calendar-views';
import { EventDialog, type DialogTarget } from './EventDialog';
import { CalendarDialog } from './CalendarDialog';

const VIEWS: { key: CalendarView; label: string; hotkey: string }[] = [
  { key: 'day', label: 'Day', hotkey: 'd' }, { key: 'week', label: 'Week', hotkey: 'w' },
  { key: 'month', label: 'Month', hotkey: 'm' }, { key: 'agenda', label: 'Agenda', hotkey: 'a' },
];
const SHORTCUTS: [string, string][] = [
  ['t', 'Go to today'], ['d / w / m / a', 'Day, Week, Month, Agenda'], ['← → or j / k', 'Next / previous period'],
  ['c', 'Create an event'], ['/', 'Search'], ['Esc', 'Clear search or close'], ['?', 'Show these shortcuts'],
];

/** Per-browser memory of the chosen view and hidden calendars (a convenience; never needed for correctness). */
function readPref<T>(key: string, fallback: T): T {
  try { const v = localStorage.getItem(key); return v === null ? fallback : (JSON.parse(v) as T); } catch { return fallback; }
}
function writePref(key: string, value: unknown) {
  try { localStorage.setItem(key, JSON.stringify(value)); } catch { /* storage unavailable */ }
}

export function CalendarApp({ tenantId }: { tenantId: number }) {
  const prefKey = `bps.calendar.${tenantId}`;
  const [cals, setCals] = useState<CalendarsData | null>(null);
  const [hidden, setHidden] = useState<number[]>([]);
  const [showProd, setShowProd] = useState(true);
  const [view, setView] = useState<CalendarView>('month');
  const [anchor, setAnchor] = useState<string | null>(null);
  const [data, setData] = useState<ViewData | null>(null);
  const [miniAnchor, setMiniAnchor] = useState<string | null>(null);
  const [mini, setMini] = useState<ViewData | null>(null);
  const [search, setSearch] = useState('');
  const [searchQ, setSearchQ] = useState('');
  const [target, setTarget] = useState<DialogTarget | null>(null);
  const [calDialog, setCalDialog] = useState<{ cal: CalendarRow | null } | null>(null);
  const [runItem, setRunItem] = useState<CalItem | null>(null);
  const [help, setHelp] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [tick, setTick] = useState(0);
  const searchRef = useRef<HTMLInputElement>(null);
  const seq = useRef(0);

  // remembered view and hidden calendars
  useEffect(() => {
    const p = readPref<{ view?: CalendarView; hidden?: number[]; prod?: boolean }>(prefKey, {});
    setView(p.view ?? (window.innerWidth < 640 ? 'agenda' : 'month'));
    setHidden(Array.isArray(p.hidden) ? p.hidden : []);
    setShowProd(p.prod !== false);
  }, [prefKey]);
  useEffect(() => { writePref(prefKey, { view, hidden, prod: showProd }); }, [prefKey, view, hidden, showProd]);

  const loadCals = useCallback(() => {
    api<CalendarsData>(`/api/organizer/calendar?tenant_id=${tenantId}`).then(setCals).catch((e: Error) => setError(e.message));
  }, [tenantId]);
  useEffect(loadCals, [loadCals]);

  // debounce search
  useEffect(() => {
    const t = setTimeout(() => setSearchQ(search.trim()), 300);
    return () => clearTimeout(t);
  }, [search]);

  // a confirmation fades after a few seconds; errors stay until dismissed
  useEffect(() => {
    if (!notice) return;
    const t = setTimeout(() => setNotice(null), 4000);
    return () => clearTimeout(t);
  }, [notice]);

  // refresh every 5 minutes so shared changes and the time line stay current
  useEffect(() => {
    const t = setInterval(() => setTick((n) => n + 1), 5 * 60 * 1000);
    return () => clearInterval(t);
  }, []);

  const calParam = useMemo(() => {
    if (!cals || hidden.length === 0) return '';
    return `&calendars=${cals.calendars.filter((c) => !hidden.includes(c.calendar_id)).map((c) => c.calendar_id).join(',')}`;
  }, [cals, hidden]);

  useEffect(() => {
    if (!cals) return;
    const n = ++seq.current;
    const q = `/api/organizer/calendar/view?tenant_id=${tenantId}&view=${view}${anchor ? `&anchor=${anchor}` : ''}`
      + `${searchQ ? `&q=${encodeURIComponent(searchQ)}` : ''}${calParam}&production=${showProd ? 1 : 0}`;
    api<ViewData>(q)
      .then((d) => { if (n === seq.current) { setData(d); setError(null); } })
      .catch((e: Error) => { if (n === seq.current) setError(e.message); });
  }, [cals, tenantId, view, anchor, searchQ, calParam, showProd, tick]);

  // mini month follows the main view's month unless the user pages it
  const miniKey = (miniAnchor ?? data?.anchor ?? '').slice(0, 7);
  useEffect(() => {
    if (!miniKey) return;
    api<ViewData>(`/api/organizer/calendar/view?tenant_id=${tenantId}&view=mini&anchor=${miniKey}-01`)
      .then(setMini).catch(() => setMini(null));
  }, [tenantId, miniKey, data?.today]);

  const go = useCallback((date: string | null) => { setAnchor(date); setMiniAnchor(null); }, []);
  const editable = useMemo(() => (cals?.calendars ?? []).filter((c) => !hidden.includes(c.calendar_id)).concat(
    (cals?.calendars ?? []).filter((c) => hidden.includes(c.calendar_id))), [cals, hidden]);

  const create = useCallback((date: string | null, startTime: string | null, allDay = false) => {
    if (!cals?.can_edit || !data) return;
    const first = editable[0];
    if (!first) { setError('Add a calendar first.'); return; }
    const d = date ?? (view === 'day' ? data.anchor : data.today);
    const st = startTime ?? fromMinutes(Math.min(22 * 60, Math.ceil((data.now_minutes + 1) / 60) * 60));
    const detail: EventDetail = {
      calendar_id: first.calendar_id, title: '', location: null, notes: null, all_day: allDay || (date !== null && startTime === null),
      start_date: d, end_date: d, start_time: st, end_time: fromMinutes(toMinutes(st) + 60),
      repeat_freq: 'NONE', repeat_interval: 1, repeat_days: [], repeat_until: null, repeat_count: null,
    };
    setNotice(null);
    setTarget({ detail, occurrence: null });
  }, [cals, data, editable, view]);

  const open = useCallback((item: CalItem) => {
    if (item.kind !== 'EVENT' || item.event_id === null) { setRunItem(item); return; }
    api<EventDetail>(`/api/organizer/calendar/events?tenant_id=${tenantId}&id=${item.event_id}`)
      .then((d) => {
        setNotice(null);
        setTarget({
          detail: { ...d, start_date: item.start_date, end_date: item.end_date },
          occurrence: d.repeat_freq !== 'NONE' ? item.occurrence_date : null,
        });
      })
      .catch((e: Error) => setError(e.message));
  }, [tenantId]);

  const afterSave = (message: string) => {
    setTarget(null);
    setNotice(message);
    setTick((n) => n + 1);
  };
  const afterCalSave = (message: string) => {
    setCalDialog(null);
    setNotice(message);
    loadCals();
  };

  const toggleCal = (id: number) => setHidden((h) => (h.includes(id) ? h.filter((x) => x !== id) : [...h, id]));
  const showDay = useCallback((date: string) => { setView('day'); go(date); }, [go]);

  // Google-style keyboard shortcuts
  const dialogOpen = target !== null || calDialog !== null || runItem !== null || help;
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.ctrlKey || e.metaKey || e.altKey || dialogOpen) return;
      const el = e.target as HTMLElement | null;
      if (el && (el.isContentEditable || ['INPUT', 'TEXTAREA', 'SELECT'].includes(el.tagName))) {
        if (e.key === 'Escape' && el === searchRef.current) { setSearch(''); el.blur(); }
        return;
      }
      const v = VIEWS.find((x) => x.hotkey === e.key);
      if (v) { setView(v.key); setSearch(''); }
      else if (e.key === 't') go(null);
      else if (e.key === 'ArrowRight' || e.key === 'j' || e.key === 'n') { if (data && !searchQ) go(data.next); }
      else if (e.key === 'ArrowLeft' || e.key === 'k' || e.key === 'p') { if (data && !searchQ) go(data.prev); }
      else if (e.key === 'c') create(null, null);
      else if (e.key === '/') searchRef.current?.focus();
      else if (e.key === '?') setHelp(true);
      else if (e.key === 'Escape') setSearch('');
      else return;
      e.preventDefault();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [dialogOpen, data, searchQ, go, create]);

  const calendars = cals?.calendars ?? [];
  const shared = calendars.filter((c) => c.visibility === 'SHARED');
  const mine = calendars.filter((c) => c.visibility === 'PRIVATE');
  const searching = searchQ !== '' && data?.view === 'search';

  const calRow = (c: CalendarRow) => {
    const on = !hidden.includes(c.calendar_id);
    return (
      <div key={c.calendar_id} className="group flex items-center gap-1 rounded hover:bg-accent">
        <button type="button" role="checkbox" aria-checked={on} onClick={() => toggleCal(c.calendar_id)}
          className="flex min-w-0 flex-1 items-center gap-2 px-1 py-1 text-left text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
          <span className={cn('flex h-4 w-4 shrink-0 items-center justify-center rounded border-2', COLOR_CLASS[c.calendar_color].border, on && COLOR_CLASS[c.calendar_color].dot)}>
            {on && <Check className="h-3 w-3 text-background" strokeWidth={3} />}
          </span>
          <span className="truncate">{c.calendar_name}</span>
          {c.visibility === 'PRIVATE' && <Lock aria-label="Only you" className="h-3 w-3 shrink-0 text-muted-foreground" />}
        </button>
        {cals?.can_edit && (
          <button type="button" aria-label={`Edit ${c.calendar_name}`} onClick={() => setCalDialog({ cal: c })}
            className="mr-1 flex h-6 w-6 items-center justify-center rounded text-muted-foreground opacity-0 hover:bg-background focus-visible:opacity-100 group-hover:opacity-100">
            <Pencil className="h-3.5 w-3.5" />
          </button>
        )}
      </div>
    );
  };

  return (
    <div className="flex h-[calc(100dvh-7.5rem)] min-h-[32rem] gap-3 p-2 sm:p-3">
      <h1 className="sr-only">Calendar</h1>

      {/* Left rail */}
      <aside className="hidden w-60 shrink-0 flex-col gap-4 overflow-y-auto rounded-lg border bg-card p-3 lg:flex">
        {cals?.can_edit && (
          <Button onClick={() => create(null, null)} className="w-full"><Plus className="mr-1 h-4 w-4" />Create event</Button>
        )}
        <MiniMonth data={mini} selFrom={data?.view === 'week' || data?.view === 'day' ? data.from : null} selTo={data?.view === 'week' || data?.view === 'day' ? data.to : null}
          onPick={(d) => { setSearch(''); go(d); }} onMove={(d) => setMiniAnchor(d)} />
        <div>
          <div className="mb-1 flex items-center justify-between text-xs font-semibold uppercase tracking-wide text-muted-foreground">
            Company calendars
            {cals?.can_edit && (
              <button type="button" aria-label="New calendar" onClick={() => setCalDialog({ cal: null })}
                className="flex h-6 w-6 items-center justify-center rounded hover:bg-accent"><Plus className="h-4 w-4" /></button>
            )}
          </div>
          {shared.map(calRow)}
          {cals && shared.length === 0 && <p className="px-1 text-xs text-muted-foreground">No shared calendars.</p>}
        </div>
        {mine.length > 0 && (
          <div>
            <div className="mb-1 text-xs font-semibold uppercase tracking-wide text-muted-foreground">My calendars</div>
            {mine.map(calRow)}
          </div>
        )}
        <div>
          <div className="mb-1 text-xs font-semibold uppercase tracking-wide text-muted-foreground">From BPS</div>
          <button type="button" role="checkbox" aria-checked={showProd} onClick={() => setShowProd((v) => !v)}
            title="Production and delivery dates from Process Run (read-only)"
            className="flex w-full items-center gap-2 rounded px-1 py-1 text-left text-sm hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
            <span className={cn('flex h-4 w-4 shrink-0 items-center justify-center rounded border-2 border-dashed border-muted-foreground', showProd && 'border-solid bg-muted-foreground')}>
              {showProd && <Check className="h-3 w-3 text-background" strokeWidth={3} />}
            </span>
            <span className="truncate">Production runs</span>
            <Lock aria-label="Read-only" className="h-3 w-3 shrink-0 text-muted-foreground" />
          </button>
        </div>
        <button type="button" onClick={() => setHelp(true)} className="mt-auto flex items-center gap-1.5 text-xs text-muted-foreground hover:text-foreground">
          <Keyboard className="h-3.5 w-3.5" />Keyboard shortcuts <kbd className="rounded border px-1 font-sans">?</kbd>
        </button>
        {cals && <p className="text-xs text-muted-foreground">Times in {cals.time_zone.replace('_', ' ')}</p>}
      </aside>

      {/* Main */}
      <section className="flex min-w-0 flex-1 flex-col overflow-hidden rounded-lg border bg-card">
        <div className="flex flex-wrap items-center gap-2 border-b px-3 py-2">
          <Button size="sm" variant="outline" onClick={() => { setSearch(''); go(null); }} title="Today (t)">Today</Button>
          <div className="flex">
            <Button size="sm" variant="ghost" className="w-9 px-0" aria-label="Previous" title="Previous (←)" disabled={!data || searching}
              onClick={() => data && go(data.prev)}><ChevronLeft className="h-4 w-4" /></Button>
            <Button size="sm" variant="ghost" className="w-9 px-0" aria-label="Next" title="Next (→)" disabled={!data || searching}
              onClick={() => data && go(data.next)}><ChevronRight className="h-4 w-4" /></Button>
          </div>
          <h2 className="mr-2 min-w-[10rem] flex-1 truncate text-lg font-semibold" aria-live="polite">{data?.title ?? 'Calendar'}</h2>
          {cals?.can_edit && (
            <Button size="sm" className="lg:hidden" onClick={() => create(null, null)} aria-label="Create event"><Plus className="h-4 w-4" /></Button>
          )}
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button size="sm" variant="outline" className="lg:hidden" aria-label="Calendars"><Layers className="h-4 w-4" /></Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-56">
              <DropdownMenuLabel>Show calendars</DropdownMenuLabel>
              {calendars.map((c) => (
                <DropdownMenuCheckboxItem key={c.calendar_id} checked={!hidden.includes(c.calendar_id)} onCheckedChange={() => toggleCal(c.calendar_id)}
                  onSelect={(e) => e.preventDefault()}>
                  <span className={cn('mr-2 h-2.5 w-2.5 rounded-full', COLOR_CLASS[c.calendar_color].dot)} />{c.calendar_name}
                </DropdownMenuCheckboxItem>
              ))}
              <DropdownMenuSeparator />
              <DropdownMenuCheckboxItem checked={showProd} onCheckedChange={(v) => setShowProd(v === true)} onSelect={(e) => e.preventDefault()}>
                Production runs
              </DropdownMenuCheckboxItem>
            </DropdownMenuContent>
          </DropdownMenu>
          <div className="relative w-32 max-sm:flex-1 2xl:w-56">
            <Search className="pointer-events-none absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
            <Input ref={searchRef} value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search events" aria-label="Search events"
              className="h-9 pl-8 pr-7" />
            {search && (
              <button type="button" aria-label="Clear search" onClick={() => setSearch('')}
                className="absolute right-1.5 top-1/2 flex h-6 w-6 -translate-y-1/2 items-center justify-center rounded text-muted-foreground hover:bg-accent">
                <X className="h-3.5 w-3.5" />
              </button>
            )}
          </div>
          <div className="inline-flex overflow-hidden rounded-md border" role="group" aria-label="View">
            {VIEWS.map((v, i) => (
              <button key={v.key} type="button" aria-pressed={view === v.key && !searching} title={`${v.label} (${v.hotkey})`}
                onClick={() => { setView(v.key); setSearch(''); }}
                className={cn('h-9 px-2.5 text-sm font-medium focus-visible:relative 2xl:px-3 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                  i > 0 && 'border-l', view === v.key && !searching ? 'bg-primary/10 text-primary' : 'hover:bg-accent')}>
                {v.label}
              </button>
            ))}
          </div>
        </div>
        {(error || notice) && (
          <div role={error ? 'alert' : 'status'} className={cn('flex items-center gap-2 border-b px-3 py-1.5 text-sm', error ? 'text-destructive' : 'text-success')}>
            <span className="flex-1">{error ?? notice}</span>
            <button type="button" aria-label="Dismiss" onClick={() => { setError(null); setNotice(null); }} className="rounded p-0.5 hover:bg-accent"><X className="h-3.5 w-3.5" /></button>
          </div>
        )}

        {!data ? (
          <p className="p-4 text-sm text-muted-foreground">Loading…</p>
        ) : searching ? (
          <AgendaView data={data} onOpen={open} emptyText={`No events match “${searchQ}” in the past or coming year.`} />
        ) : data.view === 'month' ? (
          <MonthView data={data} onOpen={open} onCreate={(d) => create(d, null, true)} onDay={showDay} />
        ) : data.view === 'agenda' ? (
          <AgendaView data={data} onOpen={open} emptyText="Nothing on the calendar in these 30 days." />
        ) : (
          <TimeGridView data={data} onOpen={open} onCreate={(d, t) => create(d, t, t === null)} onDay={showDay} />
        )}
      </section>

      <EventDialog tenantId={tenantId} target={target} calendars={editable} canEdit={cals?.can_edit === true} canDelete={cals?.can_delete === true}
        onClose={() => setTarget(null)} onSaved={afterSave} />
      <CalendarDialog tenantId={tenantId} open={calDialog !== null} calendar={calDialog?.cal ?? null} canDelete={cals?.can_delete === true}
        onClose={() => setCalDialog(null)} onSaved={afterCalSave} />

      <Dialog open={runItem !== null} onOpenChange={(o) => { if (!o) setRunItem(null); }}>
        <DialogContent className="max-w-sm gap-3 p-5">
          <DialogHeader>
            <DialogTitle>{runItem?.title}</DialogTitle>
            <DialogDescription>
              {runItem?.kind === 'PRODUCTION' ? 'Production date' : 'Delivery date'} {runItem?.day_label}
              {runItem?.run_status ? ` · ${runItem.run_status.charAt(0)}${runItem.run_status.slice(1).toLowerCase()}` : ''}
            </DialogDescription>
          </DialogHeader>
          <p className="text-sm text-muted-foreground">Production runs come from Process Run and cannot be changed here.</p>
          <div className="flex justify-end gap-2 border-t pt-3">
            <Button variant="outline" onClick={() => setRunItem(null)}>Close</Button>
            <Button asChild><Link href="/production/process">Open Process Run</Link></Button>
          </div>
        </DialogContent>
      </Dialog>

      <Dialog open={help} onOpenChange={setHelp}>
        <DialogContent className="max-w-sm gap-3 p-5">
          <DialogHeader>
            <DialogTitle>Keyboard shortcuts</DialogTitle>
            <DialogDescription>They work when you are not typing in a field.</DialogDescription>
          </DialogHeader>
          <table className="text-sm">
            <tbody>
              {SHORTCUTS.map(([k, d]) => (
                <tr key={k}><td className="w-32 py-1 pr-3"><kbd className="rounded border bg-muted px-1.5 py-0.5 font-sans text-xs font-semibold">{k}</kbd></td><td className="py-1">{d}</td></tr>
              ))}
            </tbody>
          </table>
        </DialogContent>
      </Dialog>
    </div>
  );
}
