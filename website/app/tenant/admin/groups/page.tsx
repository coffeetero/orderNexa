import { requireArea } from '@/lib/supabase/guard';
import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { GroupsAdmin } from '@/components/features/admin/GroupsAdmin';

export const metadata = {
  title: 'Customer Groups — Admin',
};

export default async function AdminGroupsAdminPage() {
  await requireArea('admin.groups');
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No company found for this user.</div>;
  }
  return <GroupsAdmin tenantId={tenantId} />;
}
