import { requireArea } from '@/lib/supabase/guard';
import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { RouteSheet } from '@/components/features/delivery/RouteSheet';

export const metadata = {
  title: 'Route Sheet — Delivery',
};

type Params = { route_id?: string; dow?: string; code?: string; date?: string };

export default async function RouteSheetPage({ searchParams }: { searchParams: Params }) {
  await requireArea('delivery.routes');
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No company found for this user.</div>;
  }
  const routeId = /^\d{1,18}$/.test(searchParams.route_id ?? '') ? Number(searchParams.route_id) : null;
  const date = /^\d{4}-\d{2}-\d{2}$/.test(searchParams.date ?? '') ? searchParams.date! : '';
  return <RouteSheet tenantId={tenantId} routeId={routeId} dow={(searchParams.dow ?? 'MON').toUpperCase()} code={searchParams.code ?? ''} initialDate={date} />;
}
