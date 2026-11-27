import { requireArea } from '@/lib/supabase/guard';
import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { createClient } from '@/lib/supabase/server';
import { ContactsBook } from '@/components/features/organizer/ContactsBook';

export const metadata = {
  title: 'Contacts — Organizer',
};

export default async function ContactsPage() {
  await requireArea('organizer.contacts');
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No company found for this user.</div>;
  }
  const supabase = await createClient();
  const [w, d] = await Promise.all([
    supabase.rpc('fnd_has_access', { p_area: 'organizer.contacts', p_action: 'W' }),
    supabase.rpc('fnd_has_access', { p_area: 'organizer.contacts', p_action: 'D' }),
  ]);
  return <ContactsBook tenantId={tenantId} canEdit={w.data === true} canDelete={d.data === true} />;
}
