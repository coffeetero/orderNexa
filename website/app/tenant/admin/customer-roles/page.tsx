import { requireArea } from '@/lib/supabase/guard';
import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { RolesAdmin } from '@/components/features/admin/RolesAdmin';

export const metadata = {
  title: 'Customer Roles — Admin',
};

export default async function AdminCustomerRolesPage() {
  await requireArea('admin.customer-roles');
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No company found for this user.</div>;
  }
  return <RolesAdmin tenantId={tenantId} audience="CUSTOMER" />;
}
