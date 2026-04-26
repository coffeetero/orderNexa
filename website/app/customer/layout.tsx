import { redirect } from 'next/navigation';
import { CustomerLayoutShell } from '@/components/layout/CustomerLayoutShell';
import { createClient } from '@/lib/supabase/server';

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

export default async function CustomerLayout({ children }: { children: React.ReactNode }) {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect('/login');
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

  return <CustomerLayoutShell timeoutMinutes={timeoutMinutes}>{children}</CustomerLayoutShell>;
}
