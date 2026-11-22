import { createClient } from '@/lib/supabase/server';
import { ProductionSettings } from '@/components/features/admin/ProductionSettings';

export const metadata = {
  title: 'Production Settings — Admin',
};

export default async function AdminProductionPage() {
  // Resolve the tenant on the server (same pattern as Enter Orders); the browser session has no tenant_id claim.
  const { data } = await createClient().rpc('fnd_tenants_get');
  const tenants = Array.isArray(data) ? data : [];
  const tenantId: number | null = tenants.length > 0 ? tenants[0].tenant_id : null;

  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No tenant found for this user.</div>;
  }
  return <ProductionSettings tenantId={tenantId} />;
}
