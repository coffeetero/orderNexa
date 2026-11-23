import { requireArea } from '@/lib/supabase/guard';
import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { UsersAdmin } from '@/components/features/admin/UsersAdmin';

export const metadata = {
  title: 'Company Users — Admin',
};

export default async function AdminUsersAdminPage() {
  await requireArea('admin.users');
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No company found for this user.</div>;
  }
  return <UsersAdmin tenantId={tenantId} audience="TENANT" />;
}
