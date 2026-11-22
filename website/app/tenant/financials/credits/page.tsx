import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { CreditEntry } from '@/components/features/financials/CreditEntry';

export const metadata = {
  title: 'Enter Credits — Financials',
};

export default async function EnterCreditsPage() {
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No tenant found for this user.</div>;
  }
  return <CreditEntry tenantId={tenantId} />;
}
