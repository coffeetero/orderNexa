import { requireArea } from '@/lib/supabase/guard';
import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { ManagePayments } from '@/components/features/financials/ManagePayments';

export const metadata = {
  title: 'Payment History — Financials',
};

export default async function ManagePaymentsPage(props: { searchParams: Promise<{ id?: string }> }) {
  const searchParams = await props.searchParams;
  await requireArea('financials.payments');
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No company found for this user.</div>;
  }
  const id = Number(searchParams.id);
  return <ManagePayments tenantId={tenantId} initialPaymentId={Number.isSafeInteger(id) && id > 0 ? id : null} />;
}
