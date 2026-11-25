import { requireArea } from '@/lib/supabase/guard';
import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { ExportCustomers } from '@/components/features/customers/ExportCustomers';

export const metadata = {
  title: 'Export Customers — Customers',
};

export default async function ExportCustomersPage() {
  await requireArea('customers.exports');
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No company found for this user.</div>;
  }
  return <ExportCustomers tenantId={tenantId} />;
}
