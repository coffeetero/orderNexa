import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { TenantLayoutShell } from '@/components/layout/TenantLayoutShell';
import { SIDEBAR_COLLAPSED, SIDEBAR_COOKIE } from '@/lib/sidebar-pref';
import { createClient, getSessionUser } from '@/lib/supabase/server';
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

  // Tenant the sidebar tracks recent records for (same RPC the pages use).
  let tenantId: number | null = null;
  if (access.userType === 'TENANCY_USER') {
    const { data: tenantData } = await createClient().rpc('fnd_tenants_get');
    const first = Array.isArray(tenantData) ? tenantData[0] : null;
    tenantId = typeof first?.tenant_id === 'number' ? first.tenant_id : null;
  }
  const sidebarCollapsed = cookies().get(SIDEBAR_COOKIE)?.value === SIDEBAR_COLLAPSED;

  return (
    <TenantLayoutShell
      sidebarHomeHref="/dashboard"
      userName={access.userName}
      userRole={access.userType === 'TENANCY_USER' ? 'Staff' : null}
      tenantId={tenantId}
      sidebarCollapsed={sidebarCollapsed}
    >
      {children}
    </TenantLayoutShell>
  );
}
