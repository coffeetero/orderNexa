import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { ReportRunner } from '@/components/features/production/ReportRunner';

export const metadata = {
  title: "Baker's Report — Production",
};

export default async function ReportReportPage() {
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No company found for this user.</div>;
  }
  return (
    <ReportRunner
      tenantId={tenantId}
      report="bakers"
      title={"Baker's Report"}
      description={"Item totals for each run in the date range, grouped by category. Printing records the print time, so a later change to an order is flagged \"changed since last print\"."}
    />
  );
}
