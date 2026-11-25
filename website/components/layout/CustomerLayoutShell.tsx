'use client';

import { useEffect, useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import { TopNav } from '@/components/layout/TopNav';
import { SessionTimeout } from '@/components/auth/SessionTimeout';
import { createClient } from '@/lib/supabase/client';
import { customerNav, visibleMenus } from '@/lib/nav-config';
import { ForceDefaultTheme } from '@/components/theme/AppearanceProvider';
import { ActivityPing } from '@/components/layout/ActivityPing';

type CustomerLayoutShellProps = {
  children: React.ReactNode;
  timeoutMinutes: number;
  basePath: string;
  userName?: string | null;
  /** Areas the user may read; menus that need other areas (e.g. Users) are hidden. */
  areas?: string[] | null;
  /** Shown under the user name — the customer account this user belongs to. */
};

export function CustomerLayoutShell({
  children,
  timeoutMinutes,
  basePath,
  userName,
  areas = null,
}: CustomerLayoutShellProps) {
  const router = useRouter();
  const [authChecked, setAuthChecked] = useState(false);
  const menus = useMemo(() => visibleMenus(customerNav(basePath), areas), [basePath, areas]);

  useEffect(() => {
    let isMounted = true;
    const supabase = createClient();

    supabase.auth.getSession().then(({ data }) => {
      if (!isMounted) return;

      if (!data.session) {
        router.replace('/login');
        return;
      }

      setAuthChecked(true);
    });

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      if (!session) {
        router.replace('/login');
      }
    });

    return () => {
      isMounted = false;
      subscription.unsubscribe();
    };
  }, [router]);

  if (!authChecked) {
    return null;
  }

  return (
    <div className="flex h-screen flex-col overflow-hidden">
      <ForceDefaultTheme />
      <ActivityPing />
      <SessionTimeout timeoutMinutes={timeoutMinutes} />

      <TopNav
        menus={menus}
        homeHref={basePath}
        brand="Customer Portal"
        userName={userName}
      />

      <main className="flex-1 overflow-y-auto bg-background p-4 scrollbar-thin sm:p-6">
        <div className="mx-auto w-full max-w-[1440px]">{children}</div>
      </main>
    </div>
  );
}
