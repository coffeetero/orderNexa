'use client';

import { useEffect, useState } from 'react';
import { usePathname, useRouter } from 'next/navigation';
import { CustomerSidebar } from '@/components/layout/CustomerSidebar';
import { DashboardHeader } from '@/components/layout/DashboardHeader';
import { SessionTimeout } from '@/components/auth/SessionTimeout';
import { createClient } from '@/lib/supabase/client';

const breadcrumbMap: Record<string, string> = {
  '/customer': 'Dashboard',
  '/customer/orders': 'Manage Orders',
  '/customer/orders/history': 'Order History',
  '/customer/invoicing': 'Statements',
  '/customer/invoicing/history': 'Invoice History',
  '/customer/payments': 'Payment Management',
  '/customer/payments/history': 'Payment History',
};

type CustomerLayoutShellProps = {
  children: React.ReactNode;
  timeoutMinutes: number;
};

export function CustomerLayoutShell({ children, timeoutMinutes }: CustomerLayoutShellProps) {
  const router = useRouter();
  const pathname = usePathname();

  const [mobileOpen, setMobileOpen] = useState(false);
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
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