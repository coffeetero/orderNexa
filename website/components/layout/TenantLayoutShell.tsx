'use client';

import { useEffect, useState } from 'react';
import { usePathname, useRouter } from 'next/navigation';
import { TenantSidebar } from '@/components/layout/TenantSidebar';
import { DashboardHeader } from '@/components/layout/DashboardHeader';
import { createClient } from '@/lib/supabase/client';

const breadcrumbMap: Record<string, string> = {
  '/': 'Home',
  '/account': 'Dashboard',
  '/account/orders': 'Orders',
  '/account/customers': 'Customers',
};

type TenantLayoutShellProps = {
  children: React.ReactNode;
};

export function TenantLayoutShell({ children }: TenantLayoutShellProps) {
  const router = useRouter();
  const pathname = usePathname();
  const [collapsed, setCollapsed] = useState(false);
  const [mobileOpen, setMobileOpen] = useState(false);
  const [authChecked, setAuthChecked] = useState(false);

  const breadcrumb = breadcrumbMap[pathname] ?? '';

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
    <div className="flex h-screen overflow-hidden">
      <TenantSidebar
        collapsed={collapsed}
        onCollapse={setCollapsed}
        mobileOpen={mobileOpen}
        onMobileClose={() => setMobileOpen(false)}
      />

      <div className="flex flex-1 flex-col overflow-hidden">
        <DashboardHeader
          title="Bakery Dashboard"
          breadcrumb={breadcrumb}
          onMobileMenuOpen={() => setMobileOpen(true)}
          userName="Jacques Moreaux"
          userRole="Bakery Admin"
        />

        <main className="flex-1 overflow-y-auto bg-background pt-[1px] pb-[1px] px-[10px] scrollbar-thin">
          {children}
        </main>
      </div>
    </div>
  );
}
