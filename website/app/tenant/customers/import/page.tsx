import { requireArea } from '@/lib/supabase/guard';
import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { ImportCustomers } from '@/components/features/customers/ImportCustomers';

export const metadata = {
  title: 'Import Customers — Customers',
};

export default async function ImportCustomersPage() {
  await requireArea('customers.import');
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No company found for this user.</div>;
  }
  return <ImportCustomers tenantId={tenantId} />;
}
