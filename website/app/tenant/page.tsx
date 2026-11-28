import Link from 'next/link';
import { SalesCharts } from '@/components/features/dashboard/SalesCharts';
import { HealthChecksSidebar } from '@/components/features/dashboard/HealthChecksSidebar';
import { Suspense, cache } from 'react';
import { ArrowRight } from 'lucide-react';
import { SecurityTodo, type SecuritySignal } from '@/components/features/dashboard/SecurityTodo';
import { createClient } from '@/lib/supabase/server';
import { getCurrentTenantId } from '@/lib/supabase/tenant';

interface TodayOrder { order_id: number; order_number: string; customer_name: string | null; production_code: string | null; quantity: number | null; amount: number | null; line_count?: number; status?: string }
interface TodayOrders { today: string; order_count: number; total_amount: number; orders: TodayOrder[] }
interface Todo { kind: 'PRICEBOOK_NOT_IN_EFFECT'; customer_name: string; pricebook_name: string; assignment_type: string; status: string; is_active: boolean; effective_start_date: string; days_until_start: number }
interface Buckets { current_amt: number; d1_30: number; d31_60: number; d61_90: number; d90_plus: number; total: number }
interface Compare { value: number; previous: number; change_pct: number | null }
interface Metrics { today: string; revenue: Compare; orders: Compare; customers: Compare; units: Compare; avg_order: Compare; top_items: { item_description: string; quantity: number; pct: number }[] }
interface ArDashboard { as_of: string; totals: Buckets; accounts: { customer_id: string; customer_name: string; total: number; d90_plus: number; d60_plus: number }[] }

/** Whole-dollar or count display with the sign in front of the $ ("-$35,355", not "$-35,355"). */
const whole = (v: number, prefix = '') => `${v < 0 ? '-' : ''}${prefix}${Math.abs(Math.round(v)).toLocaleString('en-US')}`;

interface Figure { label: string; value: string; change?: number; note: string }
/** A headline figure from a value and its comparison. */
function figure(label: string, c: Compare | undefined, period: string, prefix?: string): Figure {
  return { label, value: whole(Number(c?.value ?? 0), prefix), change: c?.change_pct == null ? undefined : Number(c.change_pct), note: `vs ${whole(Number(c?.previous ?? 0), prefix)} ${period}` };
}

/** A titled panel: heading, optional sub-line and link on one compact row, then its content. */
function Panel({ title, sub, href, linkLabel, className, children }: { title: string; sub?: React.ReactNode; href?: string; linkLabel?: string; className?: string; children: React.ReactNode }) {
  return (
    <section className={`min-w-0 overflow-hidden rounded-lg border border-border bg-card text-card-foreground shadow-sm ${className ?? ''}`}>
      <div className="flex min-h-[40px] items-center justify-between gap-3 border-b border-border px-4 py-1.5">
        <div className="flex min-w-0 flex-wrap items-baseline gap-x-3">
          <h2 className="text-sm font-semibold">{title}</h2>
          {sub && <span className="text-xs text-muted-foreground">{sub}</span>}
        </div>
        {href && (
          <Link href={href} className="inline-flex shrink-0 items-center gap-1 rounded text-xs font-medium text-primary hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
            {linkLabel} <ArrowRight className="h-3 w-3" />
          </Link>
        )}
      </div>
      {children}
    </section>
  );
}
const TH = 'h-8 whitespace-nowrap bg-muted/50 px-4 text-[11px] font-semibold uppercase tracking-wider text-muted-foreground';
const TD = 'px-4 py-1.5';
/** Order stage (from om_orders_today_get): label and status colour. */
const STAGE: Record<string, { label: string; cls: string; dot: string }> = {
  INVOICED: { label: 'Invoiced', cls: 'bg-success-soft text-success', dot: 'bg-success' },
  SHIPPED: { label: 'Shipped', cls: 'bg-info-soft text-info', dot: 'bg-info' },
  IN_PRODUCTION: { label: 'In production', cls: 'bg-warning-soft text-warning', dot: 'bg-warning' },
  OPEN: { label: 'Open', cls: 'bg-muted text-muted-foreground', dot: 'bg-muted-foreground' },
};
const EMPTY = 'px-4 py-3 text-sm text-muted-foreground';

