import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { OrdersTable } from '@/components/features/tenant/OrdersTable';
import { mockOrders } from '@/lib/mock-data';
import { Plus, Download, Filter } from 'lucide-react';

export default function ManageOrdersPage() {
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
          <Button size="sm" className="gap-1.5">
            <Plus className="h-3.5 w-3.5" />
            New Order
          </Button>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        {[
          { label: 'Pending', value: 1, color: 'text-amber-600 dark:text-amber-400' },
          { label: 'In Production', value: 1, color: 'text-primary' },
          { label: 'Dispatched', value: 1, color: 'text-orange-600 dark:text-orange-400' },
          { label: 'Delivered Today', value: 1, color: 'text-emerald-600 dark:text-emerald-400' },
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
          <OrdersTable orders={mockOrders} />
        </CardContent>
      </Card>
    </div>
  );
}
