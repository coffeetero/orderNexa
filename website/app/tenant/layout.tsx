import { redirect } from 'next/navigation';
import { TenantLayoutShell } from '@/components/layout/TenantLayoutShell';
import { createClient } from '@/lib/supabase/server';

export default async function TenantLayout({ children }: { children: React.ReactNode }) {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect('/login');
  }

  return <TenantLayoutShell>{children}</TenantLayoutShell>;
}
