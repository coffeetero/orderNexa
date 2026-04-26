import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { OrderHistoryTable } from '@/components/features/customer/OrderHistoryTable';
import { mockOrders } from '@/lib/mock-data';
import { Plus } from 'lucide-react';

export default function CustomerOrdersPage() {
  const myOrders = mockOrders.filter((o) => o.customerId === 'c1');

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h2
            className="text-2xl font-bold text-foreground"
            style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
          >
            My Orders
          </h2>
          <p className="text-sm text-muted-foreground mt-0.5">{myOrders.length} orders on your account</p>
        </div>
        <Button size="sm" className="gap-1.5">
          <Plus className="h-3.5 w-3.5" />
          Place New Order
        </Button>
      </div>

      <Card className="border-border/60">
        <CardHeader className="pb-3">
          <CardTitle
            className="text-base font-semibold"
            style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
          >
            Order History
          </CardTitle>
        </CardHeader>
        <CardContent className="p-0 pb-1">
          <OrderHistoryTable orders={myOrders} />
        </CardContent>
      </Card>
    </div>
  );
}
