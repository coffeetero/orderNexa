import { createClient } from '@/lib/supabase/server';
import { ImportOrders } from '@/components/features/orders/ImportOrders';

export const metadata = {
  title: 'Import Orders — Orders',
};

export default async function ImportOrdersPage() {
  const { data } = await createClient().rpc('fnd_tenants_get');
  const tenants = Array.isArray(data) ? data : [];
  const tenantId: number | null = tenants.length > 0 ? tenants[0].tenant_id : null;
  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No company found for this user.</div>;
  }
  return <ImportOrders tenantId={tenantId} />;
}
