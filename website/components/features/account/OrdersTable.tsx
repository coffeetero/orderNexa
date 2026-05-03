import { Badge } from '@/components/ui/badge';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import type { Order, OrderStatus } from '@/lib/types';
import { cn } from '@/lib/utils';

const statusConfig: Record<OrderStatus, { label: string; className: string }> = {
  pending: { label: 'Pending', className: 'bg-amber-500/12 text-amber-700 dark:text-amber-400 border-amber-500/25' },
  confirmed: { label: 'Confirmed', className: 'bg-sky-500/12 text-sky-700 dark:text-sky-400 border-sky-500/25' },
  in_production: { label: 'In Production', className: 'bg-primary/12 text-primary border-primary/25' },
  packed: { label: 'Packed', className: 'bg-violet-500/12 text-violet-700 dark:text-violet-400 border-violet-500/25' },
  dispatched: { label: 'Dispatched', className: 'bg-orange-500/12 text-orange-700 dark:text-orange-400 border-orange-500/25' },
  delivered: { label: 'Delivered', className: 'bg-emerald-500/12 text-emerald-700 dark:text-emerald-400 border-emerald-500/25' },
  cancelled: { label: 'Cancelled', className: 'bg-red-500/12 text-red-700 dark:text-red-400 border-red-500/25' },
};

interface OrdersTableProps {
  orders: Order[];
  compact?: boolean;
}

export function OrdersTable({ orders, compact = false }: OrdersTableProps) {
  return (
    <div className="rounded-xl border border-border/60 overflow-hidden">
      <Table>
        <TableHeader>
          <TableRow className="bg-muted/40 hover:bg-muted/40 border-b border-border/60">
            <TableHead className="text-xs font-semibold text-muted-foreground">Order #</TableHead>
            <TableHead className="text-xs font-semibold text-muted-foreground">Customer</TableHead>
            <TableHead className="text-xs font-semibold text-muted-foreground">Status</TableHead>
            {!compact && (
              <TableHead className="text-xs font-semibold text-muted-foreground">Route</TableHead>
            )}
            <TableHead className="text-xs font-semibold text-muted-foreground">Delivery</TableHead>
            <TableHead className="text-right text-xs font-semibold text-muted-foreground">Total</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {orders.map((order) => {
            const status = statusConfig[order.status];
            return (
              <TableRow
                key={order.id}
                className="border-b border-border/40 hover:bg-muted/20 transition-colors cursor-pointer"
              >
                <TableCell className="font-mono text-xs text-muted-foreground">
                  {order.orderNumber}
                </TableCell>
                <TableCell>
                  <span className="text-sm font-medium text-foreground">{order.customerName}</span>
                </TableCell>
                <TableCell>
                  <Badge
                    variant="outline"
                    className={cn('text-xs font-medium border', status.className)}
                  >
                    {status.label}
                  </Badge>
                </TableCell>
                {!compact && (
                  <TableCell>
                    <span className="text-xs text-muted-foreground">{order.route ?? '—'}</span>
                  </TableCell>
                )}
                <TableCell>
                  <span className="text-xs text-muted-foreground">
                    {new Date(order.deliveryDate).toLocaleDateString('en-GB', {
                      day: 'numeric',
                      month: 'short',
                    })}
                  </span>
                </TableCell>
                <TableCell className="text-right">
                  <span className="text-sm font-semibold text-foreground tabular-nums">
                    ${order.total.toFixed(2)}
                  </span>
                </TableCell>
              </TableRow>
            );
          })}
        </TableBody>
      </Table>
    </div>
  );
}
