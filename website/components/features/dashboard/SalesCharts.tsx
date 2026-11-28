'use client';

import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { ArrowRight } from 'lucide-react';

interface Month { month: number; this: number; last: number }
interface Part { name: string; this: number; last: number; other: boolean }
interface SalesData {
  as_of: string; last_as_of: string; year: number; last_year: number;
  months: Month[]; totals: { this: number; last: number };
  accounts: { customer_id: number; customer_name: string; this: number }[];
  segments: { code: string | null; label: string; this: number; last: number }[];
  items: { item_id: number | null; name: string; this: number; last: number; other: boolean }[];
}

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const CAT = [1, 2, 3, 4, 5, 6, 7].map((i) => `var(--chart-cat-${i})`);
const money = (v: number) => `${v < 0 ? '-' : ''}$${Math.abs(Math.round(v)).toLocaleString('en-US')}`;
const thousands = (v: number) => `${v < 0 ? '-' : ''}$${Math.round(Math.abs(v) / 1000).toLocaleString('en-US')}K`;
const change = (now: number, last: number) => (last > 0 ? Math.round(((now - last) / last) * 1000) / 10 : null);
/** "▲ 6.4%" in success, "▼ 3%" in destructive, "new" when there was nothing last year. */
function Change({ now, last, decimals = true }: { now: number; last: number; decimals?: boolean }) {
  const c = change(now, last);
  if (c === null) return <span className="font-semibold text-success">new</span>;
  const shown = decimals ? Math.abs(c) : Math.round(Math.abs(c));
  return <span className={`font-semibold tabular-nums ${c >= 0 ? 'text-success' : 'text-destructive'}`}>{c >= 0 ? '▲' : '▼'} {shown}%</span>;
}

function Card({ title, sub, action, children }: { title: string; sub?: React.ReactNode; action?: React.ReactNode; children: React.ReactNode }) {
  return (
    <section className="flex min-w-0 flex-col overflow-hidden rounded-lg border border-border bg-card text-card-foreground shadow-sm">
      <div className="flex min-h-[40px] flex-wrap items-center gap-x-3 gap-y-1 border-b border-border px-4 py-1.5">
        <h2 className="text-sm font-semibold">{title}</h2>
        {sub && <span className="text-xs text-muted-foreground">{sub}</span>}
        {action && <div className="ml-auto flex items-center gap-3">{action}</div>}
      </div>
      {children}
    </section>
  );
}

function Legend({ year, lastYear }: { year: number; lastYear: number }) {
  return (
    <span className="inline-flex items-center gap-3 text-xs text-muted-foreground">
      <span className="inline-flex items-center gap-1.5"><span className="h-2.5 w-2.5 rounded-sm" style={{ background: 'var(--chart-this)' }} />{year}</span>
      <span className="inline-flex items-center gap-1.5"><span className="h-2.5 w-2.5 rounded-sm" style={{ background: 'var(--chart-last)' }} />{lastYear}</span>
    </span>
  );
}

