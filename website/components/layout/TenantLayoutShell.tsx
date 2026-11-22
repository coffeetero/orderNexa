'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { TopNav } from '@/components/layout/TopNav';
import { createClient } from '@/lib/supabase/client';
import { tenantNav } from '@/lib/nav-config';
import { cn } from '@/lib/utils';

type TenantLayoutShellProps = {
  children: React.ReactNode;
  /** Logo / home target for tenancy staff vs customer-in-tenant shell */
  sidebarHomeHref?: string;
  /** Optional page-shell override. Default centers content at the standard app width. */
  contentClassName?: string;
  /** Signed-in user shown in the header (from fnd_users.user_name). */
  userName?: string | null;
  userRole?: string | null;
};

export function TenantLayoutShell({
  children,
  sidebarHomeHref = '/dashboard',
  contentClassName,
  userName,
  userRole,
}: TenantLayoutShellProps) {
  const router = useRouter();
  const [authChecked, setAuthChecked] = useState(false);

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
      <TopNav
        menus={tenantNav}
        homeHref={sidebarHomeHref}
        brand="Alpine Bakery"
        userName={userName}
        userRole={userRole}
        profileHref="/tenant/profile"
        settingsHref="/tenant/settings"
      />

      <main className="flex-1 overflow-y-auto bg-background px-[10px] pb-[1px] scrollbar-thin">
        <div className={cn('mx-auto h-full w-full max-w-[1440px]', contentClassName)}>{children}</div>
      </main>
    </div>
  );
}
