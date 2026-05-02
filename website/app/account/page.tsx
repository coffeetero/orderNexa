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
import { MetricCard } from '@/components/features/tenant/MetricCard';
import { OrdersTable } from '@/components/features/tenant/OrdersTable';
import { CustomersTable } from '@/components/features/tenant/CustomersTable';
import {
  mockTenantMetrics,
  mockOrders,
  mockCustomers,
} from '@/lib/mock-data';

export default function TenantDashboardPage() {
  const recentOrders = mockOrders.slice(0, 5);
  const topCustomers = mockCustomers.slice(0, 4);

  return (
    <div className="space-y-6">
      <div>
        <p className="text-sm text-muted-foreground">
          Monday, 16 December 2024 — Production day 351
        </p>
      </div>

      <div className="grid grid-cols-2 gap-4 lg:grid-cols-3 xl:grid-cols-6">
        <MetricCard
          metric={mockTenantMetrics.totalRevenue}
          icon={DollarSign}
          accentColor="bg-emerald-500/10 text-emerald-600 dark:text-emerald-400"
        />
        <MetricCard
          metric={mockTenantMetrics.totalOrders}
          icon={ShoppingCart}
          accentColor="bg-sky-500/10 text-sky-600 dark:text-sky-400"
        />
        <MetricCard
          metric={mockTenantMetrics.activeCustomers}
          icon={Users}
          accentColor="bg-primary/10 text-primary"
        />
        <MetricCard
          metric={mockTenantMetrics.productionToday}
          icon={ChefHat}
          accentColor="bg-amber-500/10 text-amber-600 dark:text-amber-400"
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

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <Card className="border-border/60 col-span-1 lg:col-span-2">
          <CardHeader className="flex flex-row items-center justify-between pb-3">
            <CardTitle
              className="text-base font-semibold"
              style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
            >
              Recent Orders
            </CardTitle>
            <Button asChild variant="ghost" size="sm" className="text-xs text-primary gap-1">
              <Link href="/account/orders">
                View all <ArrowRight className="h-3 w-3" />
              </Link>
            </Button>
          </CardHeader>
          <CardContent className="p-0 pb-1">
            <OrdersTable orders={recentOrders} compact />
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
              <Link href="/account/customers">
                View all <ArrowRight className="h-3 w-3" />
              </Link>
            </Button>
          </CardHeader>
          <CardContent className="p-0 pb-1">
            <CustomersTable customers={topCustomers} />
          </CardContent>
        </Card>

        <Card className="border-border/60">
          <CardHeader className="pb-3">
            <CardTitle
              className="text-base font-semibold"
              style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
            >
              AR Summary
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            {[
              { label: 'Current (0–30 days)', amount: 8940, color: 'bg-emerald-500' },
              { label: '31–60 days', amount: 5460, color: 'bg-amber-500' },
              { label: '61–90 days', amount: 3800, color: 'bg-orange-500' },
              { label: 'Over 90 days', amount: 3140, color: 'bg-red-500' },
            ].map((bucket) => (
              <div key={bucket.label} className="flex items-center justify-between">
                <div className="flex items-center gap-2.5">
                  <div className={`h-2.5 w-2.5 rounded-full ${bucket.color}`} />
                  <span className="text-sm text-foreground">{bucket.label}</span>
                </div>
                <span className="text-sm font-semibold tabular-nums text-foreground">
                  ${bucket.amount.toLocaleString()}
                </span>
              </div>
            ))}
            <div className="pt-3 border-t border-border flex items-center justify-between">
              <span className="text-sm font-semibold text-foreground">Total AR</span>
              <span className="text-sm font-bold text-foreground tabular-nums">$21,340</span>
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
