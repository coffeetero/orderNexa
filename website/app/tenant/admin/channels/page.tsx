import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { ChannelsAdmin } from '@/components/features/admin/ChannelsAdmin';

export const metadata = {
  title: 'Phone & Messaging Numbers — Admin',
};

export default async function AdminChannelsAdminPage() {
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No tenant found for this user.</div>;
  }
  return <ChannelsAdmin tenantId={tenantId} />;
}
