import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { UsersAdmin } from '@/components/features/admin/UsersAdmin';

export const metadata = {
  title: 'Users — Admin',
};

export default async function AdminUsersAdminPage() {
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No tenant found for this user.</div>;
  }
  return <UsersAdmin tenantId={tenantId} />;
}
