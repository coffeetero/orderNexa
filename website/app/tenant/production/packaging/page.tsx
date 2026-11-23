import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { ReportRunner } from '@/components/features/production/ReportRunner';

export const metadata = {
  title: "Packaging List — Production",
};

export default async function PackagingReportPage() {
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No company found for this user.</div>;
  }
  return (
    <ReportRunner
      tenantId={tenantId}
      report="packaging"
      title={"Packaging List"}
      description={"The invoice that goes in the bag, with orders grouped by department or event. Printing gives each draft invoice its number and locks it; printing again reuses the same numbers."}
      customerBasis="INVOICE"
      customerColumnLabel="Invoices"
    />
  );
}
