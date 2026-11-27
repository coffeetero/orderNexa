import { requireArea } from '@/lib/supabase/guard';
import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { createClient } from '@/lib/supabase/server';
import { TasksBoard } from '@/components/features/organizer/TasksBoard';

export const metadata = {
  title: 'Tasks — Organizer',
};

export default async function TasksPage() {
  await requireArea('organizer.tasks');
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No company found for this user.</div>;
  }
  const w = await (await createClient()).rpc('fnd_has_access', { p_area: 'organizer.tasks', p_action: 'W' });
  return <TasksBoard tenantId={tenantId} canEdit={w.data === true} />;
}
