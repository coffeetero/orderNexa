import { requireArea } from '@/lib/supabase/guard';
import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { NutritionLabelsPrint } from '@/components/features/inventory/NutritionLabelsPrint';

export const metadata = {
  title: 'Print Nutrition Labels — Inventory',
};

export default async function NutritionLabelsPrintPage(props: { searchParams: Promise<{ ids?: string }> }) {
  const searchParams = await props.searchParams;
  await requireArea('inventory.labels');
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No company found for this user.</div>;
  }
  const ids = (searchParams.ids ?? '').split(',').filter((v) => /^\d{1,18}$/.test(v));
  return <NutritionLabelsPrint tenantId={tenantId} itemIds={ids} />;
}
