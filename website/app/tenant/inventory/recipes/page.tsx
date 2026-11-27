import { requireArea } from '@/lib/supabase/guard';
import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { createClient } from '@/lib/supabase/server';
import { RecipesBook } from '@/components/features/inventory/recipes/RecipesBook';

export const metadata = {
  title: 'Recipes — Inventory',
};

export default async function RecipesPage() {
  await requireArea('inventory.recipes');
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No company found for this user.</div>;
  }
  const supabase = await createClient();
  const [w, d] = await Promise.all([
    supabase.rpc('fnd_has_access', { p_area: 'inventory.recipes', p_action: 'W' }),
    supabase.rpc('fnd_has_access', { p_area: 'inventory.recipes', p_action: 'D' }),
  ]);
  return <RecipesBook tenantId={tenantId} canEdit={w.data === true} canDelete={d.data === true} />;
}
