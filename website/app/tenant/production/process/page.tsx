import { createClient } from '@/lib/supabase/server';
import { ProcessRun } from '@/components/features/production/ProcessRun';

export const metadata = {
  title: 'Post Orders to Production — Production',
};

export default async function ProcessRunPage() {
  const { data } = await createClient().rpc('fnd_tenants_get');
  const tenants = Array.isArray(data) ? data : [];
  const tenantId: number | null = tenants.length > 0 ? tenants[0].tenant_id : null;
  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No company found for this user.</div>;
  }
  return <ProcessRun tenantId={tenantId} />;
}
