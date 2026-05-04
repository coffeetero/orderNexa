import { redirect } from 'next/navigation';
import { TenantLayoutShell } from '@/components/layout/TenantLayoutShell';
import { createClient, getSessionUser } from '@/lib/supabase/server';

export default async function TenantLayout({ children }: { children: React.ReactNode }) {
  const user = await getSessionUser();

  if (!user) {
    redirect('/login');
  }

  const supabase = createClient();
  const { data: profile } = await supabase
    .from('fnd_users')
    .select('user_type, account_slug')
    .eq('auth_user_id', user.id)
    .maybeSingle();

  if (profile?.user_type === 'CUSTOMER_USER' && profile.account_slug) {
    redirect(`/${profile.account_slug}`);
  }

  return <TenantLayoutShell sidebarHomeHref="/dashboard">{children}</TenantLayoutShell>;
}
