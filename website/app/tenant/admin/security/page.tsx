import { requireArea } from '@/lib/supabase/guard';
import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { SecurityAdmin } from '@/components/features/admin/SecurityAdmin';

export const metadata = {
  title: 'Security — Admin',
};

export default async function AdminSecurityPage() {
  await requireArea('admin.security');
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No company found for this user.</div>;
  }
  return <SecurityAdmin tenantId={tenantId} />;
}
