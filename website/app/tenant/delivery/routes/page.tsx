import { requireArea } from '@/lib/supabase/guard';
import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { createClient } from '@/lib/supabase/server';
import { RoutesMaintenance } from '@/components/features/delivery/RoutesMaintenance';

export const metadata = {
  title: 'Routes Maintenance — Delivery',
};

export default async function RoutesMaintenancePage() {
  await requireArea('delivery.routes');
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No company found for this user.</div>;
  }
  const supabase = createClient();
  const [w, d] = await Promise.all([
    supabase.rpc('fnd_has_access', { p_area: 'delivery.routes', p_action: 'W' }),
    supabase.rpc('fnd_has_access', { p_area: 'delivery.routes', p_action: 'D' }),
  ]);
  return <RoutesMaintenance tenantId={tenantId} canEdit={w.data === true} canDelete={d.data === true} />;
}
