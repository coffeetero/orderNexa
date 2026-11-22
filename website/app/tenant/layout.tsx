import { redirect } from 'next/navigation';
import { TenantLayoutShell } from '@/components/layout/TenantLayoutShell';
import { getSessionUser } from '@/lib/supabase/server';
import { getUserAccess } from '@/lib/supabase/access';

export default async function TenantLayout({ children }: { children: React.ReactNode }) {
  const user = await getSessionUser();

  if (!user) {
    redirect('/login');
  }

  const access = await getUserAccess(user.id);

  if (access.userType === 'CUSTOMER_USER' && access.accountSlug) {
    redirect(`/${access.accountSlug}`);
  }

  return (
    <TenantLayoutShell
      sidebarHomeHref="/dashboard"
      userName={access.userName}
      userRole={access.userType === 'TENANCY_USER' ? 'Staff' : null}
    >
      {children}
    </TenantLayoutShell>
  );
}
