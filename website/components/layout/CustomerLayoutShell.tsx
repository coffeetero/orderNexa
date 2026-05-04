'use client';

import { useEffect, useState } from 'react';
import { usePathname, useRouter } from 'next/navigation';
import { CustomerSidebar } from '@/components/layout/CustomerSidebar';
import { DashboardHeader } from '@/components/layout/DashboardHeader';
import { SessionTimeout } from '@/components/auth/SessionTimeout';
import { createClient } from '@/lib/supabase/client';

function customerBreadcrumb(pathname: string, basePath: string): string {
  if (pathname === basePath) return 'Dashboard';
  const suffix = pathname.startsWith(`${basePath}/`) ? pathname.slice(basePath.length) : '';
  const map: Record<string, string> = {
    '/orders': 'Manage Orders',
    '/orders/history': 'Order History',
    '/invoicing': 'Statements',
    '/invoicing/history': 'Invoice History',
    '/payments': 'Payment Management',
    '/payments/history': 'Payment History',
  };
  return map[suffix] ?? '';
}

type CustomerLayoutShellProps = {
  children: React.ReactNode;
  timeoutMinutes: number;
  basePath: string;
};

export function CustomerLayoutShell({ children, timeoutMinutes, basePath }: CustomerLayoutShellProps) {
  const router = useRouter();
  const pathname = usePathname();

  const [mobileOpen, setMobileOpen] = useState(false);
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const [authChecked, setAuthChecked] = useState(false);

  const breadcrumb = customerBreadcrumb(pathname, basePath);

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

      <DashboardHeader
        title="Customer Portal"
        breadcrumb={breadcrumb}
        onMobileMenuOpen={() => setMobileOpen(true)}
        onSidebarToggle={() => setSidebarCollapsed((prev) => !prev)}
        isSidebarCollapsed={sidebarCollapsed}
        userName="Marie Dupont"
        userRole="Le Jardin Restaurant"
      />

      <div className="flex flex-1 overflow-hidden">
        <CustomerSidebar
          basePath={basePath}
          mobileOpen={mobileOpen}
          onMobileClose={() => setMobileOpen(false)}
          collapsed={sidebarCollapsed}
        />

        <main className="flex-1 overflow-y-auto bg-background p-4 sm:p-6 scrollbar-thin">
          {children}
        </main>
      </div>
    </div>
  );
}