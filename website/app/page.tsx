import { headers } from 'next/headers';
import { redirect } from 'next/navigation';
import { getSessionUser } from '@/lib/supabase/server';
import { getUserAccess } from '@/lib/supabase/access';
import { TenantLayoutShell } from '@/components/layout/TenantLayoutShell';
import { HomeContent } from '@/components/features/home/HomeContent';
import { parseTenantSubdomain } from '@/lib/tenant-subdomain';

export default async function HomePage() {
  const user = await getSessionUser();

  const host = headers().get('host') || '';
  const subdomain = parseTenantSubdomain(host);

  // This page only serves `/`; middleware passes subdomain `/` through with next()
  const isSubdomainRootContext = subdomain != null;

  if (isSubdomainRootContext) {
    if (!user) {
      return <HomeContent />;
    }

    const access = await getUserAccess(user.id);

    if (access.userType === 'TENANCY_USER') {
      redirect('/dashboard');
    }

    if (access.userType === 'CUSTOMER_USER' && access.accountSlug) {
      redirect(`/${access.accountSlug}`);
    }

    return <HomeContent />;
  }

  if (user) {
    const access = await getUserAccess(user.id);

    const sidebarHomeHref =
      access.userType === 'CUSTOMER_USER' && access.accountSlug
        ? `/${access.accountSlug}`
        : '/dashboard';

    return (
      <TenantLayoutShell
        sidebarHomeHref={sidebarHomeHref}
        userName={access.userName}
        userRole={access.userType === 'TENANCY_USER' ? 'Staff' : null}
      >
        <HomeContent withFooter={false} />
      </TenantLayoutShell>
    );
  }

  return <HomeContent />;
}
