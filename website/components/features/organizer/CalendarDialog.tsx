'use client';

import { useEffect, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { cn } from '@/lib/utils';
import { CALENDAR_COLORS, COLOR_CLASS, COLOR_NAMES, type CalendarColor, type CalendarRow } from '@/lib/organizer/calendar';
import { api } from './contacts-ui';

/** Add, rename, recolour, share/make private or delete a calendar. */
export function CalendarDialog({ tenantId, calendar, open, canDelete, onClose, onSaved }: {
  tenantId: number; calendar: CalendarRow | null; open: boolean; canDelete: boolean;
  onClose: () => void; onSaved: (message: string) => void;
}) {
  const [name, setName] = useState('');
  const [color, setColor] = useState<CalendarColor>('accent');
  const [vis, setVis] = useState<'SHARED' | 'PRIVATE'>('SHARED');
  const [confirm, setConfirm] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    setName(calendar?.calendar_name ?? '');
    setColor(calendar?.calendar_color ?? 'blue');
    setVis(calendar?.visibility ?? 'SHARED');
    setConfirm(false);
    setError(null);
  }, [open, calendar]);

  const run = async (fn: () => Promise<string>) => {
    setBusy(true);
    setError(null);
    try { onSaved(await fn()); } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  };
  const save = () => run(async () => {
    await api('/api/organizer/calendar', 'POST', { tenant_id: tenantId, calendar_id: calendar?.calendar_id, calendar_name: name, calendar_color: color, visibility: vis });
    return calendar ? 'Calendar saved.' : 'Calendar added.';
  });
  const remove = () => run(async () => {
    const r = await api<{ events_deleted: number }>(`/api/organizer/calendar/${calendar?.calendar_id}?tenant_id=${tenantId}`, 'DELETE');
    return `Calendar deleted with ${r.events_deleted} event${r.events_deleted === 1 ? '' : 's'}.`;
  });

  return (
    <Dialog open={open} onOpenChange={(o) => { if (!o) onClose(); }}>
      <DialogContent className="max-w-md gap-3 p-5">
        <DialogHeader>
          <DialogTitle>{calendar ? 'Edit calendar' : 'New calendar'}</DialogTitle>
          <DialogDescription>Each calendar has its own colour and can be shown or hidden.</DialogDescription>
        </DialogHeader>
        {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
        <form id="calendar-form" className="space-y-3" onSubmit={(e) => { e.preventDefault(); void save(); }}>
          <div>
            <Label htmlFor="cal-name" className="text-xs text-muted-foreground">Name *</Label>
            <Input id="cal-name" autoFocus required maxLength={60} value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Catering" className="h-9" />
          </div>
          <div>
            <span className="text-xs font-medium text-muted-foreground">Colour</span>
            <div className="mt-1 flex gap-2" role="radiogroup" aria-label="Colour">
              {CALENDAR_COLORS.map((c) => (
                <button key={c} type="button" role="radio" aria-checked={color === c} aria-label={COLOR_NAMES[c]} title={COLOR_NAMES[c]} onClick={() => setColor(c)}
                  className={cn('h-7 w-7 rounded-full focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring', COLOR_CLASS[c].dot,
                    color === c && 'ring-2 ring-foreground ring-offset-2 ring-offset-background')} />
              ))}
            </div>
          </div>
          <fieldset className="space-y-1.5">
            <legend className="text-xs font-medium text-muted-foreground">Who sees it</legend>
            <label className="flex items-start gap-2 text-sm">
              <input type="radio" name="cal-vis" className="mt-0.5 accent-[hsl(var(--primary))]" checked={vis === 'SHARED'} onChange={() => setVis('SHARED')} />
              <span>Everyone at the company <span className="block text-xs text-muted-foreground">Staff with Calendar access can see and add events.</span></span>
            </label>
            <label className="flex items-start gap-2 text-sm">
              <input type="radio" name="cal-vis" className="mt-0.5 accent-[hsl(var(--primary))]" checked={vis === 'PRIVATE'} onChange={() => setVis('PRIVATE')} />
              <span>Only me <span className="block text-xs text-muted-foreground">A private calendar for your own events.</span></span>
            </label>
          </fieldset>
        </form>
        {confirm ? (
          <div className="flex flex-wrap items-center gap-2 border-t pt-3">
            <span className="mr-auto text-sm">Delete “{calendar?.calendar_name}” and every event on it? This cannot be undone.</span>
            <Button variant="outline" disabled={busy} onClick={() => setConfirm(false)}>Cancel</Button>
            <Button variant="destructive" disabled={busy} onClick={remove}>Delete calendar</Button>
          </div>
        ) : (
          <div className="flex items-center gap-2 border-t pt-3">
            {calendar && canDelete && (
              <Button variant="ghost" className="text-destructive hover:text-destructive" disabled={busy} onClick={() => setConfirm(true)}>Delete</Button>
            )}
            <span className="flex-1" />
            <Button variant="outline" disabled={busy} onClick={onClose}>Cancel</Button>
            <Button type="submit" form="calendar-form" disabled={busy || !name.trim()}>{calendar ? 'Save calendar' : 'Add calendar'}</Button>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
