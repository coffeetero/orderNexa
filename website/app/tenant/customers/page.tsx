import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { CustomersTable } from '@/components/features/tenant/CustomersTable';
import { mockCustomers } from '@/lib/mock-data';
import { Plus, Download, Search } from 'lucide-react';
import { Input } from '@/components/ui/input';

export default function ManageCustomersPage() {
  const activeCount = mockCustomers.filter((c) => c.status === 'active').length;
  const totalBalance = mockCustomers.reduce((acc, c) => acc + c.balance, 0);

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h2
            className="text-2xl font-bold text-foreground"
            style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
          >
            Customer Profiles
          </h2>
          <p className="text-sm text-muted-foreground mt-0.5">
            {activeCount} active of {mockCustomers.length} customers
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Button variant="outline" size="sm" className="gap-1.5">
            <Download className="h-3.5 w-3.5" />
            Export
          </Button>
          <Button size="sm" className="gap-1.5">
            <Plus className="h-3.5 w-3.5" />
            New Customer
          </Button>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
        <Card className="border-border/60">
          <CardContent className="p-4">
            <div
              className="text-2xl font-bold text-foreground mb-0.5"
              style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
            >
              {activeCount}
            </div>
            <div className="text-xs text-muted-foreground font-medium">Active Customers</div>
          </CardContent>
        </Card>
        <Card className="border-border/60">
          <CardContent className="p-4">
            <div
              className="text-2xl font-bold text-foreground mb-0.5"
              style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
            >
              ${totalBalance.toLocaleString('en-US', { minimumFractionDigits: 0 })}
            </div>
            <div className="text-xs text-muted-foreground font-medium">Total AR Balance</div>
          </CardContent>
        </Card>
        <Card className="border-border/60">
          <CardContent className="p-4">
            <div
              className="text-2xl font-bold text-foreground mb-0.5"
              style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
            >
              4
            </div>
            <div className="text-xs text-muted-foreground font-medium">Delivery Routes</div>
          </CardContent>
        </Card>
      </div>

      <Card className="border-border/60">
        <CardHeader className="pb-3 flex flex-row items-center justify-between">
          <CardTitle
            className="text-base font-semibold"
            style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
          >
            All Customers
          </CardTitle>
          <div className="relative w-48">
            <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-muted-foreground" />
            <Input placeholder="Search..." className="pl-8 h-8 text-xs" />
          </div>
        </CardHeader>
        <CardContent className="p-0 pb-1">
          <CustomersTable customers={mockCustomers} />
        </CardContent>
      </Card>
    </div>
  );
}
