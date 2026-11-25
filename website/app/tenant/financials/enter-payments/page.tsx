import { requireArea } from '@/lib/supabase/guard';
import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { EnterPayments } from '@/components/features/financials/EnterPayments';

export const metadata = { title: 'Enter Payments — Financials' };

export default async function EnterPaymentsPage() {
  await requireArea('financials.payments');
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) return <div className="p-6 text-sm text-muted-foreground">No company found for this user.</div>;
  return <EnterPayments tenantId={tenantId} />;
}