/** Money with the sign in front of the $ ("-$5,768.69"). */
const money = (v: number | null | undefined) => { const n = Number(v ?? 0); return `${n < 0 ? '-' : ''}$${Math.abs(n).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`; };

export const dynamic = 'force-dynamic';

/** AR figures, read once per request and shared by the Outstanding AR figure and both AR panels, which stream in after the rest. */
const loadAr = cache(async (tenantId: number): Promise<ArDashboard | null> => {
  const { data } = await (await createClient()).rpc('ar_dashboard_get', { p_tenant_id: tenantId, p_limit: 8 });
  return (data ?? null) as ArDashboard | null;
});

/** One cell of the key-figures strip. */
function FigureCell({ f }: { f: Figure }) {
  return (
    <div className="min-w-0 border-b border-r border-border px-4 py-3 text-center">
      <p className="truncate text-[11px] font-semibold uppercase tracking-wider text-muted-foreground" title={f.label}>{f.label}</p>
      <p className="mt-0.5 text-2xl font-semibold tabular-nums tracking-tight">{f.value}</p>
      <p className="mt-0.5 text-xs text-muted-foreground">
        {f.change !== undefined && (
          <span className={`mr-1.5 font-semibold tabular-nums ${f.change >= 0 ? 'text-success' : 'text-destructive'}`}>
            {f.change >= 0 ? '▲' : '▼'} {Math.abs(f.change)}%
          </span>
        )}
        {f.note}
      </p>
    </div>
  );
}

/** Placeholder of the same size while AR figures load. */
function Pending({ label, rows = 0 }: { label?: string; rows?: number }) {
  if (label) {
    return (
      <div className="min-w-0 border-b border-r border-border px-4 py-3 text-center" aria-busy="true">
        <p className="truncate text-[11px] font-semibold uppercase tracking-wider text-muted-foreground">{label}</p>
        <p className="mx-auto mt-1.5 h-6 w-28 animate-pulse rounded bg-muted" />
        <p className="mx-auto mt-1.5 h-3 w-36 animate-pulse rounded bg-muted" />
      </div>
    );
  }
  return (
    <div className="space-y-2 px-4 py-3" aria-busy="true" aria-label="Loading">
      {Array.from({ length: rows }, (_, i) => <div key={i} className="h-5 animate-pulse rounded bg-muted/70" />)}
    </div>
  );
}

async function ArFigure({ tenantId }: { tenantId: number }) {
  const ar = await loadAr(tenantId);
  if (!ar) return null;
  return <FigureCell f={{ label: 'Outstanding AR', value: whole(Number(ar.totals.total), '$'), note: `over 90 days: ${whole(Number(ar.totals.d90_plus), '$')}` }} />;
}

/** AR aging as vertical bars, one per age bucket, each labelled with its amount; bucket colours keep their status meaning. */
async function ArAging({ tenantId }: { tenantId: number }) {
  const ar = await loadAr(tenantId);
  if (!ar) return <p className={EMPTY}>AR aging is not available.</p>;
  const buckets = [
    { label: '1–30 Days', amount: Number(ar.totals.d1_30), color: 'bg-info' },
    { label: '30 Days +', amount: Number(ar.totals.d31_60), color: 'bg-warning' },
    { label: '60 Days +', amount: Number(ar.totals.d61_90), color: 'bg-destructive opacity-60' },
    { label: '90 Days +', amount: Number(ar.totals.d90_plus), color: 'bg-destructive' },
  ];
  const max = Math.max(1, ...buckets.map((b) => b.amount));
  return (
    <div className="px-4 pb-3 pt-2">
      <div className="mb-2 flex items-baseline justify-between text-xs text-muted-foreground">
        <span>Days past due</span>
        <span>Total AR <span className="font-semibold tabular-nums text-foreground">{money(ar.totals.total)}</span></span>
      </div>
      <div className="grid h-[200px] grid-cols-4 items-end gap-3 border-b border-border">
        {buckets.map((b) => (
          <div key={b.label} className="flex h-full flex-col items-center justify-end gap-1" title={`${b.label}: ${money(b.amount)}`}>
            <span className="text-[11px] font-medium tabular-nums">{money(Math.round(b.amount))}</span>
            <div className={`w-full max-w-[88px] rounded-t ${b.color}`} style={{ height: `${(Math.max(b.amount, 0) / max) * 80}%` }} />
          </div>
        ))}
      </div>
      <div className="grid grid-cols-4 gap-3 pt-1">
        {buckets.map((b) => <span key={b.label} className="text-center text-[11px] text-muted-foreground">{b.label}</span>)}
      </div>
    </div>
  );
}

