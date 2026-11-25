'use client';

import { Suspense, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { usePathname, useRouter, useSearchParams } from 'next/navigation';

/**
 * Orders › Manage Orders (layout approved 2026-11-25, docs/design/mockups/manage-orders.html).
 * Real orders by production date: Day / Shift / Group filters, a compact summary strip (orders per status, amount; a status
 * filters the list), search right above the list, 50 orders a page with group subtotals over all pages. Everything is
 * worked out by the database (om_orders_manage_get via /api/orders/manage). The filters live in the address, so returning
 * from an order keeps them. Clicking an order opens Order Entry (protected, unchanged). New order and Export Orders are in
 * Quick access.
 */

type Status = 'OPEN' | 'IN_PRODUCTION' | 'SHIPPED' | 'INVOICED';
interface Row { order_id: number; order_number: string; customer_name: string | null; department_event: string | null; production_date: string; shift: string | null; shift_label: string | null; lines: number; amount: number | null; status: Status; group_key: string | null }
interface Group { key: string | null; label: string | null; orders: number; lines: number; amount: number }
interface Result {
  from: string; to: string; today: string; shifts: { value: string; label: string }[];
  summary: { all: number; open: number; in_production: number; shipped: number; invoiced: number; amount: number };
  total: number; groups: Group[]; rows: Row[];
}

const PAGE = 50;
const STATUS: Record<Status, { label: string; tone: string; dot: string }> = {
  OPEN: { label: 'Open', tone: 'bg-muted text-muted-foreground', dot: 'bg-muted-foreground' },
  IN_PRODUCTION: { label: 'In production', tone: 'bg-warning-soft text-warning', dot: 'bg-warning' },
  SHIPPED: { label: 'Shipped', tone: 'bg-info-soft text-info', dot: 'bg-info' },
  INVOICED: { label: 'Invoiced', tone: 'bg-success-soft text-success', dot: 'bg-success' },
};
const PERIODS = [['yesterday', 'Yesterday'], ['today', 'Today'], ['tomorrow', 'Tomorrow'], ['this_week', 'This week'], ['next_week', 'Next week'], ['custom', 'Custom range…']] as const;
const GROUPS = [['shift', 'Group by Shift'], ['customer', 'Group by Customer'], ['status', 'Group by Status'], ['none', 'No grouping']] as const;

/** Money with the sign in front of the $ ("-$5,768.69"). */
const money = (v: number | null | undefined) => { const n = Number(v ?? 0); return `${n < 0 ? '-' : ''}$${Math.abs(n).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`; };
const longDate = (d: string) => new Date(`${d}T12:00:00`).toLocaleDateString('en-US', { weekday: 'long', month: 'short', day: 'numeric', year: 'numeric' });
const shortDate = (d: string) => new Date(`${d}T12:00:00`).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
const SEL = 'h-9 rounded-md border border-input bg-background px-2 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring';
const TH = 'h-8 whitespace-nowrap bg-muted/50 px-3 text-left text-[11px] font-semibold uppercase tracking-wider text-muted-foreground';
const TD = 'whitespace-nowrap px-3 py-1.5';

function ManageOrders() {
  const router = useRouter();
  const pathname = usePathname();
  const params = useSearchParams();
  const get = (k: string, d = '') => params.get(k) ?? d;
  const period = get('period', 'today');
  const group = get('group', 'shift');
  const sort = get('sort', 'order');
  const desc = get('desc', '1') !== '0';
  const page = Math.max(Number.parseInt(get('page', '1'), 10) || 1, 1);

  const [data, setData] = useState<Result | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState(get('search'));
  const [cursor, setCursor] = useState(-1);
  const searchRef = useRef<HTMLInputElement>(null);
  const rowsRef = useRef<HTMLTableSectionElement>(null);

  /** Changes filters in the address (replace, so Back leaves the page); any filter change returns to page 1. */
  const set = useCallback((next: Record<string, string | null>) => {
    const p = new URLSearchParams(params.toString());
    for (const [k, v] of Object.entries(next)) { if (v === null || v === '') p.delete(k); else p.set(k, v); }
    if (!('page' in next)) p.delete('page');
    router.replace(`${pathname}?${p.toString()}`, { scroll: false });
  }, [params, pathname, router]);

  // search waits until typing pauses
  useEffect(() => {
    if (search === get('search')) return;
    const t = setTimeout(() => set({ search: search.trim() || null }), 300);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [search]);

  const query = params.toString();
  useEffect(() => {
    let live = true;
    setLoading(true); setError(null);
    fetch(`/api/orders/manage?${query}`)
      .then((r) => r.json())
      .then((j: { data?: Result; error?: string }) => { if (!live) return; if (j.error) setError(j.error); else { setData(j.data ?? null); setCursor(-1); } })
      .catch((e: Error) => live && setError(e.message))
      .finally(() => live && setLoading(false));
    return () => { live = false; };
  }, [query]);

  const open = useCallback((id: number) => router.push(`/orders/${id}/edit`), [router]);

  // keyboard: / search, ↑ ↓ move, Enter open
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const typing = e.target instanceof HTMLElement && /^(INPUT|SELECT|TEXTAREA)$/.test(e.target.tagName);
      if (e.key === '/' && !typing) { e.preventDefault(); searchRef.current?.focus(); return; }
      if (typing || !data?.rows.length) return;
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        e.preventDefault();
        setCursor((c) => Math.min(Math.max((c < 0 ? (e.key === 'ArrowDown' ? -1 : data.rows.length) : c) + (e.key === 'ArrowDown' ? 1 : -1), 0), data.rows.length - 1));
      } else if (e.key === 'Enter' && cursor >= 0) { e.preventDefault(); open(data.rows[cursor].order_id); }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [data, cursor, open]);
  useEffect(() => { rowsRef.current?.querySelector(`[data-i="${cursor}"]`)?.scrollIntoView({ block: 'nearest' }); }, [cursor]);

  const groups = useMemo(() => new Map((data?.groups ?? []).map((g) => [g.key ?? '', g])), [data]);
  const pages = data ? Math.max(Math.ceil(data.total / PAGE), 1) : 1;
  const status = get('status');
  const sortBy = (col: string) => set({ sort: col, desc: sort === col ? (desc ? '0' : '1') : (col === 'customer' ? '0' : '1') });
  const arrow = (col: string) => (sort === col ? <span className="text-primary">{desc ? ' ↓' : ' ↑'}</span> : null);

  const figures: [string, string, number | undefined, string | null][] = [
    ['', 'All orders', data?.summary.all, null],
    ['OPEN', 'Open', data?.summary.open, STATUS.OPEN.dot],
    ['IN_PRODUCTION', 'In production', data?.summary.in_production, STATUS.IN_PRODUCTION.dot],
    ['SHIPPED', 'Shipped', data?.summary.shipped, STATUS.SHIPPED.dot],
    ['INVOICED', 'Invoiced', data?.summary.invoiced, STATUS.INVOICED.dot],
  ];

  const subtitle = data ? `${data.from === data.to ? `Production ${longDate(data.from)}` : `Production ${shortDate(data.from)} – ${shortDate(data.to)}`} · ${data.summary.all.toLocaleString('en-US')} order${data.summary.all === 1 ? '' : 's'}` : '';
  let lastKey: string | null | undefined;

  return (
    <div className="space-y-3 py-3">
      <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
        <h1 className="text-lg font-semibold tracking-tight">Manage Orders</h1>
        <p className="text-sm text-muted-foreground">{subtitle}</p>
      </div>

      <section aria-label="Filters" className="flex flex-wrap items-center gap-2 rounded-lg border border-border bg-card px-3 py-2.5 shadow-sm">
        <select aria-label="Production date" className={SEL} value={period} onChange={(e) => set({ period: e.target.value === 'today' ? null : e.target.value, ...(e.target.value === 'custom' ? { from: data?.from ?? null, to: data?.to ?? null } : { from: null, to: null }) })}>
          {PERIODS.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
        </select>
        <select aria-label="Shift" className={SEL} value={get('shift')} onChange={(e) => set({ shift: e.target.value || null })}>
          <option value="">All shifts</option>
          {data?.shifts.map((s) => <option key={s.value} value={s.value}>{s.label}</option>)}
        </select>
        {period === 'custom' && (
          <span className="inline-flex items-center gap-1.5">
            <input type="date" aria-label="From" className={SEL} value={get('from', data?.from ?? '')} onChange={(e) => set({ from: e.target.value || null })} />
            <span className="text-sm text-muted-foreground">to</span>
            <input type="date" aria-label="To" className={SEL} value={get('to', data?.to ?? '')} onChange={(e) => set({ to: e.target.value || null })} />
          </span>
        )}
        <select aria-label="Group the list" className={SEL} value={group} onChange={(e) => set({ group: e.target.value === 'shift' ? null : e.target.value })}>
          {GROUPS.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
        </select>
      </section>

      <section aria-label="Summary" className="grid grid-cols-3 overflow-hidden rounded-lg border border-border bg-card shadow-sm md:grid-cols-6">
        {figures.map(([key, label, value, dot]) => (
          <button key={label} type="button" onClick={() => set({ status: key || null })} aria-pressed={status === key}
            className={`min-w-0 border-b border-r border-border px-3 py-1.5 text-center hover:bg-muted/40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring md:border-b-0 ${status === key ? 'shadow-[inset_0_-2px_0_hsl(var(--primary))]' : ''}`}>
            <span className="block truncate text-[11px] font-semibold uppercase tracking-wider text-muted-foreground">
              {dot && <span className={`mr-1.5 inline-block h-1.5 w-1.5 rounded-full align-middle ${dot}`} />}{label}
            </span>
            <span className="block text-[17px] font-semibold leading-snug tabular-nums">{value === undefined ? '—' : value.toLocaleString('en-US')}</span>
          </button>
        ))}
        <div className="min-w-0 border-b border-border px-3 py-1.5 text-center md:border-b-0">
          <span className="block text-[11px] font-semibold uppercase tracking-wider text-muted-foreground">Amount</span>
          <span className="block text-[17px] font-semibold leading-snug tabular-nums">{data ? money(data.summary.amount) : '—'}</span>
        </div>
      </section>

      <section className="min-w-0 overflow-hidden rounded-lg border border-border bg-card text-card-foreground shadow-sm">
        <div className="flex items-center gap-2 border-b border-border px-3 py-2">
          <input ref={searchRef} type="search" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search order #, customer, department  ( / )"
            aria-label="Search orders" className={`${SEL} w-full max-w-sm`} />
          {loading && <span className="text-xs text-muted-foreground">Loading…</span>}
        </div>
        {error ? (
          <p role="alert" className="px-4 py-3 text-sm text-destructive">{error}</p>
        ) : (
          <div className="overflow-x-auto" aria-busy={loading}>
            <table className="w-full text-sm">
              <thead>
                <tr>
                  <th className={`${TH} cursor-pointer`} onClick={() => sortBy('order')}>Order{arrow('order')}</th>
                  <th className={`${TH} cursor-pointer`} onClick={() => sortBy('customer')}>Customer{arrow('customer')}</th>
                  <th className={TH}>Department / event</th>
                  <th className={TH}>Shift</th>
                  <th className={`${TH} cursor-pointer text-right`} onClick={() => sortBy('lines')}>Lines{arrow('lines')}</th>
                  <th className={`${TH} cursor-pointer text-right`} onClick={() => sortBy('amount')}>Amount{arrow('amount')}</th>
                  <th className={TH}>Status</th>
                </tr>
              </thead>
              <tbody ref={rowsRef}>
                {data?.rows.map((r, i) => {
                  const g = group !== 'none' && r.group_key !== lastKey ? groups.get(r.group_key ?? '') : undefined;
                  const continued = g && i === 0 && page > 1;
                  lastKey = r.group_key;
                  return [
                    g && (
                      <tr key={`g-${r.group_key}`} className="bg-muted/40 text-[13px] font-semibold">
                        <td className={TD} colSpan={4}>{g.label ?? '—'} · {g.orders} order{g.orders === 1 ? '' : 's'}{continued ? ' (continued)' : ''}</td>
                        <td className={`${TD} text-right tabular-nums`}>{g.lines.toLocaleString('en-US')}</td>
                        <td className={`${TD} text-right tabular-nums`}>{money(g.amount)}</td>
                        <td />
                      </tr>
                    ),
                    <tr key={r.order_id} data-i={i} onClick={() => open(r.order_id)} title={`Open order ${r.order_number}`}
                      className={`cursor-pointer border-t border-border hover:bg-muted/40 ${cursor === i ? 'bg-accent text-accent-foreground' : ''}`}>
                      <td className={`${TD} font-medium text-primary`}>{r.order_number}</td>
                      <td className={TD}>{r.customer_name}</td>
                      <td className={`${TD} text-muted-foreground`}>{r.department_event ?? '—'}</td>
                      <td className={TD}>{r.shift_label ?? r.shift}</td>
                      <td className={`${TD} text-right tabular-nums`}>{r.lines}</td>
                      <td className={`${TD} text-right tabular-nums`}>{money(r.amount)}</td>
                      <td className={TD}>
                        <span className={`inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 text-xs font-medium ${STATUS[r.status].tone}`}>
                          <span className={`h-1.5 w-1.5 rounded-full ${STATUS[r.status].dot}`} />{STATUS[r.status].label}
                        </span>
                      </td>
                    </tr>,
                  ];
                })}
                {data && data.rows.length === 0 && (
                  <tr><td colSpan={7} className="px-4 py-6 text-center text-sm text-muted-foreground">No orders match. Try another day, shift or search.</td></tr>
                )}
              </tbody>
            </table>
          </div>
        )}
        {data && data.total > 0 && (
          <div className="flex flex-wrap items-center justify-between gap-2 border-t border-border px-3 py-2 text-xs text-muted-foreground">
            <span>Showing {((page - 1) * PAGE + 1).toLocaleString('en-US')}–{Math.min(page * PAGE, data.total).toLocaleString('en-US')} of {data.total.toLocaleString('en-US')} · ↑ ↓ move · Enter open · / search</span>
            <span className="flex gap-2">
              <button type="button" className="h-8 rounded-md border border-input bg-background px-3 text-sm text-foreground hover:bg-muted disabled:opacity-40" disabled={page <= 1} onClick={() => set({ page: String(page - 1) })}>‹ Previous</button>
              <button type="button" className="h-8 rounded-md border border-input bg-background px-3 text-sm text-foreground hover:bg-muted disabled:opacity-40" disabled={page >= pages} onClick={() => set({ page: String(page + 1) })}>Next ›</button>
            </span>
          </div>
        )}
      </section>
    </div>
  );
}

export default function ManageOrdersPage() {
  return <Suspense fallback={null}><ManageOrders /></Suspense>;
}
