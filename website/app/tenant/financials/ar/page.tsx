import { requireArea } from '@/lib/supabase/guard';
import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { FinancialReport } from '@/components/features/financials/FinancialReport';

export const metadata = {
  title: 'AR Open Balances — Financials',
};

export default async function FinancialArPage() {
  await requireArea('financials.ar');
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No company found for this user.</div>;
  }
  return <FinancialReport tenantId={tenantId} kind="ar" />;
}
