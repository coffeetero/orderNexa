import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import { mockInvoices } from '@/lib/mock-data';
import { Download } from 'lucide-react';
import { cn } from '@/lib/utils';

const statusConfig = {
  open: { label: 'Open', className: 'bg-sky-500/12 text-sky-700 dark:text-sky-400 border-sky-500/25' },
  partial: { label: 'Partial', className: 'bg-amber-500/12 text-amber-700 dark:text-amber-400 border-amber-500/25' },
  paid: { label: 'Paid', className: 'bg-emerald-500/12 text-emerald-700 dark:text-emerald-400 border-emerald-500/25' },
  overdue: { label: 'Overdue', className: 'bg-red-500/12 text-red-700 dark:text-red-400 border-red-500/25' },
};

export default function CustomerInvoicingPage() {
  const myInvoices = mockInvoices.filter((i) => i.customerId === 'c1');
  const totalBalance = myInvoices.reduce((acc, i) => acc + i.balance, 0);

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h2
            className="text-2xl font-bold text-foreground"
            style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
          >
            Statements & Invoices
          </h2>
          <p className="text-sm text-muted-foreground mt-0.5">Le Jardin Restaurant — ACC-0042</p>
        </div>
        <Button variant="outline" size="sm" className="gap-1.5">
          <Download className="h-3.5 w-3.5" />
          Download Statement
        </Button>
      </div>

      <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
        <Card className="border-border/60">
          <CardContent className="p-4">
            <div
              className="text-2xl font-bold text-foreground mb-0.5 tabular-nums"
              style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
            >
              ${totalBalance.toFixed(2)}
            </div>
            <div className="text-xs text-muted-foreground font-medium">Total Outstanding</div>
          </CardContent>
        </Card>
        <Card className="border-border/60">
          <CardContent className="p-4">
            <div
              className="text-2xl font-bold text-foreground mb-0.5"
              style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
            >
              {myInvoices.length}
            </div>
            <div className="text-xs text-muted-foreground font-medium">Open Invoices</div>
          </CardContent>
        </Card>
        <Card className="border-border/60">
          <CardContent className="p-4">
            <div
              className="text-2xl font-bold text-foreground mb-0.5"
              style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
            >
              30 days
            </div>
            <div className="text-xs text-muted-foreground font-medium">Payment Terms</div>
          </CardContent>
        </Card>
      </div>

      <Card className="border-border/60">
        <CardHeader className="pb-3">
          <CardTitle
            className="text-base font-semibold"
            style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
          >
            Invoice History
          </CardTitle>
        </CardHeader>
        <CardContent className="p-0 pb-1">
          <div className="rounded-xl overflow-hidden">
            <Table>
              <TableHeader>
                <TableRow className="bg-muted/40 hover:bg-muted/40 border-b border-border/60">
                  <TableHead className="text-xs font-semibold text-muted-foreground">Invoice #</TableHead>
                  <TableHead className="text-xs font-semibold text-muted-foreground">Order</TableHead>
                  <TableHead className="text-xs font-semibold text-muted-foreground">Issued</TableHead>
                  <TableHead className="text-xs font-semibold text-muted-foreground">Due</TableHead>
                  <TableHead className="text-xs font-semibold text-muted-foreground">Status</TableHead>
                  <TableHead className="text-right text-xs font-semibold text-muted-foreground">Balance</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {myInvoices.map((invoice) => {
                  const status = statusConfig[invoice.status];
                  return (
                    <TableRow
                      key={invoice.id}
                      className="border-b border-border/40 hover:bg-muted/20 transition-colors cursor-pointer"
                    >
                      <TableCell className="font-mono text-xs text-muted-foreground">
                        {invoice.invoiceNumber}
                      </TableCell>
                      <TableCell>
                        <span className="text-xs text-foreground">{invoice.orderNumber}</span>
                      </TableCell>
                      <TableCell>
                        <span className="text-xs text-muted-foreground">
                          {new Date(invoice.issuedAt).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })}
                        </span>
                      </TableCell>
                      <TableCell>
                        <span className="text-xs text-muted-foreground">
                          {new Date(invoice.dueAt).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })}
                        </span>
                      </TableCell>
                      <TableCell>
                        <Badge variant="outline" className={cn('text-xs font-medium border', status.className)}>
                          {status.label}
                        </Badge>
                      </TableCell>
                      <TableCell className="text-right">
                        <span className="text-sm font-semibold text-foreground tabular-nums">
                          ${invoice.balance.toFixed(2)}
                        </span>
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
