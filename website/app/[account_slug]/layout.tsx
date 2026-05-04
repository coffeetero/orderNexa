import { headers } from 'next/headers';
import { notFound, redirect } from 'next/navigation';
import { createClient, getSessionUser } from '@/lib/supabase/server';
import { CustomerLayoutShell } from '@/components/layout/CustomerLayoutShell';
import { parseTenantSubdomain } from '@/lib/tenant-subdomain';

const DEFAULT_TIMEOUT_MINUTES = 5;

function parseAppUserId(appUserId: unknown): number | null {
  if (typeof appUserId === 'number' && Number.isInteger(appUserId)) {
    return appUserId;
  }
  if (typeof appUserId === 'string' && appUserId.trim().length > 0) {
    const parsed = Number(appUserId);
    return Number.isInteger(parsed) ? parsed : null;
  }
  return null;
}

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
  const { data: profile } = await supabase
    .from('fnd_users')
    .select('user_type, account_slug')
    .eq('auth_user_id', user.id)
    .maybeSingle();

  if (profile?.user_type === 'TENANCY_USER') {
    redirect('/dashboard');
  }

  if (profile?.user_type === 'CUSTOMER_USER') {
    if (!profile.account_slug) {
      notFound();
    }
    if (profile.account_slug !== account_slug) {
      redirect(`/${profile.account_slug}`);
    }
  }

  const { data: customer, error: customerError } = await supabase
    .from('fnd_customers')
    .select('customer_id')
    .eq('account_slug', account_slug)
    .maybeSingle();

  if (customerError || !customer) {
    notFound();
  }

  const appUserId = parseAppUserId(user.app_metadata?.app_user_id);
  let timeoutMinutes = DEFAULT_TIMEOUT_MINUTES;

  if (appUserId !== null) {
    const { data } = await supabase.rpc('fnd_get_session_timeout', {
      p_user_id: appUserId,
    });
    if (typeof data === 'number' && Number.isFinite(data)) {
      timeoutMinutes = data;
    }
  }

  const basePath = `/${account_slug}`;

  return (
    <CustomerLayoutShell timeoutMinutes={timeoutMinutes} basePath={basePath}>
      {children}
    </CustomerLayoutShell>
  );
}
