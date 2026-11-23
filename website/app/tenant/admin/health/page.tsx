import { requireArea } from '@/lib/supabase/guard';
import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { HealthChecksAdmin } from '@/components/features/admin/HealthChecksAdmin';

export const metadata = {
  title: 'Health Checks — Admin',
};

export default async function AdminHealthPage() {
  await requireArea('admin.health');
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No company found for this user.</div>;
  }
  return <HealthChecksAdmin tenantId={tenantId} />;
}
