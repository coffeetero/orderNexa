import { supabase } from '@/lib/supabase';
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
import { mockPayments } from '@/lib/mock-data';
import { Plus } from 'lucide-react';

const methodLabels: Record<string, string> = {
  bank_transfer: 'Bank Transfer',
  credit_card: 'Credit Card',
  cash: 'Cash',
  cheque: 'Cheque',
};

export default async function CustomerPaymentsPage() {
  // const myPayments = mockPayments.filter((p) => p.customerId === 'c2' || p.customerId === 'c3');

  // const supabase = createSupabaseClient();

  const { data: myPayments, error } = await supabase
    .from('ar_payments')
    .select('*')
    .eq('customer_id', 200000000103) // temporary
    .order('payment_date', { ascending: false });

  const { data: sessionData } = await supabase.auth.getSession();
  console.log('SESSION:', sessionData.session);

  
  if (error) {
    console.error(error); 
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h2
            className="text-2xl font-bold text-foreground"
            style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
          >
            Payment Management
          </h2>
          <p className="text-sm text-muted-foreground mt-0.5">Manage and track your payments</p>
        </div>
        <Button size="sm" className="gap-1.5">
          <Plus className="h-3.5 w-3.5" />
          Make a Payment
        </Button>
      </div>

      <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
        <Card className="border-border/60">
          <CardContent className="p-4">
            <div
              className="text-2xl font-bold text-foreground mb-0.5 tabular-nums"
              style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
            >
              $186.00
            </div>
            <div className="text-xs text-muted-foreground font-medium">Amount Due Now</div>
          </CardContent>
        </Card>
        <Card className="border-border/60">
          <CardContent className="p-4">
            <div
              className="text-2xl font-bold text-emerald-600 dark:text-emerald-400 mb-0.5 tabular-nums"
              style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
            >
              $0.00
            </div>
            <div className="text-xs text-muted-foreground font-medium">Credits Available</div>
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
            <div className="text-xs text-muted-foreground font-medium">Standard Payment Terms</div>
          </CardContent>
        </Card>
      </div>

      <Card className="border-border/60">
        <CardHeader className="pb-3">
          <CardTitle
            className="text-base font-semibold"
            style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
          >
            Payment History
          </CardTitle>
        </CardHeader>
        <CardContent className="p-0 pb-1">
          <div className="rounded-xl overflow-hidden">
            <Table>
              <TableHeader>
                <TableRow className="bg-muted/40 hover:bg-muted/40 border-b border-border/60">
                  <TableHead className="text-xs font-semibold text-muted-foreground">Payment #</TableHead>
                  <TableHead className="text-xs font-semibold text-muted-foreground">Method</TableHead>
                  <TableHead className="text-xs font-semibold text-muted-foreground">Reference</TableHead>
                  <TableHead className="text-xs font-semibold text-muted-foreground">Date</TableHead>
                  <TableHead className="text-right text-xs font-semibold text-muted-foreground">Amount</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {myPayments?.map((payment) => (
                  <TableRow
                    key={payment.ar_paymentid}
                    className="border-b border-border/40 hover:bg-muted/20 transition-colors"
                  >
                    <TableCell className="font-mono text-xs text-muted-foreground">
                      {payment.payment_number}
                    </TableCell>
                    <TableCell>
                      <Badge variant="secondary" className="text-xs">
                        {methodLabels[payment.payment_method]}
                      </Badge>
                    </TableCell>
                    <TableCell>
                      <span className="font-mono text-xs text-muted-foreground">{payment.reference}</span>
                    </TableCell>
                    <TableCell>
                      <span className="text-xs text-muted-foreground">
                        {new Date(payment.payment_date).toLocaleDateString('en-GB', {
                          day: 'numeric',
                          month: 'short',
                          year: 'numeric',
                        })}
                      </span>
                    </TableCell>
                    <TableCell className="text-right">
                      <span className="text-sm font-semibold text-emerald-600 dark:text-emerald-400 tabular-nums">
                        ${payment.amount.toFixed(2)}
                      </span>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
