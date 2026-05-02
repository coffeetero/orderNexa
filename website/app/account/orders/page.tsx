'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Plus, Download, Filter } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { cn } from '@/lib/utils';
import type { Order, OrderStatus } from '@/lib/types';
import { mockOrders } from '@/lib/mock-data';

const statusConfig: Record<OrderStatus, { label: string; className: string }> = {
  pending:       { label: 'Pending',       className: 'bg-amber-500/12 text-amber-700 dark:text-amber-400 border-amber-500/25' },
  confirmed:     { label: 'Confirmed',     className: 'bg-sky-500/12 text-sky-700 dark:text-sky-400 border-sky-500/25' },
  in_production: { label: 'In Production', className: 'bg-primary/12 text-primary border-primary/25' },
  packed:        { label: 'Packed',        className: 'bg-violet-500/12 text-violet-700 dark:text-violet-400 border-violet-500/25' },
  dispatched:    { label: 'Dispatched',    className: 'bg-orange-500/12 text-orange-700 dark:text-orange-400 border-orange-500/25' },
  delivered:     { label: 'Delivered',     className: 'bg-emerald-500/12 text-emerald-700 dark:text-emerald-400 border-emerald-500/25' },
  cancelled:     { label: 'Cancelled',     className: 'bg-red-500/12 text-red-700 dark:text-red-400 border-red-500/25' },
};

export default function ManageOrdersPage() {
  const router = useRouter();

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h2
            className="text-2xl font-bold text-foreground"
            style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
          >
            Manage Orders
          </h2>
          <p className="text-sm text-muted-foreground mt-0.5">{mockOrders.length} orders found</p>
        </div>
        <div className="flex items-center gap-2">
          <Button variant="outline" size="sm" className="gap-1.5">
            <Filter className="h-3.5 w-3.5" />
            Filter
          </Button>
          <Button variant="outline" size="sm" className="gap-1.5">
            <Download className="h-3.5 w-3.5" />
            Export
          </Button>
          <Button size="sm" className="gap-1.5" asChild>
            <Link href="/account/orders/new">
              <Plus className="h-3.5 w-3.5" />
              New Order
            </Link>
          </Button>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        {[
          { label: 'Pending',        value: 1, color: 'text-amber-600 dark:text-amber-400' },
          { label: 'In Production',  value: 1, color: 'text-primary' },
          { label: 'Dispatched',     value: 1, color: 'text-orange-600 dark:text-orange-400' },
          { label: 'Delivered Today',value: 1, color: 'text-emerald-600 dark:text-emerald-400' },
        ].map((stat) => (
          <Card key={stat.label} className="border-border/60">
            <CardContent className="p-4 text-center">
              <div
                className={`text-2xl font-bold mb-0.5 ${stat.color}`}
                style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
              >
                {stat.value}
              </div>
              <div className="text-xs text-muted-foreground font-medium">{stat.label}</div>
            </CardContent>
          </Card>
        ))}
      </div>

      <Card className="border-border/60">
        <CardHeader className="pb-3">
          <CardTitle
            className="text-base font-semibold"
            style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
          >
            All Orders
          </CardTitle>
        </CardHeader>
        <CardContent className="p-0 pb-1">
          <div className="rounded-xl border border-border/60 overflow-hidden">
            <table className="w-full">
              <thead>
                <tr className="bg-muted/40 hover:bg-muted/40 border-b border-border/60">
                  <th className="px-3 py-2 text-left text-xs font-semibold text-muted-foreground">Order #</th>
                  <th className="px-3 py-2 text-left text-xs font-semibold text-muted-foreground">Customer</th>
                  <th className="px-3 py-2 text-left text-xs font-semibold text-muted-foreground">Status</th>
                  <th className="px-3 py-2 text-left text-xs font-semibold text-muted-foreground">Route</th>
                  <th className="px-3 py-2 text-left text-xs font-semibold text-muted-foreground">Delivery</th>
                  <th className="px-3 py-2 text-right text-xs font-semibold text-muted-foreground">Total</th>
                </tr>
              </thead>
              <tbody>
                {mockOrders.map((order: Order) => {
                  const status = statusConfig[order.status];
                  return (
                    <tr
                      key={order.id}
                      className="border-b border-border/40 hover:bg-muted/20 transition-colors cursor-pointer"
                      onClick={() => router.push(`/account/orders/${order.id}/edit`)}
                      title={`Edit order ${order.orderNumber}`}
                    >
                      <td className="px-3 py-2 font-mono text-xs text-muted-foreground">
                        {order.orderNumber}
                      </td>
                      <td className="px-3 py-2">
                        <span className="text-sm font-medium text-foreground">{order.customerName}</span>
                      </td>
                      <td className="px-3 py-2">
                        <Badge
                          variant="outline"
                          className={cn('text-xs font-medium border', status.className)}
                        >
                          {status.label}
                        </Badge>
                      </td>
                      <td className="px-3 py-2">
                        <span className="text-xs text-muted-foreground">{order.route ?? '—'}</span>
                      </td>
                      <td className="px-3 py-2">
                        <span className="text-xs text-muted-foreground">
                          {new Date(order.deliveryDate).toLocaleDateString('en-GB', {
                            day: 'numeric',
                            month: 'short',
                          })}
                        </span>
                      </td>
                      <td className="px-3 py-2 text-right">
                        <span className="text-sm font-semibold text-foreground tabular-nums">
                          ${order.total.toFixed(2)}
                        </span>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
