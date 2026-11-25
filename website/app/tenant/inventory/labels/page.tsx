import { requireArea } from '@/lib/supabase/guard';
import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { NutritionLabelsAdmin } from '@/components/features/inventory/NutritionLabelsAdmin';

export const metadata = {
  title: 'Nutrition Labels — Inventory',
};

export default async function NutritionLabelsPage() {
  await requireArea('inventory.labels');
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No company found for this user.</div>;
  }
  return <NutritionLabelsAdmin tenantId={tenantId} />;
}
