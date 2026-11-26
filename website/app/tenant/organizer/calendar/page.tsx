import { requireArea } from '@/lib/supabase/guard';
import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { CalendarApp } from '@/components/features/organizer/CalendarApp';

export const metadata = {
  title: 'Calendar — Organizer',
};

export default async function CalendarPage() {
  await requireArea('organizer.calendar');
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No company found for this user.</div>;
  }
  return <CalendarApp tenantId={tenantId} />;
}
