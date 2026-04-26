import Link from 'next/link';
import { ShoppingCart, FileText, CreditCard, Calendar, ArrowRight } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { CustomerMetricCard } from '@/components/features/customer/CustomerMetricCard';
import { OrderHistoryTable } from '@/components/features/customer/OrderHistoryTable';
import { mockCustomerMetrics, mockOrders, mockInvoices } from '@/lib/mock-data';

export default function CustomerDashboardPage() {
  const myOrders = mockOrders.filter((o) => o.customerId === 'c1');
  const myInvoices = mockInvoices.filter((i) => i.customerId === 'c1');

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <CustomerMetricCard
          metric={mockCustomerMetrics.totalOrders}
          icon={ShoppingCart}
          accentColor="bg-sky-500/10 text-sky-600 dark:text-sky-400"
        />
        <CustomerMetricCard
          metric={mockCustomerMetrics.openInvoices}
          icon={FileText}
          accentColor="bg-amber-500/10 text-amber-600 dark:text-amber-400"
        />
        <CustomerMetricCard
          metric={mockCustomerMetrics.lastOrderDate}
          icon={Calendar}
          accentColor="bg-primary/10 text-primary"
        />
        <CustomerMetricCard
          metric={mockCustomerMetrics.outstandingBalance}
          icon={CreditCard}
          accentColor="bg-orange-500/10 text-orange-600 dark:text-orange-400"
        />
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <Card className="border-border/60 lg:col-span-2">
          <CardHeader className="flex flex-row items-center justify-between pb-3">
            <CardTitle
              className="text-base font-semibold"
              style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
            >
              Recent Orders
            </CardTitle>
            <Button asChild variant="ghost" size="sm" className="text-xs text-primary gap-1">
              <Link href="/customer/orders">
                View all <ArrowRight className="h-3 w-3" />
              </Link>
            </Button>
          </CardHeader>
          <CardContent className="p-0 pb-1">
            <OrderHistoryTable orders={myOrders} />
          </CardContent>
        </Card>

        <div className="space-y-4">
          <Card className="border-border/60">
            <CardHeader className="pb-3">
              <CardTitle
                className="text-base font-semibold"
                style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
              >
                Open Invoices
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              {myInvoices.map((invoice) => (
                <div key={invoice.id} className="flex items-start justify-between gap-2">
                  <div className="min-w-0">
                    <p className="text-xs font-medium text-foreground truncate">
                      {invoice.invoiceNumber}
                    </p>
                    <p className="text-[10px] text-muted-foreground">
                      Due: {new Date(invoice.dueAt).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })}
                    </p>
                  </div>
                  <div className="text-right shrink-0">
                    <p className="text-xs font-semibold text-foreground tabular-nums">
                      ${invoice.balance.toFixed(2)}
                    </p>
                    <Badge
                      variant="outline"
                      className={
                        invoice.status === 'overdue'
                          ? 'text-[10px] bg-red-500/10 text-red-700 dark:text-red-400 border-red-500/25 mt-0.5'
                          : 'text-[10px] bg-amber-500/10 text-amber-700 dark:text-amber-400 border-amber-500/25 mt-0.5'
                      }
                    >
                      {invoice.status === 'overdue' ? 'Overdue' : 'Open'}
                    </Badge>
                  </div>
                </div>
              ))}
              <Button asChild variant="outline" size="sm" className="w-full text-xs mt-2">
                <Link href="/customer/invoicing">View Statements</Link>
              </Button>
            </CardContent>
          </Card>

          <Card className="border-border/60 bg-primary/5 border-primary/20">
            <CardContent className="p-5">
              <h3
                className="text-sm font-semibold text-foreground mb-2"
                style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
              >
                Next Delivery
              </h3>
              <div className="flex items-center gap-2 mb-3">
                <Calendar className="h-4 w-4 text-primary" />
                <span className="text-sm font-medium text-foreground">Tuesday, 17 Dec 2024</span>
              </div>
              <div className="space-y-1">
                <div className="flex justify-between text-xs">
                  <span className="text-muted-foreground">Pane di Altamura 1kg</span>
                  <span className="font-medium text-foreground">6x</span>
                </div>
              </div>
              <Button asChild size="sm" className="w-full mt-4 text-xs">
                <Link href="/customer/orders">Manage Order</Link>
              </Button>
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}
