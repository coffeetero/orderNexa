'use client';

import { useEffect, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { cn } from '@/lib/utils';
import {
  COLOR_CLASS, fromMinutes, toMinutes, type CalendarRow, type EventDetail, type RepeatFreq, type Scope,
} from '@/lib/organizer/calendar';
import { api } from './contacts-ui';

const WEEKDAYS: { iso: number; short: string; name: string }[] = [
  { iso: 7, short: 'S', name: 'Sunday' }, { iso: 1, short: 'M', name: 'Monday' }, { iso: 2, short: 'T', name: 'Tuesday' },
  { iso: 3, short: 'W', name: 'Wednesday' }, { iso: 4, short: 'T', name: 'Thursday' }, { iso: 5, short: 'F', name: 'Friday' },
  { iso: 6, short: 'S', name: 'Saturday' },
];
const UNIT: Record<RepeatFreq, string> = { NONE: '', DAILY: 'day(s)', WEEKLY: 'week(s)', MONTHLY: 'month(s)', YEARLY: 'year(s)' };
const selectCls = 'h-9 w-full rounded-md border border-input bg-background px-2 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-60';

/** ISO weekday (1 Mon .. 7 Sun) of a YYYY-MM-DD date, for the default "weekly on" day. */
const isoDow = (date: string) => new Date(`${date}T00:00:00`).getDay() || 7;

export interface DialogTarget {
  detail: EventDetail;
  /** The occurrence that was opened, for a repeating event. */
  occurrence: string | null;
}

/** Create or change an event. Repeating events ask which occurrences a change or delete applies to. */
export function EventDialog({ tenantId, target, calendars, canEdit, canDelete, onClose, onSaved }: {
  tenantId: number; target: DialogTarget | null; calendars: CalendarRow[]; canEdit: boolean; canDelete: boolean;
  onClose: () => void; onSaved: (message: string) => void;
}) {
  const [ev, setEv] = useState<EventDetail | null>(null);
  const [ends, setEnds] = useState<'never' | 'until' | 'count'>('never');
  const [ask, setAsk] = useState<'save' | 'delete' | null>(null);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!target) return;
    setEv(target.detail);
    setEnds(target.detail.repeat_until ? 'until' : target.detail.repeat_count ? 'count' : 'never');
    setAsk(null);
    setConfirmDelete(false);
    setError(null);
  }, [target]);

  if (!target || !ev) return null;
  const isNew = ev.event_id === undefined;
  const wasRepeating = !isNew && target.detail.repeat_freq !== 'NONE';
  const readOnly = !canEdit;
  const set = (patch: Partial<EventDetail>) => setEv((cur) => (cur ? { ...cur, ...patch } : cur));

  const setStartDate = (v: string) => {
    const patch: Partial<EventDetail> = { start_date: v };
    if (!ev.end_date || ev.end_date < v || ev.end_date === ev.start_date) patch.end_date = v;
    if (ev.repeat_freq === 'WEEKLY' && ev.repeat_days.length === 1 && ev.repeat_days[0] === isoDow(ev.start_date)) patch.repeat_days = [isoDow(v)];
    set(patch);
  };
  const setStartTime = (v: string) => {
    const dur = Math.max(toMinutes(ev.end_time) - toMinutes(ev.start_time), 15);
    set({ start_time: v, end_time: ev.start_date === ev.end_date ? fromMinutes(toMinutes(v) + dur) : ev.end_time });
  };
  const setFreq = (f: RepeatFreq) => set({ repeat_freq: f, repeat_days: f === 'WEEKLY' && ev.repeat_days.length === 0 ? [isoDow(ev.start_date)] : ev.repeat_days });
  const toggleDay = (iso: number) => set({
    repeat_days: ev.repeat_days.includes(iso) ? ev.repeat_days.filter((d) => d !== iso) : [...ev.repeat_days, iso].sort(),
  });

  const save = async (scope?: Scope) => {
    if (!ev.title.trim()) { setError('Give the event a title'); return; }
    if (wasRepeating && !scope) { setAsk('save'); return; }
    setBusy(true);
    setError(null);
    try {
      await api('/api/organizer/calendar/events', 'POST', {
        tenant_id: tenantId, ...ev,
        start_time: ev.all_day ? null : ev.start_time, end_time: ev.all_day ? null : ev.end_time,
        repeat_until: ev.repeat_freq !== 'NONE' && ends === 'until' ? ev.repeat_until : null,
        repeat_count: ev.repeat_freq !== 'NONE' && ends === 'count' ? ev.repeat_count : null,
        scope: scope ?? 'ALL', occurrence_date: target.occurrence,
      });
      onSaved(isNew ? 'Event added.' : 'Event saved.');
    } catch (e) {
      setError((e as Error).message);
      setAsk(null);
    } finally {
      setBusy(false);
    }
  };

  const remove = async (scope: Scope) => {
    setBusy(true);
    setError(null);
    try {
      const q = new URLSearchParams({ tenant_id: String(tenantId), scope });
      if (target.occurrence) q.set('occurrence_date', target.occurrence);
      await api(`/api/organizer/calendar/events/${ev.event_id}?${q}`, 'DELETE');
      onSaved('Event deleted.');
    } catch (e) {
      setError((e as Error).message);
      setAsk(null);
    } finally {
      setBusy(false);
    }
  };

  const cal = calendars.find((c) => c.calendar_id === ev.calendar_id);

  return (
    <Dialog open onOpenChange={(o) => { if (!o) onClose(); }}>
      <DialogContent className="max-h-[92dvh] max-w-2xl gap-3 overflow-y-auto p-5">
        <DialogHeader>
          <DialogTitle>{isNew ? 'New event' : readOnly ? 'Event' : 'Edit event'}</DialogTitle>
          <DialogDescription className={cn(isNew && 'sr-only')}>
            {isNew ? 'Add an event to a calendar.' : [target.detail.repeat_label, ev.updated_by_name && `Last changed by ${ev.updated_by_name}`].filter(Boolean).join(' · ') || ' '}
          </DialogDescription>
        </DialogHeader>
        {error && <p role="alert" className="text-sm text-destructive">{error}</p>}

        <form
          id="event-form"
          className="grid grid-cols-2 gap-x-3 gap-y-2.5"
          onSubmit={(e) => { e.preventDefault(); if (!readOnly) void save(); }}
        >
          <div className="col-span-2">
            <Label htmlFor="ev-title" className="text-xs text-muted-foreground">Title *</Label>
            <Input id="ev-title" autoFocus={!readOnly} disabled={readOnly} maxLength={200} value={ev.title}
              onChange={(e) => set({ title: e.target.value })} placeholder="e.g. Wedding cake pickup" className="h-9" />
          </div>
          <label className="col-span-2 flex items-center gap-2 text-sm">
            <input type="checkbox" className="h-4 w-4 accent-[hsl(var(--primary))]" disabled={readOnly} checked={ev.all_day}
              onChange={(e) => set({ all_day: e.target.checked, start_time: ev.start_time ?? '09:00', end_time: ev.end_time ?? '10:00' })} />
            All day
          </label>
          <div>
            <Label htmlFor="ev-sd" className="text-xs text-muted-foreground">Starts</Label>
            <div className="flex gap-1.5">
              <Input id="ev-sd" type="date" required disabled={readOnly} value={ev.start_date} onChange={(e) => setStartDate(e.target.value)} className="h-9 min-w-0" />
              {!ev.all_day && <Input aria-label="Start time" type="time" step={900} required disabled={readOnly} value={ev.start_time ?? ''} onChange={(e) => setStartTime(e.target.value)} className="h-9 w-[7.5rem] shrink-0" />}
            </div>
          </div>
          <div>
            <Label htmlFor="ev-ed" className="text-xs text-muted-foreground">Ends</Label>
            <div className="flex gap-1.5">
              <Input id="ev-ed" type="date" required disabled={readOnly} min={ev.start_date} value={ev.end_date} onChange={(e) => set({ end_date: e.target.value })} className="h-9 min-w-0" />
              {!ev.all_day && <Input aria-label="End time" type="time" step={900} required disabled={readOnly} value={ev.end_time ?? ''} onChange={(e) => set({ end_time: e.target.value })} className="h-9 w-[7.5rem] shrink-0" />}
            </div>
          </div>

          <div>
            <Label htmlFor="ev-repeat" className="text-xs text-muted-foreground">Repeat</Label>
            <select id="ev-repeat" className={selectCls} disabled={readOnly} value={ev.repeat_freq} onChange={(e) => setFreq(e.target.value as RepeatFreq)}>
              <option value="NONE">Does not repeat</option>
              <option value="DAILY">Daily</option>
              <option value="WEEKLY">Weekly</option>
              <option value="MONTHLY">Monthly (same day)</option>
              <option value="YEARLY">Yearly</option>
            </select>
          </div>
          {ev.repeat_freq !== 'NONE' ? (
            <div>
              <Label htmlFor="ev-every" className="text-xs text-muted-foreground">Every</Label>
              <div className="flex items-center gap-2">
                <Input id="ev-every" type="number" min={1} max={99} disabled={readOnly} value={ev.repeat_interval}
                  onChange={(e) => set({ repeat_interval: Math.max(1, Math.min(99, Number(e.target.value) || 1)) })} className="h-9 w-20" />
                <span className="text-sm text-muted-foreground">{UNIT[ev.repeat_freq]}</span>
              </div>
            </div>
          ) : <div />}
          {ev.repeat_freq === 'WEEKLY' && (
            <div className="col-span-2 sm:col-span-1">
              <span className="text-xs font-medium text-muted-foreground">On</span>
              <div className="mt-1 flex gap-1.5" role="group" aria-label="Repeat on">
                {WEEKDAYS.map((d) => {
                  const on = ev.repeat_days.includes(d.iso);
                  return (
                    <button key={d.iso} type="button" disabled={readOnly} aria-label={d.name} aria-pressed={on} onClick={() => toggleDay(d.iso)}
                      className={cn('flex h-9 w-9 items-center justify-center rounded-full border text-xs font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                        on ? 'border-primary bg-primary text-primary-foreground' : 'border-input hover:bg-accent')}>
                      {d.short}
                    </button>
                  );
                })}
              </div>
            </div>
          )}
          {ev.repeat_freq !== 'NONE' && (
            <div className={cn('flex flex-wrap items-end gap-2', ev.repeat_freq === 'WEEKLY' ? 'col-span-2 sm:col-span-1' : 'col-span-2')}>
              <div className="w-32">
                <Label htmlFor="ev-ends" className="text-xs text-muted-foreground">Ends</Label>
                <select id="ev-ends" className={selectCls} disabled={readOnly} value={ends} onChange={(e) => setEnds(e.target.value as typeof ends)}>
                  <option value="never">Never</option>
                  <option value="until">On a date</option>
                  <option value="count">After</option>
                </select>
              </div>
              {ends === 'until' && (
                <Input aria-label="Repeat until" type="date" required disabled={readOnly} min={ev.start_date} value={ev.repeat_until ?? ''}
                  onChange={(e) => set({ repeat_until: e.target.value || null })} className="h-9 w-40" />
              )}
              {ends === 'count' && (
                <span className="flex items-center gap-2">
                  <Input aria-label="Number of times" type="number" min={1} max={999} required disabled={readOnly} value={ev.repeat_count ?? ''}
                    onChange={(e) => set({ repeat_count: Number(e.target.value) || null })} className="h-9 w-24" />
                  <span className="text-sm text-muted-foreground">times</span>
                </span>
              )}
            </div>
          )}

          <div>
            <Label htmlFor="ev-cal" className="text-xs text-muted-foreground">Calendar *</Label>
            <div className="relative">
              {cal && <span className={cn('pointer-events-none absolute left-2.5 top-1/2 h-2.5 w-2.5 -translate-y-1/2 rounded-full', COLOR_CLASS[cal.calendar_color].dot)} />}
              <select id="ev-cal" className={cn(selectCls, 'pl-7')} disabled={readOnly} value={ev.calendar_id ?? ''}
                onChange={(e) => set({ calendar_id: Number(e.target.value) || null })}>
                {calendars.map((c) => (
                  <option key={c.calendar_id} value={c.calendar_id}>{c.calendar_name}{c.visibility === 'PRIVATE' ? ' (only me)' : ''}</option>
                ))}
              </select>
            </div>
          </div>
          <div>
            <Label htmlFor="ev-loc" className="text-xs text-muted-foreground">Location</Label>
            <Input id="ev-loc" disabled={readOnly} maxLength={200} value={ev.location ?? ''} onChange={(e) => set({ location: e.target.value })} className="h-9" />
          </div>
          <div className="col-span-2">
            <Label htmlFor="ev-notes" className="text-xs text-muted-foreground">Notes</Label>
            <Textarea id="ev-notes" disabled={readOnly} maxLength={4000} rows={2} value={ev.notes ?? ''} onChange={(e) => set({ notes: e.target.value })} className="min-h-[3.5rem]" />
          </div>
          {cal && (
            <p className="col-span-2 text-xs text-muted-foreground">
              {cal.visibility === 'PRIVATE' ? 'Private: only you see events on this calendar.' : 'Shared: everyone at the company with Calendar access sees this event.'}
            </p>
          )}
        </form>

        {ask ? (
          <div className="flex flex-wrap items-center gap-2 border-t pt-3" role="group" aria-label={ask === 'save' ? 'Change which events' : 'Delete which events'}>
            <span className="mr-auto text-sm font-medium">{ask === 'save' ? 'Change which events?' : 'Delete which events?'}</span>
            <Button variant="outline" size="sm" disabled={busy} onClick={() => setAsk(null)}>Cancel</Button>
            {(['ONE', 'FOLLOWING', 'ALL'] as Scope[]).map((s) => (
              <Button key={s} size="sm" variant={ask === 'delete' ? 'destructive' : s === 'ALL' ? 'default' : 'outline'} disabled={busy}
                onClick={() => (ask === 'save' ? save(s) : remove(s))}>
                {s === 'ONE' ? 'This event' : s === 'FOLLOWING' ? 'This and following' : 'All events'}
              </Button>
            ))}
          </div>
        ) : confirmDelete ? (
          <div className="flex flex-wrap items-center gap-2 border-t pt-3">
            <span className="mr-auto text-sm">Delete “{target.detail.title}”? This cannot be undone.</span>
            <Button variant="outline" disabled={busy} onClick={() => setConfirmDelete(false)}>Cancel</Button>
            <Button variant="destructive" disabled={busy} onClick={() => remove('ALL')}>Delete event</Button>
          </div>
        ) : (
          <div className="flex flex-wrap items-center gap-2 border-t pt-3">
            {!isNew && canDelete && (
              <Button variant="ghost" className="text-destructive hover:text-destructive" disabled={busy}
                onClick={() => (wasRepeating ? setAsk('delete') : setConfirmDelete(true))}>
                Delete
              </Button>
            )}
            <span className="flex-1" />
            <Button variant="outline" disabled={busy} onClick={onClose}>{readOnly ? 'Close' : 'Cancel'}</Button>
            {!readOnly && <Button type="submit" form="event-form" disabled={busy}>{busy ? 'Saving…' : isNew ? 'Add event' : 'Save event'}</Button>}
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
