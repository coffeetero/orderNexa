'use client';

import { useCallback, useEffect, useState } from 'react';
import { X } from 'lucide-react';
import { EntityComboBox } from '@/components/bps/EntityComboBox';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import type { CustomerOption } from '@/components/features/account/order-entry/OrderHeaderRow';
import { DAYS, DAY_SHORT, IN, LAB, TD, TH, call, customerLabel, post, shortDate, type DateChange, type Day, type Route } from './routes-ui';

/** New route / Edit route: code, name, sort order, default driver, start time, notes, active; Delete route. */
export function RouteDialog({ tenantId, route, staff, canDelete, onClose, onSaved }: {
  tenantId: number; route: Route | null; staff: { user_id: number; user_name: string }[]; canDelete: boolean;
  onClose: () => void; onSaved: (routeId: number | null, message: string) => void;
}) {
  const [f, setF] = useState({
    route_code: route?.route_code ?? '', route_name: route?.route_name ?? '', sort_order: route ? String(route.sort_order) : '',
    default_driver_user_id: route?.default_driver_user_id ? String(route.default_driver_user_id) : '', start_time: route?.start_time ?? '',
    notes: route?.notes ?? '', is_active: route?.is_active ?? true,
  });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const set = (k: keyof typeof f, v: string | boolean) => setF((x) => ({ ...x, [k]: v }));
  const totalStops = route ? Object.values(route.counts).reduce((a, b) => a + b, 0) : 0;

  const save = async () => {
    setBusy(true); setError(null);
    try {
      const r = await post<{ route_id: number }>('/api/delivery/routes', {
        tenant_id: tenantId,
        route: { ...f, route_id: route?.route_id ?? null, default_driver_user_id: f.default_driver_user_id || null },
      });
      onSaved(r.route_id, `Route ${f.route_code.trim()} saved.`);
    } catch (e) { setError((e as Error).message); setBusy(false); }
  };
  const remove = async () => {
    if (!route) return;
    setBusy(true); setError(null);
    try {
      await call(`/api/delivery/routes?tenant_id=${tenantId}&id=${route.route_id}`, { method: 'DELETE' });
      onSaved(null, `Route ${route.route_code} deleted.`);
    } catch (e) { setError((e as Error).message); setBusy(false); }
  };

  return (
    <Dialog open onOpenChange={(o) => { if (!o) onClose(); }}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>{route ? `Edit route ${route.route_code}` : 'New route'}</DialogTitle>
          <DialogDescription>Stops are set per day and production time on the main screen.</DialogDescription>
        </DialogHeader>
        <form className="grid grid-cols-2 gap-3" onSubmit={(e) => { e.preventDefault(); void save(); }}>
          <div><label className={LAB} htmlFor="rd-code">Code *</label><input id="rd-code" className={IN} value={f.route_code} maxLength={20} autoFocus onChange={(e) => set('route_code', e.target.value)} /></div>
          <div><label className={LAB} htmlFor="rd-sort">Sort order</label><input id="rd-sort" className={IN} type="number" step={1} value={f.sort_order} placeholder="Last" onChange={(e) => set('sort_order', e.target.value)} /></div>
          <div className="col-span-2"><label className={LAB} htmlFor="rd-name">Name *</label><input id="rd-name" className={IN} value={f.route_name} maxLength={80} onChange={(e) => set('route_name', e.target.value)} /></div>
          <div>
            <label className={LAB} htmlFor="rd-driver">Default driver</label>
            <select id="rd-driver" className={IN} value={f.default_driver_user_id} onChange={(e) => set('default_driver_user_id', e.target.value)}>
              <option value="">None</option>
              {staff.map((s) => <option key={s.user_id} value={s.user_id}>{s.user_name}</option>)}
            </select>
          </div>
          <div><label className={LAB} htmlFor="rd-start">Start time</label><input id="rd-start" className={IN} type="time" value={f.start_time} onChange={(e) => set('start_time', e.target.value)} /></div>
          <div className="col-span-2"><label className={LAB} htmlFor="rd-notes">Notes</label><textarea id="rd-notes" className={`${IN} h-16 py-1.5`} maxLength={2000} value={f.notes} onChange={(e) => set('notes', e.target.value)} /></div>
          <label className="col-span-2 flex items-center gap-2 text-sm">
            <input type="checkbox" className="h-4 w-4 accent-[hsl(var(--primary))]" checked={f.is_active} onChange={(e) => set('is_active', e.target.checked)} />
            Active <span className="text-xs text-muted-foreground">(stops on an inactive route are not used when a run is processed)</span>
          </label>
          {error && <p role="alert" className="col-span-2 text-sm text-destructive">{error}</p>}
          <DialogFooter className="col-span-2 gap-2 sm:space-x-0">
            {route && canDelete && <Button type="button" variant="outline" className="mr-auto text-destructive" disabled={busy} onClick={() => setConfirmDelete(true)}>Delete route</Button>}
            <Button type="button" variant="outline" onClick={onClose} disabled={busy}>Cancel</Button>
            <Button type="submit" disabled={busy || !f.route_code.trim() || !f.route_name.trim()}>{busy ? 'Saving…' : 'Save route'}</Button>
          </DialogFooter>
        </form>
        <AlertDialog open={confirmDelete} onOpenChange={setConfirmDelete}>
          <AlertDialogContent>
            <AlertDialogHeader>
              <AlertDialogTitle>Delete route {route?.route_code}?</AlertDialogTitle>
              <AlertDialogDescription>
                This removes the route with its stops on every day and production time{totalStops ? ` (${totalStops} for this time alone)` : ''} and its date changes.
                Shipments already stamped keep the route name. To stop using it for now, untick Active instead.
              </AlertDialogDescription>
            </AlertDialogHeader>
            <AlertDialogFooter>
              <AlertDialogCancel>Cancel</AlertDialogCancel>
              <AlertDialogAction className="bg-destructive text-destructive-foreground hover:bg-destructive/90" onClick={() => void remove()}>Delete route</AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
      </DialogContent>
    </Dialog>
  );
}

