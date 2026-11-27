import { requireArea } from '@/lib/supabase/guard';
import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { createClient } from '@/lib/supabase/server';
import { VendorsBook } from '@/components/features/purchasing/VendorsBook';

export const metadata = {
  title: 'Vendors — Purchasing',
};

export default async function Page() {
  await requireArea('purchasing.vendors');
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No company found for this user.</div>;
  }
  const supabase = await createClient();
  const [w, d] = await Promise.all([
    supabase.rpc('fnd_has_access', { p_area: 'purchasing.vendors', p_action: 'W' }),
    supabase.rpc('fnd_has_access', { p_area: 'purchasing.vendors', p_action: 'D' }),
  ]);
  return <VendorsBook tenantId={tenantId} canEdit={w.data === true} canDelete={d.data === true} />;
}
