'use client';

import { useEffect, useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import { TopNav } from '@/components/layout/TopNav';
import { SessionTimeout } from '@/components/auth/SessionTimeout';
import { createClient } from '@/lib/supabase/client';
import { customerNav } from '@/lib/nav-config';

type CustomerLayoutShellProps = {
  children: React.ReactNode;
  timeoutMinutes: number;
  basePath: string;
  userName?: string | null;
  /** Shown under the user name — the customer account this user belongs to. */
  accountName?: string | null;
};

export function CustomerLayoutShell({
  children,
  timeoutMinutes,
  basePath,
  userName,
  accountName,
}: CustomerLayoutShellProps) {
  const router = useRouter();
  const [authChecked, setAuthChecked] = useState(false);
  const menus = useMemo(() => customerNav(basePath), [basePath]);

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
      <SessionTimeout timeoutMinutes={timeoutMinutes} />

      <TopNav
        menus={menus}
        homeHref={basePath}
        brand="Customer Portal"
        userName={userName}
        userRole={accountName}
      />

      <main className="flex-1 overflow-y-auto bg-background p-4 scrollbar-thin sm:p-6">
        <div className="mx-auto w-full max-w-[1440px]">{children}</div>
      </main>
    </div>
  );
}
