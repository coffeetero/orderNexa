import { requireArea } from '@/lib/supabase/guard';
import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { RecipeBatchSheet } from '@/components/features/inventory/recipes/RecipeBatchSheet';

export const metadata = {
  title: 'Batch Sheet — Recipes',
};

type Params = { id?: string; mode?: string; value?: string; unit?: string; out?: string; room?: string; flour?: string; pf?: string };

export default async function RecipeBatchSheetPage({ searchParams }: { searchParams: Params }) {
  await requireArea('inventory.recipes');
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No company found for this user.</div>;
  }
  const id = /^\d{1,18}$/.test(searchParams.id ?? '') ? Number(searchParams.id) : null;
  const n = (v?: string) => (v && /^-?\d+(\.\d+)?$/.test(v) ? Number(v) : null);
  const scale = {
    mode: searchParams.mode ?? 'BATCHES', value: n(searchParams.value) ?? 1, unit: searchParams.unit ?? 'g',
    out_unit: searchParams.out ?? null, room_f: n(searchParams.room), flour_f: n(searchParams.flour), preferment_f: n(searchParams.pf),
  };
  return <RecipeBatchSheet tenantId={tenantId} recipeId={id} scale={scale} />;
}
