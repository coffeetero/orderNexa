import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { ReportRunner } from '@/components/features/production/ReportRunner';

export const metadata = {
  title: "Route Delivery Report — Production",
};

export default async function RoutesReportPage() {
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No tenant found for this user.</div>;
  }
  return (
    <ReportRunner
      tenantId={tenantId}
      report="delivery"
      title={"Route Delivery Report"}
      description={"The driver's sheet: stops by delivery date and route with their invoices and items. Own-fleet deliveries only."}
    />
  );
}
