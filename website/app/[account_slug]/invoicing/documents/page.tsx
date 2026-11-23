import { notFound } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { DocumentsList } from '@/components/features/financials/DocumentsList';

export const metadata = {
  title: 'Documents',
};

const TYPES = ['STATEMENT', 'INVOICE'];

export default async function AccountDocumentsPage({ params }: { params: { account_slug: string } }) {
  const tenantId = await getCurrentTenantId();
  const { data: customer } = await createClient()
    .from('fnd_customers')
    .select('customer_id')
    .eq('account_slug', params.account_slug)
    .maybeSingle();
  if (tenantId === null || !customer) notFound();
  return (
    <div className="space-y-2">
      <h2 className="text-2xl font-bold text-foreground">Statements & Invoices</h2>
      <p className="text-sm text-muted-foreground">Your saved statements and invoices. Open one to view, download or print it.</p>
      <DocumentsList tenantId={tenantId} customerId={customer.customer_id as number} types={TYPES} />
    </div>
  );
}
