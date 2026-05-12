import { ItemProfilePage } from '@/components/features/account/item-profile/ItemProfilePage';
import { createClient } from '@/lib/supabase/server';

export const metadata = {
  title: 'Item Profile - Inventory',
};

export default async function TenantItemProfileRoute() {
  const supabase = createClient();
  const { data: tenantData } = await supabase.rpc('fnd_tenants_get');
  const tenants = Array.isArray(tenantData) ? tenantData : [];
  const tenantId: number | undefined = tenants.length > 0 ? tenants[0].tenant_id : undefined;

  return <ItemProfilePage tenantId={tenantId} />;
}
