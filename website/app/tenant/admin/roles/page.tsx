import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { RolesAdmin } from '@/components/features/admin/RolesAdmin';

export const metadata = {
  title: 'Roles & Access — Admin',
};

export default async function AdminRolesAdminPage() {
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No tenant found for this user.</div>;
  }
  return <RolesAdmin tenantId={tenantId} />;
}
