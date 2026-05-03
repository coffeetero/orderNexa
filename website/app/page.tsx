import { headers } from 'next/headers';
import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import { TenantLayoutShell } from '@/components/layout/TenantLayoutShell';
import { HomeContent } from '@/components/features/home/HomeContent';
import { parseTenantSubdomain } from '@/lib/tenant-subdomain';

export default async function HomePage() {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const host = headers().get('host') || '';
  const subdomain = parseTenantSubdomain(host);

  // This page only serves `/`; middleware passes subdomain `/` through with next()
  const isSubdomainRootContext = subdomain != null;

  if (isSubdomainRootContext) {
    if (!user) {
      return <HomeContent />;
    }

    const { data: profile } = await supabase
      .from('fnd_users')
      .select('user_type, account_slug')
      .eq('auth_user_id', user.id)
      .maybeSingle();

    if (profile?.user_type === 'TENANCY_USER') {
      redirect('/dashboard');
    }

    if (profile?.user_type === 'CUSTOMER_USER' && profile.account_slug) {
      redirect(`/${profile.account_slug}`);
    }

    return <HomeContent />;
  }

  if (user) {
    return (
      <TenantLayoutShell>
        <HomeContent withFooter={false} />
      </TenantLayoutShell>
    );
  }

  return <HomeContent />;
}