/** Overlapping bars by month: both years in the same place, the taller behind and the shorter in front (outlined), so neither hides. */
function MonthBars({ data }: { data: SalesData }) {
  const max = Math.max(1, ...data.months.flatMap((m) => [m.this, m.last]));
  const step = max <= 50_000 ? 10_000 : max <= 200_000 ? 50_000 : max <= 500_000 ? 100_000 : 250_000;
  const top = Math.ceil(max / step) * step;
  const ticks = Array.from({ length: Math.round(top / step) + 1 }, (_, i) => i * step);
  const lastMonth = Number(data.as_of.slice(5, 7));
  const n = data.months.length;
  return (
    <div className="grid grid-cols-[44px_minmax(0,1fr)] gap-x-1.5 px-4 pb-2 pt-1">
      <div className="relative h-[180px]" aria-hidden="true">
        {ticks.map((t) => (
          <span key={t} className="absolute right-0 translate-y-1/2 text-[11px] tabular-nums text-muted-foreground" style={{ bottom: `${(t / top) * 100}%` }}>
            {t === 0 ? '0' : `${t / 1000}K`}
          </span>
        ))}
      </div>
      <div className="relative h-[180px] border-b border-border">
        {ticks.map((t) => <div key={t} className="absolute inset-x-0 border-t border-border/50" style={{ bottom: `${(t / top) * 100}%` }} aria-hidden="true" />)}
        <div className="absolute inset-0 grid" style={{ gridTemplateColumns: `repeat(${n}, minmax(0, 1fr))` }}>
          {data.months.map((m) => {
            const label = `${MONTHS[m.month - 1]}${m.month === lastMonth ? ` (1–${Number(data.as_of.slice(8, 10))})` : ''}: ${data.year} ${money(m.this)}, ${data.last_year} ${money(m.last)}`;
            const bars = [{ v: m.last, color: 'var(--chart-last)' }, { v: m.this, color: 'var(--chart-this)' }].sort((p, q) => q.v - p.v);
            return (
              <div key={m.month} title={label} aria-label={label} role="img" className="relative rounded-t hover:bg-muted/40">
                {bars.map((b, i) => (
                  <div key={i} className={`absolute bottom-0 left-1/2 w-[calc(100%-8px)] max-w-[28px] -translate-x-1/2 rounded-t ${i === 1 ? 'ring-2 ring-card' : ''}`}
                    style={{ height: `${(Math.max(b.v, 0) / top) * 100}%`, background: b.color }} />
                ))}
              </div>
            );
          })}
        </div>
      </div>
      <div />
      <div className="grid pt-1" style={{ gridTemplateColumns: `repeat(${n}, minmax(0, 1fr))` }} aria-hidden="true">
        {data.months.map((m) => <span key={m.month} className="text-center text-[11px] text-muted-foreground">{MONTHS[m.month - 1]}</span>)}
      </div>
    </div>
  );
}

/** A pie of this year's shares with a legend: amount, share and change vs last year. The "other" slice is gray. */
function Pie({ parts, label, year, lastYear }: { parts: Part[]; label: string; year: number; lastYear: number }) {
  const shown = parts.filter((p) => p.this > 0);
  const total = shown.reduce((a, p) => a + p.this, 0);
  let angle = 0;
  const slices = shown.map((p, i) => {
    const a0 = angle;
    const a1 = angle + (total ? (p.this / total) * Math.PI * 2 : 0);
    angle = a1;
    const full = a1 - a0 >= Math.PI * 2 - 1e-6;
    const d = full
      ? 'M 1 0 A 1 1 0 1 1 -1 0 A 1 1 0 1 1 1 0 Z'
      : `M 0 0 L ${Math.cos(a0).toFixed(4)} ${Math.sin(a0).toFixed(4)} A 1 1 0 ${a1 - a0 > Math.PI ? 1 : 0} 1 ${Math.cos(a1).toFixed(4)} ${Math.sin(a1).toFixed(4)} Z`;
    const pct = total ? Math.round((p.this / total) * 100) : 0;
    return { ...p, d, pct, color: p.other ? 'var(--chart-other)' : CAT[i % CAT.length], tip: `${p.name}: ${year} ${money(p.this)} (${pct}%), ${lastYear} ${money(p.last)}` };
  });
  if (slices.length === 0) return <p className="px-4 py-6 text-sm text-muted-foreground">No sales yet this year.</p>;
  return (
    <div className="flex flex-wrap items-center gap-4 px-4 py-3">
      <svg width="170" height="170" viewBox="-1 -1 2 2" role="img" aria-label={label} className="-rotate-90 shrink-0">
        {slices.map((s) => <path key={s.name} d={s.d} fill={s.color} stroke="hsl(var(--card))" strokeWidth={0.02} className="hover:opacity-85"><title>{s.tip}</title></path>)}
      </svg>
      <div className="min-w-[200px] flex-1 space-y-1">
        <div className="grid grid-cols-[10px_minmax(0,1fr)_52px_36px_52px] gap-x-2 text-[11px] text-muted-foreground">
          <span /><span /><span className="text-right">{year}</span><span className="text-right">Share</span><span className="text-right">vs {lastYear}</span>
        </div>
        {slices.map((s) => (
          <div key={s.name} title={s.tip} className="grid grid-cols-[10px_minmax(0,1fr)_52px_36px_52px] items-center gap-x-2 text-xs">
            <span className="h-2.5 w-2.5 rounded-sm" style={{ background: s.color }} />
            <span className={`truncate ${s.other ? 'text-muted-foreground' : ''}`}>{s.name}</span>
            <span className="text-right tabular-nums text-muted-foreground">{thousands(s.this)}</span>
            <span className="text-right font-semibold tabular-nums">{s.pct}%</span>
            <span className="text-right"><Change now={s.this} last={s.last} decimals={false} /></span>
          </div>
        ))}
      </div>
    </div>
  );
}

