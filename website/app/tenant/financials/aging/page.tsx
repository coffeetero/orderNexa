import { requireArea } from '@/lib/supabase/guard';
import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { FinancialReport } from '@/components/features/financials/FinancialReport';

export const metadata = {
  title: 'AR Aging Report — Financials',
};

export default async function FinancialAgingPage() {
  await requireArea('financials.aging');
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No company found for this user.</div>;
  }
  return <FinancialReport tenantId={tenantId} kind="aging" />;
}