export default async function TenantDashboardPage() {
  const supabase = await createClient();
  const tenantId = await getCurrentTenantId();
  if (tenantId !== null) void loadAr(tenantId);   // start the AR read now; its panels wait for it, the rest of the page does not
  const [areasRes, ordersRes, todoRes, metricsRes] = tenantId === null
    ? [null, null, null, null]
    : await Promise.all([
        supabase.rpc('fnd_my_areas'),
        supabase.rpc('om_orders_today_get', { p_tenant_id: tenantId, p_limit: 8 }),
        supabase.rpc('fnd_todos_get', { p_tenant_id: tenantId }),
        supabase.rpc('om_dashboard_metrics_get', { p_tenant_id: tenantId }),
      ]);
  const areas = Array.isArray(areasRes?.data) ? (areasRes!.data as string[]) : [];
  const todays = (ordersRes?.data ?? null) as TodayOrders | null;
  const m = (metricsRes?.data ?? null) as Metrics | null;
  const allTodos = (Array.isArray(todoRes?.data) ? todoRes!.data : []) as (Todo | SecuritySignal)[];
  const signals = allTodos.filter((t): t is SecuritySignal => t.kind === 'INACTIVE_USER' || t.kind === 'NEW_LOCATION' || t.kind === 'EMAIL_REUSE');
  const todos = allTodos.filter((t): t is Todo => t.kind === 'PRICEBOOK_NOT_IN_EFFECT');
  const showAr = tenantId !== null && areas.includes('financials.aging');
  const showOrders = areas.includes('orders.manage') || areas.includes('orders.enter');
  const dateLabel = todays
    ? new Date(`${todays.today}T12:00:00`).toLocaleDateString('en-US', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })
    : '';

  const figures: Figure[] = [
    ...(showAr ? [figure('Revenue, month to date', m?.revenue, 'last month', '$')] : []),
    ...(showOrders ? [
      figure('Orders today', m?.orders, 'yesterday'),
      figure('Units today', m?.units, 'yesterday'),
      figure('Active customers, 30 days', m?.customers, 'prior 30'),
      figure('Average order', m?.avg_order, 'last month', '$'),
    ] : []),
  ];

  return (
    <div className="space-y-3 py-3">
      {areas.includes('admin.health') && <HealthChecksSidebar />}
      <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
        <h1 className="text-lg font-semibold tracking-tight">Dashboard</h1>
        <p className="text-sm text-muted-foreground">{dateLabel}</p>
      </div>

      {(figures.length > 0 || showAr) && (
        <section aria-label="Key figures" className="overflow-hidden rounded-lg border border-border bg-card shadow-sm">
          <div className="-mb-px -mr-px grid grid-cols-2 md:grid-cols-3 xl:grid-cols-6">
            {figures.map((f) => <FigureCell key={f.label} f={f} />)}
            {showAr && (
              <Suspense fallback={<Pending label="Outstanding AR" />}>
                <ArFigure tenantId={tenantId!} />
              </Suspense>
            )}
          </div>
        </section>
      )}

      {showAr && (
        <SalesCharts
          tenantId={tenantId!}
          extra={(
            <Panel title="AR Aging" sub={todays ? `As of ${todays.today}` : undefined} href="/financials/aging" linkLabel="Report">
              <Suspense fallback={<Pending rows={6} />}><ArAging tenantId={tenantId!} /></Suspense>
            </Panel>
          )}
        />
      )}

      {(todos.length > 0 || signals.length > 0) && (
        <Panel title="To-Do's" sub={`${todos.length + signals.length} item${todos.length + signals.length === 1 ? '' : 's'} need attention`} className="border-warning/50">
          {signals.length > 0 && (
            <ul className="divide-y divide-border border-b border-border" aria-label="Security">
              {signals.map((sg) => <SecurityTodo key={`${sg.kind}-${sg.user_id}-${sg.city ?? ''}-${sg.event_id ?? ''}`} tenantId={tenantId!} signal={sg} />)}
            </ul>
          )}
          {todos.length > 0 && <p className="px-4 pt-2 text-xs text-muted-foreground">Pricing books not in effect yet. Approve and activate them on the customer&apos;s Pricing tab.</p>}
          <ul className="divide-y divide-border">
            {todos.map((t, i) => (
              <li key={i} className="flex flex-wrap items-center gap-x-3 gap-y-1 px-4 py-1.5 text-sm">
                <span className="font-medium">{t.pricebook_name}</span>
                <span className="text-muted-foreground">{t.assignment_type} for {t.customer_name}</span>
                <span className="text-muted-foreground">
                  {t.days_until_start > 0 ? `starts in ${t.days_until_start} day${t.days_until_start === 1 ? '' : 's'}` : t.days_until_start === 0 ? 'starts today' : `started ${-t.days_until_start} day${t.days_until_start === -1 ? '' : 's'} ago`}
                  {' '}({t.effective_start_date})
                </span>
                <span className="ml-auto rounded bg-warning-soft px-2 py-0.5 text-xs font-medium text-warning">{t.is_active ? t.status : `${t.status}, inactive`}</span>
              </li>
            ))}
          </ul>
        </Panel>
      )}

      <div className="grid grid-cols-1 gap-3 lg:grid-cols-3">
        <Panel
          className="lg:col-span-2"
          title="Today's Orders"
          sub={todays && showOrders ? `${todays.order_count} order${todays.order_count === 1 ? '' : 's'} for production today · ${money(todays.total_amount)}` : undefined}
          href="/manage-orders" linkLabel="View all"
        >
          {!showOrders ? (
            <p className={EMPTY}>Orders are not available to your role.</p>
          ) : !todays || todays.orders.length === 0 ? (
            <p className={EMPTY}>No orders are scheduled for production today.</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="text-left">
                  <tr><th className={TH}>Order</th><th className={TH}>Customer</th><th className={TH}>Production</th><th className={`${TH} text-right`}>Lines</th><th className={`${TH} text-right`}>Qty</th><th className={`${TH} text-right`}>Amount</th><th className={TH}>Status</th></tr>
                </thead>
                <tbody>
                  {todays.orders.map((o) => (
                    <tr key={o.order_id} className="border-t border-border hover:bg-muted/40">
                      <td className={TD}><Link className="font-medium text-primary hover:underline" href={`/orders/${o.order_id}/edit`}>{o.order_number}</Link></td>
                      <td className={TD}>{o.customer_name}</td>
                      <td className={`${TD} text-muted-foreground`}>{o.production_code}</td>
                      <td className={`${TD} text-right`}>{Number(o.line_count ?? 0).toLocaleString('en-US')}</td>
                      <td className={`${TD} text-right`}>{Number(o.quantity ?? 0).toLocaleString('en-US')}</td>
                      <td className={`${TD} text-right`}>{money(o.amount)}</td>
                      <td className={TD}>
                        {STAGE[o.status ?? ''] && (
                          <span className={`inline-flex items-center gap-1.5 whitespace-nowrap rounded-full px-2 py-0.5 text-xs font-medium ${STAGE[o.status!].cls}`}>
                            <span className={`h-1.5 w-1.5 rounded-full ${STAGE[o.status!].dot}`} />{STAGE[o.status!].label}
                          </span>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          {todays && showOrders && todays.order_count > todays.orders.length && (
            <p className="border-t border-border px-4 py-1.5 text-xs text-muted-foreground">and {todays.order_count - todays.orders.length} more</p>
          )}
        </Panel>

        <Panel title="Production Summary" sub="Most units for production today">
          {!showOrders ? (
            <p className={EMPTY}>Production is not available to your role.</p>
          ) : !m || m.top_items.length === 0 ? (
            <p className={EMPTY}>Nothing is scheduled for production today.</p>
          ) : (
            <ul className="space-y-2 px-4 py-3">
              {m.top_items.map((item) => (
                <li key={item.item_description} className="flex items-center gap-3 text-sm">
                  <span className="w-2/5 shrink-0 truncate" title={item.item_description}>{item.item_description}</span>
                  <span className="h-2 min-w-0 flex-1 rounded-sm bg-muted"><span className="block h-2 rounded-sm bg-primary" style={{ width: `${item.pct}%` }} /></span>
                  <span className="w-14 shrink-0 text-right tabular-nums">{Number(item.quantity).toLocaleString('en-US')}</span>
                </li>
              ))}
            </ul>
          )}
        </Panel>
      </div>

    </div>
  );
}
