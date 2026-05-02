import { createClient } from '@/lib/supabase/server';
import { TenantLayoutShell } from '@/components/layout/TenantLayoutShell';
import { HomeContent } from '@/components/features/home/HomeContent';

export default async function HomePage() {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (user) {
    return (
      <TenantLayoutShell>
        <HomeContent withFooter={false} />
      </TenantLayoutShell>
    );
  }

  return <HomeContent />;
}
