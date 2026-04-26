import { Badge } from '@/components/ui/badge';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import type { Customer } from '@/lib/types';
import { cn } from '@/lib/utils';

const statusConfig = {
  active: { label: 'Active', className: 'bg-emerald-500/12 text-emerald-700 dark:text-emerald-400 border-emerald-500/25' },
  inactive: { label: 'Inactive', className: 'bg-muted text-muted-foreground border-border' },
  suspended: { label: 'Suspended', className: 'bg-red-500/12 text-red-700 dark:text-red-400 border-red-500/25' },
};

interface CustomersTableProps {
  customers: Customer[];
}

export function CustomersTable({ customers }: CustomersTableProps) {
  return (
    <div className="rounded-xl border border-border/60 overflow-hidden">
      <Table>
        <TableHeader>
          <TableRow className="bg-muted/40 hover:bg-muted/40 border-b border-border/60">
            <TableHead className="text-xs font-semibold text-muted-foreground">Account</TableHead>
            <TableHead className="text-xs font-semibold text-muted-foreground">Customer</TableHead>
            <TableHead className="text-xs font-semibold text-muted-foreground">City</TableHead>
            <TableHead className="text-xs font-semibold text-muted-foreground">Route</TableHead>
            <TableHead className="text-xs font-semibold text-muted-foreground">Status</TableHead>
            <TableHead className="text-right text-xs font-semibold text-muted-foreground">Balance</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {customers.map((customer) => {
            const status = statusConfig[customer.status];
            return (
              <TableRow
                key={customer.id}
                className="border-b border-border/40 hover:bg-muted/20 transition-colors cursor-pointer"
              >
                <TableCell>
                  <span className="font-mono text-xs text-muted-foreground">{customer.accountNumber}</span>
                </TableCell>
                <TableCell>
                  <div>
                    <p className="text-sm font-medium text-foreground">{customer.name}</p>
                    <p className="text-xs text-muted-foreground">{customer.email}</p>
                  </div>
                </TableCell>
                <TableCell>
                  <span className="text-xs text-muted-foreground">{customer.city}</span>
                </TableCell>
                <TableCell>
                  <span className="text-xs text-muted-foreground">{customer.deliveryRoute ?? '—'}</span>
                </TableCell>
                <TableCell>
                  <Badge
                    variant="outline"
                    className={cn('text-xs font-medium border', status.className)}
                  >
                    {status.label}
                  </Badge>
                </TableCell>
                <TableCell className="text-right">
                  <span
                    className={cn(
                      'text-sm font-semibold tabular-nums',
                      customer.balance > 0 ? 'text-foreground' : 'text-muted-foreground'
                    )}
                  >
                    ${customer.balance.toLocaleString('en-US', { minimumFractionDigits: 2 })}
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