/** Copy a day: this route's stops for the day + time to other days and/or times, replace or merge (om_route_stops_copy). */
export function CopyDayDialog({ tenantId, route, dow, code, codes, onClose, onDone }: {
  tenantId: number; route: Route; dow: Day; code: string; codes: { code: string; label: string }[];
  onClose: () => void; onDone: (message: string) => void;
}) {
  const [days, setDays] = useState<Day[]>([]);
  const [toCodes, setToCodes] = useState<string[]>([code]);
  const [mode, setMode] = useState<'REPLACE' | 'MERGE'>('REPLACE');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const label = (c: string) => codes.find((x) => x.code === c)?.label ?? c;
  const targets = days.flatMap((d) => toCodes.map((c) => ({ day_of_week: d, production_code: c }))).filter((t) => !(t.day_of_week === dow && t.production_code === code));
  const toggle = <T,>(list: T[], v: T) => (list.includes(v) ? list.filter((x) => x !== v) : [...list, v]);

  const copy = async () => {
    setBusy(true); setError(null);
    try {
      const r = await post<{ targets: number; copied: number; skipped: { day_of_week: Day; production_code: string; customer_name: string; route_code: string }[] }>(
        '/api/delivery/routes/stops', { tenant_id: tenantId, action: 'copy', route_id: route.route_id, dow, code, targets, mode });
      const skipped = r.skipped.length
        ? ` Skipped (on another route that day): ${r.skipped.map((s) => `${s.customer_name} (${DAY_SHORT[s.day_of_week]} ${label(s.production_code)}, ${s.route_code})`).join(', ')}.`
        : '';
      onDone(`Copied to ${r.targets} day${r.targets === 1 ? '' : 's'}: ${r.copied} stops added.${skipped}`);
    } catch (e) { setError((e as Error).message); setBusy(false); }
  };

  return (
    <Dialog open onOpenChange={(o) => { if (!o) onClose(); }}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Copy {DAY_SHORT[dow]} {label(code)} stops of {route.route_code} · {route.route_name}</DialogTitle>
          <DialogDescription>Windows and driver notes come along.</DialogDescription>
        </DialogHeader>
        <div className="space-y-3 text-sm">
          <fieldset>
            <legend className={LAB}>To days</legend>
            <div className="flex flex-wrap gap-x-4 gap-y-1">
              {DAYS.map((d) => (
                <label key={d} className="flex items-center gap-1.5">
                  <input type="checkbox" className="h-4 w-4 accent-[hsl(var(--primary))]" checked={days.includes(d)} onChange={() => setDays((x) => toggle(x, d))} />{DAY_SHORT[d]}
                </label>
              ))}
            </div>
          </fieldset>
          <fieldset>
            <legend className={LAB}>To production times</legend>
            <div className="flex flex-wrap gap-x-4 gap-y-1">
              {codes.map((c) => (
                <label key={c.code} className="flex items-center gap-1.5">
                  <input type="checkbox" className="h-4 w-4 accent-[hsl(var(--primary))]" checked={toCodes.includes(c.code)} onChange={() => setToCodes((x) => toggle(x, c.code))} />{c.label}
                </label>
              ))}
            </div>
          </fieldset>
          <fieldset className="space-y-1">
            <legend className={LAB}>How</legend>
            <label className="flex items-center gap-2"><input type="radio" name="copy-mode" checked={mode === 'REPLACE'} onChange={() => setMode('REPLACE')} />Replace: those days get exactly these stops</label>
            <label className="flex items-center gap-2"><input type="radio" name="copy-mode" checked={mode === 'MERGE'} onChange={() => setMode('MERGE')} />Merge: keep their stops, add the missing ones at the end</label>
          </fieldset>
          <p className="text-xs text-muted-foreground">A ship-to already on another route on a target day is skipped and listed afterwards.</p>
          {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
        </div>
        <DialogFooter className="gap-2 sm:space-x-0">
          <Button variant="outline" onClick={onClose} disabled={busy}>Cancel</Button>
          <Button onClick={() => void copy()} disabled={busy || targets.length === 0}>{busy ? 'Copying…' : `Copy to ${targets.length} day${targets.length === 1 ? '' : 's'}`}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/** One-off changes for a single delivery date: skip a ship-to, or put it on a route at a stop for that date only. */
export function DateChangesDialog({ tenantId, route, routes, code, codes, customers, canEdit, onClose }: {
  tenantId: number; route: Route; routes: Route[]; code: string; codes: { code: string; label: string }[];
  customers: CustomerOption[]; canEdit: boolean; onClose: () => void;
}) {
  const [date, setDate] = useState('');
  const [prodCode, setProdCode] = useState(code);
  const [changes, setChanges] = useState<DateChange[] | null>(null);
  const [customerId, setCustomerId] = useState<number | null>(null);
  const [kind, setKind] = useState<'SKIP' | 'ROUTE'>('SKIP');
  const [toRoute, setToRoute] = useState(String(route.route_id));
  const [stopNo, setStopNo] = useState('1');
  const [notes, setNotes] = useState('');
  const [formKey, setFormKey] = useState(0);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const label = (c: string) => codes.find((x) => x.code === c)?.label ?? c;

  /** A date shows its changes; no date shows the next 60 days. */
  const load = useCallback(async () => {
    setError(null);
    try {
      const from = date || new Date().toLocaleDateString('en-CA');
      const to = date || new Date(Date.now() + 60 * 86400000).toLocaleDateString('en-CA');
      const qs = new URLSearchParams({ tenant_id: String(tenantId), from, to, code: prodCode });
      setChanges((await call<{ changes: DateChange[] }>(`/api/delivery/routes/changes?${qs.toString()}`)).changes);
    } catch (e) { setError((e as Error).message); }
  }, [tenantId, date, prodCode]);
  useEffect(() => { void load(); }, [load]);

  const add = async () => {
    if (!date || customerId === null) return;
    setBusy(true); setError(null);
    try {
      await post('/api/delivery/routes/changes', {
        tenant_id: tenantId,
        change: { exception_date: date, production_code: prodCode, customer_id: customerId, kind, route_id: kind === 'ROUTE' ? Number(toRoute) : null, stop_no: kind === 'ROUTE' ? stopNo : null, notes },
      });
      setCustomerId(null); setNotes(''); setFormKey((k) => k + 1);
      await load();
    } catch (e) { setError((e as Error).message); }
    finally { setBusy(false); }
  };
  const remove = async (id: number) => {
    setBusy(true); setError(null);
    try { await call(`/api/delivery/routes/changes?tenant_id=${tenantId}&id=${id}`, { method: 'DELETE' }); await load(); }
    catch (e) { setError((e as Error).message); }
    finally { setBusy(false); }
  };

  return (
    <Dialog open onOpenChange={(o) => { if (!o) onClose(); }}>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle>Date changes</DialogTitle>
          <DialogDescription>One-off changes for a single delivery date (a holiday, a closed customer, an extra drop). Process run and that date&apos;s route sheet use them.</DialogDescription>
        </DialogHeader>
        <div className="space-y-3 text-sm">
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-[170px_150px_1fr]">
            <div><label className={LAB} htmlFor="dc-date">Delivery date</label><input id="dc-date" type="date" className={IN} value={date} onChange={(e) => setDate(e.target.value)} /></div>
            <div>
              <label className={LAB} htmlFor="dc-code">Production time</label>
              <select id="dc-code" className={IN} value={prodCode} onChange={(e) => setProdCode(e.target.value)}>
                {codes.map((c) => <option key={c.code} value={c.code}>{c.label}</option>)}
              </select>
            </div>
            <p className="col-span-2 self-end pb-2 text-xs text-muted-foreground sm:col-span-1">{date ? 'Changes for this date' : 'Showing the next 60 days; pick a date to add a change.'}</p>
          </div>
          <div className="max-h-56 overflow-auto rounded-md border border-border">
            <table className="w-full text-sm">
              <thead className="sticky top-0 z-[1] bg-card"><tr>
                <th className={TH}>Date</th><th className={TH}>Ship-to</th><th className={TH}>Change</th><th className={TH}>Usually</th>
                {canEdit && <th className={TH}><span className="sr-only">Remove</span></th>}
              </tr></thead>
              <tbody>
                {(changes ?? []).map((c) => (
                  <tr key={c.exception_id} className="border-t border-border">
                    <td className={`${TD} tabular-nums`}>{DAY_SHORT[c.day_of_week]} {shortDate(c.exception_date)}</td>
                    <td className={`${TD} max-w-[12rem] truncate`}>{customerLabel(c)}</td>
                    <td className={TD}>
                      <span className="inline-flex items-center gap-1.5 rounded-full border border-border px-2 text-xs font-medium">
                        <span className={`h-1.5 w-1.5 rounded-full ${c.kind === 'SKIP' ? 'bg-warning' : 'bg-info'}`} />
                        {c.kind === 'SKIP' ? 'Skip' : `${c.route_code}, stop ${c.stop_no}`}
                      </span>
                      {c.notes ? <span className="ml-1.5 text-xs text-muted-foreground">{c.notes}</span> : null}
                    </td>
                    <td className={`${TD} text-muted-foreground`}>{c.usual_route_code ? `${c.usual_route_code}, stop ${c.usual_stop_no}` : 'No route'}</td>
                    {canEdit && (
                      <td className={`${TD} text-center`}>
                        <Button variant="ghost" size="icon" className="h-7 w-7 text-destructive" aria-label={`Remove the change for ${c.customer_name}`} disabled={busy} onClick={() => void remove(c.exception_id)}><X className="h-4 w-4" /></Button>
                      </td>
                    )}
                  </tr>
                ))}
                {changes && changes.length === 0 && <tr><td colSpan={5} className="px-3 py-3 text-muted-foreground">No changes{date ? ` for ${shortDate(date)}` : ''} ({label(prodCode)}).</td></tr>}
              </tbody>
            </table>
          </div>
          {canEdit && (
            <div className="grid grid-cols-2 items-end gap-3 rounded-md border border-border p-3 sm:grid-cols-[minmax(0,1fr)_150px]">
              <div className="col-span-2 min-w-0 sm:col-span-1">
                <label className={LAB} htmlFor="dc-cust">Ship-to</label>
                <EntityComboBox<CustomerOption>
                  key={formKey} items={customers} value={customerId} onChange={(c) => setCustomerId(c?.customer_id ?? null)}
                  getId={(c) => c.customer_id} getLabel={customerLabel} getSearchText={(c) => `${c.customer_number ?? ''} ${c.customer_name}`}
                  getParentId={(c) => c.customer_parent_id} getSortKey={(c) => c.sort_path}
                  placeholder="Search number or name…" emptyText="No accounts or departments found." clearable triggerId="dc-cust" disabled={!date}
                  alwaysOpen collapseOnSelect clearSearchOnFocus maxResults={50}
                />
              </div>
              <div>
                <label className={LAB} htmlFor="dc-kind">Change</label>
                <select id="dc-kind" className={IN} value={kind} onChange={(e) => setKind(e.target.value as 'SKIP' | 'ROUTE')} disabled={!date}>
                  <option value="SKIP">Skip that day</option>
                  <option value="ROUTE">On a route at stop…</option>
                </select>
              </div>
              {kind === 'ROUTE' && (<>
                <div>
                  <label className={LAB} htmlFor="dc-route">Route</label>
                  <select id="dc-route" className={IN} value={toRoute} onChange={(e) => setToRoute(e.target.value)}>
                    {routes.filter((r) => r.is_active).map((r) => <option key={r.route_id} value={r.route_id}>{r.route_code} · {r.route_name}</option>)}
                  </select>
                </div>
                <div><label className={LAB} htmlFor="dc-stop">Stop</label><input id="dc-stop" type="number" min={1} className={IN} value={stopNo} onChange={(e) => setStopNo(e.target.value)} /></div>
              </>)}
              <div className="col-span-2 sm:col-span-1"><label className={LAB} htmlFor="dc-notes">Note</label><input id="dc-notes" className={IN} maxLength={500} value={notes} placeholder="Optional, shown to the driver" onChange={(e) => setNotes(e.target.value)} disabled={!date} /></div>
              <div className="col-span-2 flex justify-end sm:col-span-1">
                <Button onClick={() => void add()} disabled={busy || !date || customerId === null}>Add change</Button>
              </div>
            </div>
          )}
          {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
        </div>
        <DialogFooter><Button variant="outline" onClick={onClose}>Close</Button></DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
