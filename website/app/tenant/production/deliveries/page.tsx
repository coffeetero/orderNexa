import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { ConfirmDeliveries } from '@/components/features/production/ConfirmDeliveries';

export const metadata = {
  title: 'Confirm Deliveries — Production',
};

export default async function ConfirmDeliveriesPage() {
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No company found for this user.</div>;
  }
  return <ConfirmDeliveries tenantId={tenantId} />;
}
