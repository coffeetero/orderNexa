import { requireArea } from '@/lib/supabase/guard';
import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { PricingBooksAdmin } from '@/components/features/inventory/PricingBooksAdmin';

export const metadata = {
  title: 'Pricing Books — Inventory',
};

export default async function PricingBooksPage() {
  await requireArea('inventory.pricing');
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No company found for this user.</div>;
  }
  return <PricingBooksAdmin tenantId={tenantId} />;
}
