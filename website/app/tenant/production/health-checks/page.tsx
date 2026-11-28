import { requireArea } from '@/lib/supabase/guard';
import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { createClient } from '@/lib/supabase/server';
import { HealthFindings } from '@/components/features/health/HealthFindings';

export const metadata = {
  title: 'Health Checks — Operations',
};

export default async function HealthChecksPage({ searchParams }: { searchParams: Promise<{ check?: string | string[] }> }) {
  await requireArea('admin.health');
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No company found for this user.</div>;
  }
  const check = (await searchParams).check;
  const w = await (await createClient()).rpc('fnd_has_access', { p_area: 'admin.health', p_action: 'W' });
  return <HealthFindings tenantId={tenantId} initialCheck={typeof check === 'string' && check ? check : null} canRun={w.data === true} />;
}
