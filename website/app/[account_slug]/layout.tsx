import { headers } from 'next/headers';
import { notFound, redirect } from 'next/navigation';
import { createClient, getSessionUser } from '@/lib/supabase/server';
import { getUserAccess } from '@/lib/supabase/access';
import { CustomerLayoutShell } from '@/components/layout/CustomerLayoutShell';
import { parseTenantSubdomain } from '@/lib/tenant-subdomain';

const DEFAULT_TIMEOUT_MINUTES = 5;

export default async function AccountSlugLayout({
  children,
  params,
}: {
  children: React.ReactNode;
  params: { account_slug: string };
}) {
  const host = headers().get('host') || '';
  if (!parseTenantSubdomain(host)) {
    notFound();
  }

  const { account_slug } = params;
  const user = await getSessionUser();

  if (!user) {
    redirect('/login');
  }

  const supabase = createClient();
  const access = await getUserAccess(user.id);

  if (access.userType === 'TENANCY_USER') {
    redirect('/dashboard');
  }

  if (access.userType === 'CUSTOMER_USER') {
    if (!access.accountSlug) {
      notFound();
    }
    if (access.accountSlug !== account_slug) {
      redirect(`/${access.accountSlug}`);
    }
  }

  const { data: customer, error: customerError } = await supabase
    .from('fnd_customers')
    .select('customer_id, customer_name')
    .eq('account_slug', account_slug)
    .maybeSingle();

  if (customerError || !customer) {
    notFound();
  }

  // Note: user.app_metadata (from auth.getUser) does not contain the hook's app_user_id claim — use fnd_users.user_id.
  let timeoutMinutes = DEFAULT_TIMEOUT_MINUTES;

  if (access.userId !== null) {
    const { data } = await supabase.rpc('fnd_session_get_timeout', {
      p_user_id: access.userId,
    });
    if (typeof data === 'number' && Number.isFinite(data)) {
      timeoutMinutes = data;
    }
  }

  const basePath = `/${account_slug}`;

  return (
    <CustomerLayoutShell
      timeoutMinutes={timeoutMinutes}
      basePath={basePath}
      userName={access.userName}
    >
      {children}
    </CustomerLayoutShell>
  );
}
