import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { ReportRunner } from '@/components/features/production/ReportRunner';

export const metadata = {
  title: "Print Invoices — Production",
};

export default async function PrintInvoicesPage() {
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No company found for this user.</div>;
  }
  return (
    <ReportRunner
      tenantId={tenantId}
      report="invoices"
      title={"Print Invoices"}
      description={"The customers' invoices for these production dates, in the old BPS invoice layout, grouped by department or event. Issued invoices only (old and new); printing changes nothing."}
      customerBasis="PRINT"
      customerColumnLabel="Invoices"
    />
  );
}
