import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { ReportRunner } from '@/components/features/production/ReportRunner';

export const metadata = {
  title: "Packing Labels — Production",
};

export default async function LabelsReportPage() {
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No company found for this user.</div>;
  }
  return (
    <ReportRunner
      tenantId={tenantId}
      report="labels"
      title={"Packing Labels"}
      description={"One 4\" x 2\" label per order line. Pick the customers to include; none are selected by default."}
      customerBasis="ORDER"
      customerColumnLabel="Orders"
    />
  );
}