/**
 * Dashboard: year-to-date sales against the same days of last year, from ar_sales_dashboard_get.
 * AR Aging first (passed in as extra), then By account (overlapping monthly bars, one account or all), by segment and by item (pies of this year's shares with the change vs last year).
 */
export function SalesCharts({ tenantId, extra }: { tenantId: number; /** the first card in the grid (AR Aging) */ extra?: React.ReactNode }) {
  const [accountId, setAccountId] = useState<string>('');
  const [data, setData] = useState<SalesData | null>(null);
  const [failed, setFailed] = useState<string | null>(null);

  useEffect(() => {
    let live = true;
    const qs = new URLSearchParams({ tenant_id: String(tenantId) });
    if (accountId) qs.set('account_id', accountId);
    fetch(`/api/dashboard/sales?${qs}`)
      .then((r) => r.json())
      .then((j: { data?: SalesData; error?: string }) => { if (!live) return; if (j.error || !j.data) setFailed(j.error ?? 'No data'); else { setData(j.data); setFailed(null); } })
      .catch((e: Error) => live && setFailed(e.message));
    return () => { live = false; };
  }, [tenantId, accountId]);

  const segments = useMemo<Part[]>(() => (data?.segments ?? []).map((s) => ({ name: s.label, this: s.this, last: s.last, other: s.code === null })), [data]);
  const items = useMemo<Part[]>(() => (data?.items ?? []).map((i) => ({ name: i.name, this: i.this, last: i.last, other: i.other })), [data]);
  const unassignedOnly = segments.length > 0 && segments.every((s) => s.other);

  if (failed) return <p className="text-sm text-muted-foreground">Couldn&apos;t load the sales charts: {failed}</p>;
  if (!data) return <div className="h-[290px] animate-pulse rounded-lg border border-border bg-muted/40" aria-busy="true" aria-label="Loading sales charts" />;

  return (
    <section aria-label="Sales, year to date" className="space-y-2">
      <div className="grid gap-3 md:grid-cols-2">
        {extra}
        <Card
          title="YTD Sales By Account"
          action={(
            <>
              <label className="sr-only" htmlFor="sales-account">Account</label>
              <select id="sales-account" value={accountId} onChange={(e) => setAccountId(e.target.value)}
                className="h-7 max-w-[200px] rounded-md border border-input bg-background px-1.5 text-xs focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
                <option value="">All accounts</option>
                {data.accounts.map((a) => <option key={a.customer_id} value={a.customer_id}>{a.customer_name}</option>)}
              </select>
              <Legend year={data.year} lastYear={data.last_year} />
            </>
          )}
        >
          <div className="flex items-baseline justify-between px-4 pt-2 text-xs text-muted-foreground">
            <span className="tabular-nums">{thousands(data.totals.this)} vs {thousands(data.totals.last)} last year</span>
            <Change now={data.totals.this} last={data.totals.last} />
          </div>
          <MonthBars data={data} />
        </Card>
        <Card title="YTD Sales By Segment" sub={`${data.year} share of sales, vs ${data.last_year}`}
          action={<Link href="/customers" className="inline-flex items-center gap-1 text-xs font-medium text-primary hover:underline">Customers <ArrowRight className="h-3 w-3" /></Link>}>
          {unassignedOnly && (
            <p className="mx-4 mt-2 rounded bg-warning-soft px-2.5 py-1.5 text-xs text-warning">
              No account has a Segment yet. Set it on each account (Customers › Profile) to split this chart.
            </p>
          )}
          <Pie parts={segments} label={`Sales by segment, ${data.year}`} year={data.year} lastYear={data.last_year} />
        </Card>
        <Card title="YTD Sales By Item" sub={`${data.year} share of sales, vs ${data.last_year}`}>
          <Pie parts={items} label={`Sales by item, ${data.year}`} year={data.year} lastYear={data.last_year} />
        </Card>
      </div>
    </section>
  );
}
