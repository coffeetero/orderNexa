'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ArrowDown, ArrowUp, CalendarX2, Copy, Pencil, Plus, Printer, X } from 'lucide-react';
import { EntityComboBox } from '@/components/bps/EntityComboBox';
import { Button } from '@/components/ui/button';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import type { CustomerOption } from '@/components/features/account/order-entry/OrderHeaderRow';
import { CopyDayDialog, DateChangesDialog, RouteDialog } from './RouteDialogs';
import {
  DAYS, DAY_LETTER, DAY_SHORT, IN, TD, TH, call, customerLabel, isShipTo, post, shortDate, timeLabel,
  type Day, type Route, type RoutesData, type Stop, type StopsData, type Unassigned,
} from './routes-ui';

const todayDow = (): Day => DAYS[(new Date().getDay() + 6) % 7];

/** Operations › Delivery › Routes Maintenance (docs/design/mockups/routes-maintenance.html). */
export function RoutesMaintenance({ tenantId, canEdit, canDelete }: { tenantId: number; canEdit: boolean; canDelete: boolean }) {
  const [dow, setDow] = useState<Day>(todayDow);
  const [code, setCode] = useState('');
  const [data, setData] = useState<RoutesData | null>(null);
  const [routeId, setRouteId] = useState<number | null>(null);
  const [stops, setStops] = useState<StopsData | null>(null);
  const [selStop, setSelStop] = useState<number | null>(null);
  const [unassigned, setUnassigned] = useState<Unassigned[] | null>(null);
  const [orderingOnly, setOrderingOnly] = useState(true);
  const [customers, setCustomers] = useState<CustomerOption[] | null>(null);
  const [filter, setFilter] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [editing, setEditing] = useState<Route | 'new' | null>(null);
  const [copyOpen, setCopyOpen] = useState(false);
  const [changesOpen, setChangesOpen] = useState(false);
  const [confirmMove, setConfirmMove] = useState<{ customer: { customer_id: number; customer_name: string }; from: string } | null>(null);
  const addRef = useRef<HTMLInputElement>(null);
  /** Latest request per list, so a slow older answer never replaces a newer one. */
  const seq = useRef({ stops: 0, unassigned: 0 });

  const loadRoutes = useCallback(async (c: string) => {
    try {
      const d = await call<RoutesData>(`/api/delivery/routes?tenant_id=${tenantId}&code=${encodeURIComponent(c)}`);
      setData(d);
      if (!c) setCode(d.production_code ?? '');
      setRouteId((cur) => (cur !== null && d.routes.some((r) => r.route_id === cur) ? cur : d.routes.find((r) => r.is_active)?.route_id ?? d.routes[0]?.route_id ?? null));
    } catch (e) { setError((e as Error).message); }
  }, [tenantId]);

  const loadStops = useCallback(async () => {
    const n = ++seq.current.stops;
    if (routeId === null || !code) { setStops(null); return; }
    try {
      const qs = new URLSearchParams({ tenant_id: String(tenantId), route_id: String(routeId), dow, code });
      const d = await call<StopsData>(`/api/delivery/routes/stops?${qs.toString()}`);
      if (n === seq.current.stops) setStops(d);
    } catch (e) { if (n === seq.current.stops) { setStops(null); setError((e as Error).message); } }
  }, [tenantId, routeId, dow, code]);

  const loadUnassigned = useCallback(async () => {
    if (!code) return;
    const n = ++seq.current.unassigned;
    try {
      const qs = new URLSearchParams({ tenant_id: String(tenantId), dow, code, all: orderingOnly ? '0' : '1' });
      const d = await call<{ customers: Unassigned[] }>(`/api/delivery/routes/unassigned?${qs.toString()}`);
      if (n === seq.current.unassigned) setUnassigned(d.customers);
    } catch (e) { setError((e as Error).message); }
  }, [tenantId, dow, code, orderingOnly]);

  useEffect(() => { void loadRoutes(code); }, [loadRoutes, code]);
  useEffect(() => { void loadStops(); }, [loadStops]);
  useEffect(() => { void loadUnassigned(); }, [loadUnassigned]);
  useEffect(() => {
    call<CustomerOption[]>(`/api/customers?tenant_id=${tenantId}&hierarchy=true&active=true`)
      .then((c) => setCustomers(c.filter(isShipTo)))
      .catch(() => setCustomers([]));
  }, [tenantId]);

  /** After any change: the stops, the counts and the unassigned list come back from the database. */
  const refresh = useCallback(async () => { await Promise.all([loadStops(), loadRoutes(code), loadUnassigned()]); }, [loadStops, loadRoutes, loadUnassigned, code]);

  const run = async (fn: () => Promise<string | void>) => {
    setBusy(true); setError(null); setMessage(null);
    try { const m = await fn(); if (m) setMessage(m); await refresh(); }
    catch (e) { setError((e as Error).message); }
    finally { setBusy(false); }
  };

  const route = data?.routes.find((r) => r.route_id === routeId) ?? null;
  const codeLabel = data?.production_codes.find((c) => c.code === code)?.label ?? code;
  const where = `${DAY_SHORT[dow]} ${codeLabel}`;
  const list = stops?.stops ?? [];
  const assignedTo = useMemo(() => new Map((stops?.day_assignments ?? []).map((a) => [a.customer_id, a])), [stops]);
  const shownRoutes = (data?.routes ?? []).filter((r) => {
    const q = filter.trim().toLowerCase();
    return !q || r.route_code.toLowerCase().includes(q) || r.route_name.toLowerCase().includes(q);
  });

  const addStop = (customer: { customer_id: number; customer_name: string }, move = false) => {
    if (routeId === null || !route) return;
    const on = assignedTo.get(customer.customer_id);
    if (on && on.route_id === routeId) { setError(`${customer.customer_name} is already stop ${on.stop_no} on this route.`); return; }
    if (on && !move) { setConfirmMove({ customer, from: `route ${on.route_code}, stop ${on.stop_no}` }); return; }
    void run(async () => {
      const r = await post<{ stop_no: number; route_stop_id: number; moved_from: { route_code: string } | null }>('/api/delivery/routes/stops',
        { tenant_id: tenantId, action: 'add', route_id: routeId, dow, code, customer_id: customer.customer_id, move });
      setSelStop(r.route_stop_id);
      return `${customer.customer_name} added as stop ${r.stop_no}${r.moved_from ? ` (taken off route ${r.moved_from.route_code})` : ''}.`;
    });
  };

  const moveStop = (s: Stop, delta: number) => {
    const to = s.stop_no + delta;
    if (to < 1 || to > list.length) return;
    setSelStop(s.route_stop_id);
    void run(async () => { await post('/api/delivery/routes/stops', { tenant_id: tenantId, action: 'move', route_stop_id: s.route_stop_id, stop_no: to }); });
  };

  const removeStop = (s: Stop) => {
    const next = list.find((x) => x.stop_no === s.stop_no + 1) ?? list.find((x) => x.stop_no === s.stop_no - 1);
    setSelStop(next?.route_stop_id ?? null);
    void run(async () => {
      await call(`/api/delivery/routes/stops?tenant_id=${tenantId}&id=${s.route_stop_id}`, { method: 'DELETE' });
      return `${s.customer_name} taken off the route.`;
    });
  };

  /** Saves a window or note when it changed (on leaving the box). */
  const saveStop = (s: Stop, field: 'window_from' | 'window_to' | 'driver_notes', value: string) => {
    if ((s[field] ?? '') === value.trim()) return;
    void run(async () => { await post('/api/delivery/routes/stops', { tenant_id: tenantId, action: 'save', route_stop_id: s.route_stop_id, stop: { [field]: value } }); });
  };

  /** ↑ ↓ pick a stop, Alt+↑ / Alt+↓ move it, Delete removes it (not while typing in a box). */
  const onStopsKey = (e: React.KeyboardEvent) => {
    if (e.key !== 'ArrowUp' && e.key !== 'ArrowDown' && e.key !== 'Delete') return;
    const inBox = (e.target as HTMLElement).tagName === 'INPUT';
    const rowId = Number((e.target as HTMLElement).closest('tr')?.dataset.id) || selStop;
    const cur = list.find((s) => s.route_stop_id === rowId);
    if (e.altKey && cur && e.key !== 'Delete') {
      e.preventDefault();
      if (!canEdit || busy) return;
      moveStop(cur, e.key === 'ArrowUp' ? -1 : 1);
      return;
    }
    if (inBox) return;
    e.preventDefault();
    if (e.key === 'Delete') { if (cur && canEdit && !busy) removeStop(cur); return; }
    const i = cur ? list.indexOf(cur) : -1;
    const next = list[e.key === 'ArrowDown' ? Math.min(list.length - 1, i + 1) : Math.max(0, i - 1)];
    if (next) setSelStop(next.route_stop_id);
  };

  const onRoutesKey = (e: React.KeyboardEvent) => {
    if (e.key !== 'ArrowDown' && e.key !== 'ArrowUp') return;
    e.preventDefault();
    const i = shownRoutes.findIndex((r) => r.route_id === routeId);
    const next = shownRoutes[e.key === 'ArrowDown' ? Math.min(shownRoutes.length - 1, i + 1) : Math.max(0, i - 1)];
    if (next) setRouteId(next.route_id);
  };

  const openPrint = (all: boolean) => {
    const qs = new URLSearchParams({ dow, code });
    if (!all && routeId !== null) qs.set('route_id', String(routeId));
    window.open(`/delivery/routes/print?${qs.toString()}`, '_blank', 'noopener');
  };

  const unCount = unassigned?.length ?? null;

  return (
    <div className="flex min-h-[32rem] flex-col gap-3 p-2 sm:p-3 lg:h-[calc(100dvh-7.5rem)]">
      <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
        <h1 className="text-lg font-semibold">Routes Maintenance</h1>
        <span className="hidden text-sm text-muted-foreground min-[1440px]:inline">Operations › Delivery</span>
        <div className="inline-flex h-9 overflow-hidden rounded-md border border-input" role="group" aria-label="Day of week">
          {DAYS.map((d) => (
            <button key={d} type="button" aria-pressed={d === dow} onClick={() => setDow(d)}
              className={`min-w-[2.5rem] border-l border-input px-1.5 text-sm font-medium first:border-l-0 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring ${d === dow ? 'bg-accent text-accent-foreground shadow-[inset_0_-2px_0_hsl(var(--primary))]' : 'bg-background text-muted-foreground hover:bg-muted/40'}`}>
              {DAY_SHORT[d]}
            </button>
          ))}
        </div>
        <select aria-label="Production time" className={`${IN} !w-32`} value={code} onChange={(e) => setCode(e.target.value)}>
          {(data?.production_codes ?? []).map((c) => <option key={c.code} value={c.code}>{c.label}</option>)}
        </select>
        {unCount !== null && (
          <span className="inline-flex items-center gap-1.5 rounded-full border border-border px-2 text-xs font-medium">
            <span className={`h-1.5 w-1.5 rounded-full ${unCount ? 'bg-warning' : 'bg-success'}`} />
            {unCount ? `${unCount} unassigned` : 'All assigned'}
          </span>
        )}
        <span className="flex-1" />
        <Button variant="outline" size="sm" className={ACT} title="Print every route of the day" aria-label="Print day" onClick={() => openPrint(true)} disabled={!code}><Printer className="h-4 w-4" /><span className={ACT_TXT}>Print day</span></Button>
        {canEdit && <Button size="sm" className="gap-1.5" onClick={() => setEditing('new')}><Plus className="h-4 w-4" />New route</Button>}
      </div>
      {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
      {message && <p role="status" className="text-sm text-success">{message}</p>}

      <div className="grid min-h-0 flex-1 gap-3 lg:grid-cols-[300px_minmax(0,1fr)] min-[1440px]:grid-cols-[340px_minmax(0,1fr)]">
        <div className="flex min-h-0 flex-col gap-3">
          <section className="flex min-h-[12rem] flex-1 flex-col rounded-lg border border-border bg-card shadow-sm">
            <div className="flex items-center gap-3 border-b border-border px-3 py-1.5">
              <h2 className="text-sm font-semibold">Routes</h2>
              <span className="hidden text-xs min-[1440px]:inline text-muted-foreground">{codeLabel} stops per day</span>
              <span className="flex-1" />
              <input aria-label="Filter routes" placeholder="Filter…" value={filter} onChange={(e) => setFilter(e.target.value)} className={`${IN} h-8 !w-28`} />
            </div>
            <div className="min-h-0 flex-1 overflow-auto" tabIndex={0} onKeyDown={onRoutesKey} role="listbox" aria-label="Routes">
              <table className="w-full text-sm">
                <thead className="sticky top-0 z-[1] bg-card"><tr>
                  <th className={TH}>Route</th>
                  {DAYS.map((d) => <th key={d} className={`${TH} w-6 px-0.5 ${d === dow ? 'text-foreground' : ''}`} title={DAY_SHORT[d]}>{DAY_LETTER[d]}</th>)}
                </tr></thead>
                <tbody>
                  {shownRoutes.map((r) => {
                    const sel = r.route_id === routeId;
                    return (
                      <tr key={r.route_id} role="option" aria-selected={sel} onClick={() => setRouteId(r.route_id)}
                        ref={sel ? (el) => el?.scrollIntoView({ block: 'nearest' }) : undefined}
                        className={`cursor-pointer border-t border-border ${sel ? 'bps-sel bg-accent font-medium text-accent-foreground shadow-[inset_3px_0_0_hsl(var(--primary))]' : 'hover:bg-muted/40'} ${r.is_active ? '' : 'text-muted-foreground'}`}>
                        <td className={`${TD} w-full max-w-0 truncate`} title={`${r.route_code} · ${r.route_name}${r.is_active ? '' : ' (inactive)'}`}>
                          <span className="tabular-nums">{r.route_code}</span> · {r.route_name}{r.is_active ? '' : ' · inactive'}
                        </td>
                        {DAYS.map((d) => (
                          <td key={d} onClick={() => setDow(d)} title={`${DAY_SHORT[d]}: ${r.counts[d]} stops`}
                            className={`px-0.5 py-1.5 text-center tabular-nums ${d === dow ? 'bg-muted/50 font-semibold' : ''} ${r.counts[d] ? '' : 'text-muted-foreground'}`}>
                            {r.counts[d] || '·'}
                          </td>
                        ))}
                      </tr>
                    );
                  })}
                  {data && shownRoutes.length === 0 && <tr><td colSpan={8} className="px-3 py-3 text-sm text-muted-foreground">{data.routes.length ? 'No route matches.' : 'No routes yet. Use New route.'}</td></tr>}
                </tbody>
              </table>
            </div>
          </section>

          <section className="flex min-h-[10rem] flex-1 flex-col rounded-lg border border-border bg-card shadow-sm">
            <div className="flex items-center gap-3 border-b border-border px-3 py-1.5">
              <h2 className="text-sm font-semibold">Unassigned</h2>
              <span className="text-xs text-muted-foreground"><span className="hidden min-[1440px]:inline">{where} · </span><b className="font-semibold text-foreground">{unCount ?? '…'}</b></span>
              <span className="flex-1" />
              <label className="flex items-center gap-1.5 text-xs" title="Only those with an order for this day and time in the last 8 weeks, or a standing order">
                <input type="checkbox" className="h-4 w-4 accent-[hsl(var(--primary))]" checked={orderingOnly} onChange={(e) => setOrderingOnly(e.target.checked)} />Ordering only
              </label>
            </div>
            <div className="min-h-0 flex-1 overflow-auto">
              <table className="w-full text-sm">
                <thead className="sticky top-0 z-[1] bg-card"><tr>
                  <th className={TH}>Ship-to · last order</th><th className={TH}><span className="sr-only">Add</span></th>
                </tr></thead>
                <tbody>
                  {(unassigned ?? []).map((u) => (
                    <tr key={u.customer_id} className="border-t border-border hover:bg-muted/40">
                      <td className={`${TD} w-full max-w-0`}>
                        <div className="truncate" title={[u.customer_number, u.account_name, u.customer_name].filter(Boolean).join(' · ')}>
                          <span className="tabular-nums">{u.customer_number}</span>{u.customer_number ? ' · ' : ''}
                          {u.account_name ? <span className="text-muted-foreground">{u.account_name} · </span> : null}{u.customer_name}
                        </div>
                        <div className="text-xs tabular-nums text-muted-foreground">{u.last_order_date ? `Last order ${shortDate(u.last_order_date)}` : 'No orders for this time'}</div>
                      </td>
                      <td className={`${TD} text-right`}>
                        {canEdit && route && (
                          <Button variant="outline" size="sm" className="h-7 px-2 text-xs" disabled={busy} onClick={() => addStop(u)}
                            title={`Add to the end of ${route.route_code} · ${route.route_name}`}>
                            Add to {route.route_code}
                          </Button>
                        )}
                      </td>
                    </tr>
                  ))}
                  {unassigned && unassigned.length === 0 && (
                    <tr><td colSpan={2} className="px-3 py-3 text-sm text-muted-foreground">Every {orderingOnly ? 'ordering ' : ''}own-truck ship-to location has a stop for {where}.</td></tr>
                  )}
                </tbody>
              </table>
            </div>
            <p className="border-t border-border px-3 py-1 text-xs text-muted-foreground">Own-truck accounts and departments with no stop this day and time; a department follows its account&apos;s stop.</p>
          </section>
        </div>

        <section className="flex min-h-[20rem] min-w-0 flex-col rounded-lg border border-border bg-card shadow-sm">
          {route ? (<>
            <div className="flex flex-wrap items-center gap-x-3 gap-y-1 border-b border-border px-3 py-1.5">
              <h2 className="text-sm font-semibold">{route.route_code} · {route.route_name}</h2>
              <span className="text-sm text-muted-foreground">
                {where} · <b className="font-semibold text-foreground">{list.length}</b> stops
                {route.driver_name ? <> · Driver <b className="font-semibold text-foreground">{route.driver_name}</b></> : null}
                {route.start_time ? <> · Starts <b className="font-semibold text-foreground">{timeLabel(route.start_time)}</b></> : null}
              </span>
              <span className="inline-flex items-center gap-1.5 rounded-full border border-border px-2 text-xs font-medium">
                <span className={`h-1.5 w-1.5 rounded-full ${route.is_active ? 'bg-success' : 'bg-muted-foreground'}`} />{route.is_active ? 'Active' : 'Inactive'}
              </span>
              <span className="flex-1" />
              {canEdit && <Button variant="outline" size="sm" className={ACT} title="Edit route" aria-label="Edit route" onClick={() => setEditing(route)}><Pencil className="h-4 w-4" /><span className={ACT_TXT}>Edit route</span></Button>}
              {canEdit && <Button variant="outline" size="sm" className={ACT} title="Copy day…" aria-label="Copy day" onClick={() => setCopyOpen(true)} disabled={list.length === 0}><Copy className="h-4 w-4" /><span className={ACT_TXT}>Copy day…</span></Button>}
              <Button variant="outline" size="sm" className={ACT} title="Date changes…" aria-label="Date changes" onClick={() => setChangesOpen(true)}><CalendarX2 className="h-4 w-4" /><span className={ACT_TXT}>Date changes…</span></Button>
              <Button variant="outline" size="sm" className={ACT} title="Print route sheet" aria-label="Print route sheet" onClick={() => openPrint(false)}><Printer className="h-4 w-4" /><span className={ACT_TXT}>Print</span></Button>
            </div>
            {route.notes && <p className="border-b border-border px-3 py-1 text-xs text-muted-foreground">{route.notes}</p>}
            {canEdit && (
              <div className="flex flex-wrap items-center gap-x-3 gap-y-1 border-b border-border px-3 py-2">
                <label className="text-xs font-semibold text-muted-foreground" htmlFor="rt-add">Add</label>
                <div className="w-full max-w-md flex-1">
                  <EntityComboBox<CustomerOption>
                    items={customers ?? []} value={null}
                    onChange={(c) => { if (c) addStop(c); }}
                    getId={(c) => c.customer_id}
                    getLabel={(c) => {
                      const on = assignedTo.get(c.customer_id);
                      return `${customerLabel(c)}${on ? (on.route_id === routeId ? `  (stop ${on.stop_no} here)` : `  (on ${on.route_code}, stop ${on.stop_no})`) : ''}`;
                    }}
                    getInputLabel={() => ''}
                    getSearchText={(c) => `${c.customer_number ?? ''} ${c.customer_name}`}
                    getParentId={(c) => c.customer_parent_id}
                    getSortKey={(c) => c.sort_path}
                    getItemWeight={(c) => ((c.customer_type ?? '').trim().toUpperCase() === 'ACCOUNT' ? 'bold' : 'regular')}
                    placeholder="Search number or name, Enter adds at the end…"
                    loading={customers === null} disabled={busy}
                    emptyText="No accounts or departments found."
                    alwaysOpen collapseOnSelect clearSearchOnFocus
                    inputRef={addRef} triggerId="rt-add"
                  />
                </div>
                <p className="hidden text-xs text-muted-foreground min-[1440px]:block">A ship-to on another route this day asks before moving it here.</p>
              </div>
            )}
            <div className="min-h-0 flex-1 overflow-auto" onKeyDown={onStopsKey}>
              <table className="w-full text-sm">
                <thead className="sticky top-0 z-[1] bg-card"><tr>
                  <th className={TH}>Stop</th><th className={`${TH} hidden min-[1440px]:table-cell`}>Cust No.</th><th className={TH}>Ship-to</th><th className={`${TH} hidden min-[1700px]:table-cell`}>Address</th>
                  <th className={TH}>Window</th><th className={TH}>Driver notes</th>
                  {canEdit && <th className={TH}>Move</th>}
                </tr></thead>
                <tbody>
                  {list.map((s) => {
                    const sel = s.route_stop_id === selStop;
                    return (
                      <tr key={s.route_stop_id} data-id={s.route_stop_id} tabIndex={0} aria-selected={sel} onClick={() => setSelStop(s.route_stop_id)}
                        onFocus={() => setSelStop(s.route_stop_id)}
                        ref={sel ? (el) => el?.scrollIntoView({ block: 'nearest' }) : undefined}
                        className={`border-t border-border focus-visible:outline-none ${sel ? 'bps-sel bg-accent text-accent-foreground shadow-[inset_3px_0_0_hsl(var(--primary))]' : 'hover:bg-muted/40'}`}>
                        <td className={`${TD} text-center font-semibold tabular-nums`}>{s.stop_no}</td>
                        <td className={`${TD} hidden tabular-nums min-[1440px]:table-cell`}>{s.customer_number}</td>
                        <td className={`${TD} max-w-[11rem] truncate min-[1440px]:max-w-[13rem]`} title={[s.parent_name, s.customer_name].filter(Boolean).join(' · ') + (s.address ? `\n${s.address}` : '')}>
                          {s.customer_number ? <span className="tabular-nums min-[1440px]:hidden">{s.customer_number} · </span> : null}
                          {s.parent_name ? <span className="text-muted-foreground">{s.parent_name} · </span> : null}{s.customer_name}
                          {!s.is_active && <span className="ml-1.5 inline-flex items-center gap-1 text-xs text-warning"><span className="h-1.5 w-1.5 rounded-full bg-warning" />Inactive</span>}
                          <div className="truncate text-xs text-muted-foreground min-[1700px]:hidden">{s.address ?? <span className="italic">No address</span>}</div>
                        </td>
                        <td className={`${TD} hidden max-w-[18rem] truncate text-muted-foreground min-[1700px]:table-cell`} title={s.address ?? ''}>{s.address ?? <span className="italic">No address</span>}</td>
                        <td className={`${TD} text-center`}>
                          <span className="inline-flex items-center gap-1">
                            <input type="time" aria-label={`Window from, stop ${s.stop_no}`} defaultValue={s.window_from ?? ''} key={`f${s.route_stop_id}${s.window_from}`} disabled={!canEdit}
                              onBlur={(e) => saveStop(s, 'window_from', e.target.value)} className={`${CELL_IN} ${TIME_IN}`} />
                            <span className="text-muted-foreground">–</span>
                            <input type="time" aria-label={`Window to, stop ${s.stop_no}`} defaultValue={s.window_to ?? ''} key={`t${s.route_stop_id}${s.window_to}`} disabled={!canEdit}
                              onBlur={(e) => saveStop(s, 'window_to', e.target.value)} className={`${CELL_IN} ${TIME_IN}`} />
                          </span>
                        </td>
                        <td className={`${TD} w-full min-w-[6rem]`}>
                          <input aria-label={`Driver notes, stop ${s.stop_no}`} defaultValue={s.driver_notes ?? ''} key={`n${s.route_stop_id}${s.driver_notes}`} disabled={!canEdit} maxLength={500}
                            onBlur={(e) => saveStop(s, 'driver_notes', e.target.value)}
                            onKeyDown={(e) => { if (e.key === 'Enter') (e.target as HTMLInputElement).blur(); }}
                            className={`${CELL_IN} w-full`} />
                        </td>
                        {canEdit && (
                          <td className={`${TD} text-center`}>
                            <span className="inline-flex gap-1">
                              <Button variant="outline" size="icon" className="h-7 w-7 [@media(pointer:coarse)]:h-10 [@media(pointer:coarse)]:w-10" aria-label={`Move ${s.customer_name} up`} disabled={busy || s.stop_no === 1} onClick={(e) => { e.stopPropagation(); moveStop(s, -1); }}><ArrowUp className="h-4 w-4" /></Button>
                              <Button variant="outline" size="icon" className="h-7 w-7 [@media(pointer:coarse)]:h-10 [@media(pointer:coarse)]:w-10" aria-label={`Move ${s.customer_name} down`} disabled={busy || s.stop_no === list.length} onClick={(e) => { e.stopPropagation(); moveStop(s, 1); }}><ArrowDown className="h-4 w-4" /></Button>
                              <Button variant="ghost" size="icon" className="h-7 w-7 [@media(pointer:coarse)]:h-10 [@media(pointer:coarse)]:w-10 text-destructive" aria-label={`Take ${s.customer_name} off the route`} disabled={busy} onClick={(e) => { e.stopPropagation(); removeStop(s); }}><X className="h-4 w-4" /></Button>
                            </span>
                          </td>
                        )}
                      </tr>
                    );
                  })}
                  {stops && list.length === 0 && (
                    <tr><td colSpan={8} className="px-3 py-3 text-sm text-muted-foreground">No stops on this route for {where}.{canEdit ? ' Add a ship-to location above, or copy another day here.' : ''}</td></tr>
                  )}
                </tbody>
              </table>
            </div>
            <p className="border-t border-border px-3 py-1 text-xs text-muted-foreground">
              ↑ ↓ picks a stop{canEdit ? ' · Alt+↑ / Alt+↓ moves it · Delete takes it off · windows and notes save when you leave the box' : ''}
            </p>
          </>) : (
            <p className="p-4 text-sm text-muted-foreground">{data ? (data.routes.length ? 'Pick a route on the left.' : 'No routes yet.') : 'Loading…'}</p>
          )}
        </section>
      </div>

      {editing && data && (
        <RouteDialog tenantId={tenantId} route={editing === 'new' ? null : editing} staff={data.staff} canDelete={canDelete}
          onClose={() => setEditing(null)}
          onSaved={(id, msg) => { setEditing(null); if (id !== null) setRouteId(id); setMessage(msg); void refresh(); }} />
      )}
      {copyOpen && route && data && (
        <CopyDayDialog tenantId={tenantId} route={route} dow={dow} code={code} codes={data.production_codes}
          onClose={() => setCopyOpen(false)}
          onDone={(msg) => { setCopyOpen(false); setMessage(msg); void refresh(); }} />
      )}
      {changesOpen && route && data && (
        <DateChangesDialog tenantId={tenantId} route={route} routes={data.routes} code={code} codes={data.production_codes} customers={customers ?? []}
          canEdit={canEdit} onClose={() => setChangesOpen(false)} />
      )}
      <AlertDialog open={confirmMove !== null} onOpenChange={(o) => { if (!o) setConfirmMove(null); }}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Move {confirmMove?.customer.customer_name} to {route?.route_code}?</AlertDialogTitle>
            <AlertDialogDescription>It is on {confirmMove?.from} for {where}. Moving it takes it off that route, which is renumbered.</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={() => { if (confirmMove) addStop(confirmMove.customer, true); setConfirmMove(null); }}>Move here</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}

const ACT = 'gap-1.5 px-2 min-[1600px]:px-3';
const ACT_TXT = 'hidden min-[1600px]:inline';
const TIME_IN = 'w-[5.5rem] [&::-webkit-calendar-picker-indicator]:hidden';
const CELL_IN = 'bps-entry h-8 min-w-0 rounded-md border border-input bg-background px-1.5 text-sm tabular-nums focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-60';
