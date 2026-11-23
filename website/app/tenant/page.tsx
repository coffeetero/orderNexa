import Link from 'next/link';
import {
  DollarSign,
  ShoppingCart,
  Users,
  ChefHat,
  Receipt,
  TrendingUp,
  ArrowRight,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { MetricCard } from '@/components/features/account/MetricCard';
import { mockTenantMetrics } from '@/lib/mock-data';
import { createClient } from '@/lib/supabase/server';
import { getCurrentTenantId } from '@/lib/supabase/tenant';

interface TodayOrder { order_id: number; order_number: string; customer_name: string | null; production_code: string | null; quantity: number | null; amount: number | null }
interface TodayOrders { today: string; order_count: number; total_amount: number; orders: TodayOrder[] }
interface Todo { kind: string; customer_name: string; pricebook_name: string; assignment_type: string; status: string; is_active: boolean; effective_start_date: string; days_until_start: number }
interface Buckets { current_amt: number; d1_30: number; d31_60: number; d61_90: number; d90_plus: number; total: number }
interface ArDashboard { as_of: string; totals: Buckets; accounts: { customer_id: string; customer_name: string; total: number; d90_plus: number }[] }

const money = (v: number | null | undefined) => `$${Number(v ?? 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

export const dynamic = 'force-dynamic';

export default async function TenantDashboardPage() {
  const supabase = createClient();
  const tenantId = await getCurrentTenantId();
  const [areasRes, ordersRes, arRes, todoRes] = tenantId === null
    ? [null, null, null, null]
    : await Promise.all([
        supabase.rpc('fnd_my_areas'),
        supabase.rpc('om_orders_today_get', { p_tenant_id: tenantId, p_limit: 8 }),
        supabase.rpc('ar_dashboard_get', { p_tenant_id: tenantId, p_limit: 8 }),
        supabase.rpc('fnd_todos_get', { p_tenant_id: tenantId }),
      ]);
  const areas = Array.isArray(areasRes?.data) ? (areasRes!.data as string[]) : [];
  const todays = (ordersRes?.data ?? null) as TodayOrders | null;
  const ar = (arRes?.data ?? null) as ArDashboard | null;
  const todos = (Array.isArray(todoRes?.data) ? todoRes!.data : []) as Todo[];
  const showAr = areas.includes('financials.aging');
  const showOrders = areas.includes('orders.manage') || areas.includes('orders.enter');
  const dateLabel = todays
    ? new Date(`${todays.today}T12:00:00`).toLocaleDateString('en-US', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })
    : '';

  return (
    <div className="space-y-6">
      <div>
        <p className="text-sm text-muted-foreground">
          {dateLabel}
        </p>
      </div>

      <div className="grid grid-cols-2 gap-4 lg:grid-cols-3 xl:grid-cols-6">
        <MetricCard
          metric={mockTenantMetrics.totalRevenue}
          icon={DollarSign}
          accentColor="bg-success/10 text-success"
        />
        <MetricCard
          metric={mockTenantMetrics.totalOrders}
          icon={ShoppingCart}
          accentColor="bg-info/10 text-info"
        />
        <MetricCard
          metric={mockTenantMetrics.activeCustomers}
          icon={Users}
          accentColor="bg-primary/10 text-primary"
        />
        <MetricCard
          metric={mockTenantMetrics.productionToday}
          icon={ChefHat}
          accentColor="bg-warning/10 text-warning"
        />
        <MetricCard
          metric={mockTenantMetrics.outstandingAR}
          icon={Receipt}
          accentColor="bg-orange-500/10 text-orange-600 dark:text-orange-400"
        />
        <MetricCard
          metric={mockTenantMetrics.avgOrderValue}
          icon={TrendingUp}
          accentColor="bg-violet-500/10 text-violet-600 dark:text-violet-400"
        />
      </div>

      {todos.length > 0 && (
        <Card className="border-warning/40">
          <CardHeader className="pb-3">
            <CardTitle
              className="text-base font-semibold"
              style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
            >
              To-Do&apos;s
            </CardTitle>
          </CardHeader>
          <CardContent className="p-0 pb-1">
            <ul className="divide-y divide-border/40">
              {todos.map((t, i) => (
                <li key={i} className="flex flex-wrap items-center gap-x-3 gap-y-1 px-6 py-2 text-sm">
                  <span className="font-medium">{t.pricebook_name}</span>
                  <span className="text-muted-foreground">{t.assignment_type} for {t.customer_name}</span>
                  <span className="text-muted-foreground">
                    {t.days_until_start > 0 ? `starts in ${t.days_until_start} day${t.days_until_start === 1 ? '' : 's'}` : t.days_until_start === 0 ? 'starts today' : `started ${-t.days_until_start} day${t.days_until_start === -1 ? '' : 's'} ago`}
                    {' '}({t.effective_start_date})
                  </span>
                  <span className="ml-auto rounded bg-warning/15 px-2 py-0.5 text-xs text-warning">{t.is_active ? t.status : `${t.status}, inactive`}</span>
                </li>
              ))}
            </ul>
            <p className="px-6 pb-2 pt-1 text-xs text-muted-foreground">These pricing books are not in effect yet. Approve and activate them on the customer&apos;s Pricing tab.</p>
          </CardContent>
        </Card>
      )}

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <Card className="border-border/60 col-span-1 lg:col-span-2">
          <CardHeader className="flex flex-row items-center justify-between pb-3">
            <div>
              <CardTitle
                className="text-base font-semibold"
                style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
              >
                Today&apos;s Orders
              </CardTitle>
              {todays && showOrders && (
                <p className="mt-0.5 text-xs text-muted-foreground">
                  {todays.order_count} order{todays.order_count === 1 ? '' : 's'} for production today · {money(todays.total_amount)}
                </p>
              )}
            </div>
            <Button asChild variant="ghost" size="sm" className="text-xs text-primary gap-1">
              <Link href="/manage-orders">
                View all <ArrowRight className="h-3 w-3" />
              </Link>
            </Button>
          </CardHeader>
          <CardContent className="p-0 pb-1">
            {!showOrders ? (
              <p className="px-6 py-4 text-sm text-muted-foreground">Orders are not available to your role.</p>
            ) : !todays || todays.orders.length === 0 ? (
              <p className="px-6 py-4 text-sm text-muted-foreground">No orders are scheduled for production today.</p>
            ) : (
              <table className="w-full text-sm">
                <thead className="text-left text-xs text-muted-foreground">
                  <tr><th className="px-6 py-2">Order</th><th className="px-3 py-2">Customer</th><th className="px-3 py-2">Production</th><th className="px-3 py-2 text-right">Qty</th><th className="px-6 py-2 text-right">Amount</th></tr>
                </thead>
                <tbody>
                  {todays.orders.map((o) => (
                    <tr key={o.order_id} className="border-t border-border/40">
                      <td className="px-6 py-2 font-mono text-xs"><Link className="text-primary hover:underline" href={`/orders/${o.order_id}/edit`}>{o.order_number}</Link></td>
                      <td className="px-3 py-2">{o.customer_name}</td>
                      <td className="px-3 py-2 text-xs text-muted-foreground">{o.production_code}</td>
                      <td className="px-3 py-2 text-right tabular-nums">{Number(o.quantity ?? 0).toLocaleString('en-US')}</td>
                      <td className="px-6 py-2 text-right tabular-nums">{money(o.amount)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
            {todays && todays.order_count > todays.orders.length && (
              <p className="px-6 pb-2 pt-1 text-xs text-muted-foreground">and {todays.order_count - todays.orders.length} more</p>
            )}
          </CardContent>
        </Card>

        <Card className="border-border/60">
          <CardHeader className="pb-3">
            <CardTitle
              className="text-base font-semibold"
              style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
            >
              Production Summary
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            {[
              { label: 'Baguette Tradition', qty: 420, unit: 'pcs', pct: 68 },
              { label: 'Pain de Campagne', qty: 180, unit: 'loaves', pct: 45 },
              { label: 'Croissant au Beurre', qty: 360, unit: 'pcs', pct: 72 },
              { label: 'Focaccia Genovese', qty: 90, unit: 'pcs', pct: 30 },
              { label: 'Pane di Altamura', qty: 60, unit: 'loaves', pct: 25 },
            ].map((item) => (
              <div key={item.label}>
                <div className="flex items-center justify-between mb-1">
                  <span className="text-xs font-medium text-foreground">{item.label}</span>
                  <span className="text-xs text-muted-foreground tabular-nums">
                    {item.qty} {item.unit}
                  </span>
                </div>
                <div className="h-1.5 w-full rounded-full bg-muted">
                  <div
                    className="h-1.5 rounded-full bg-primary transition-all"
                    style={{ width: `${item.pct}%` }}
                  />
                </div>
              </div>
            ))}
          </CardContent>
        </Card>
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Card className="border-border/60">
          <CardHeader className="flex flex-row items-center justify-between pb-3">
            <CardTitle
              className="text-base font-semibold"
              style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
            >
              Customer Accounts
            </CardTitle>
            <Button asChild variant="ghost" size="sm" className="text-xs text-primary gap-1">
              <Link href="/customers">
                View all <ArrowRight className="h-3 w-3" />
              </Link>
            </Button>
          </CardHeader>
          <CardContent className="p-0 pb-1">
            {!showAr ? (
              <p className="px-6 py-4 text-sm text-muted-foreground">Balances are not available to your role.</p>
            ) : !ar || ar.accounts.length === 0 ? (
              <p className="px-6 py-4 text-sm text-muted-foreground">No account has an open balance.</p>
            ) : (
              <table className="w-full text-sm">
                <thead className="text-left text-xs text-muted-foreground">
                  <tr><th className="px-6 py-2">Account</th><th className="px-3 py-2 text-right">Balance</th><th className="px-6 py-2 text-right">Over 90 days</th></tr>
                </thead>
                <tbody>
                  {ar.accounts.map((a) => (
                    <tr key={a.customer_id} className="border-t border-border/40">
                      <td className="px-6 py-2">{a.customer_name}</td>
                      <td className="px-3 py-2 text-right tabular-nums">{money(a.total)}</td>
                      <td className={`px-6 py-2 text-right tabular-nums ${Number(a.d90_plus) > 0 ? 'font-medium text-destructive' : ''}`}>{money(a.d90_plus)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </CardContent>
        </Card>

        <Card className="border-border/60">
          <CardHeader className="flex flex-row items-center justify-between pb-3">
            <div>
              <CardTitle
                className="text-base font-semibold"
                style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
              >
                AR Aging
              </CardTitle>
              {ar && showAr && <p className="mt-0.5 text-xs text-muted-foreground">As of {ar.as_of}</p>}
            </div>
            <Button asChild variant="ghost" size="sm" className="text-xs text-primary gap-1">
              <Link href="/financials/aging">
                Report <ArrowRight className="h-3 w-3" />
              </Link>
            </Button>
          </CardHeader>
          <CardContent className="space-y-4">
            {!showAr || !ar ? (
              <p className="text-sm text-muted-foreground">AR aging is not available to your role.</p>
            ) : (
              <>
                {[
                  { label: 'Current', amount: ar.totals.current_amt, color: 'bg-success' },
                  { label: '1–30 days', amount: ar.totals.d1_30, color: 'bg-info' },
                  { label: '31–60 days', amount: ar.totals.d31_60, color: 'bg-warning' },
                  { label: '61–90 days', amount: ar.totals.d61_90, color: 'bg-orange-500' },
                  { label: 'Over 90 days', amount: ar.totals.d90_plus, color: 'bg-destructive' },
                ].map((bucket) => (
                  <div key={bucket.label} className="flex items-center justify-between">
                    <div className="flex items-center gap-2.5">
                      <div className={`h-2.5 w-2.5 rounded-full ${bucket.color}`} />
                      <span className="text-sm text-foreground">{bucket.label}</span>
                    </div>
                    <span className="text-sm font-semibold tabular-nums text-foreground">{money(bucket.amount)}</span>
                  </div>
                ))}
                <div className="pt-3 border-t border-border flex items-center justify-between">
                  <span className="text-sm font-semibold text-foreground">Total AR</span>
                  <span className="text-sm font-bold text-foreground tabular-nums">{money(ar.totals.total)}</span>
                </div>
              </>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
