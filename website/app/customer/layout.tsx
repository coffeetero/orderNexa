'use client';

import { useEffect, useState } from 'react';
import { usePathname, useRouter } from 'next/navigation';
import { CustomerSidebar } from '@/components/layout/CustomerSidebar';
import { DashboardHeader } from '@/components/layout/DashboardHeader';
import { supabase } from '@/lib/supabase';

const breadcrumbMap: Record<string, string> = {
  '/customer': 'Dashboard',
  '/customer/orders': 'Manage Orders',
  '/customer/orders/history': 'Order History',
  '/customer/invoicing': 'Statements',
  '/customer/invoicing/history': 'Invoice History',
  '/customer/payments': 'Payment Management',
  '/customer/payments/history': 'Payment History',
};

export default function CustomerLayout({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const [mobileOpen, setMobileOpen] = useState(false);
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const [authChecked, setAuthChecked] = useState(false);
  const pathname = usePathname();
  const breadcrumb = breadcrumbMap[pathname] ?? '';

  useEffect(() => {
    let isMounted = true;

    supabase.auth.getSession().then(({ data }) => {
      if (!isMounted) return;

      if (!data.session) {
        router.replace('/login');
        return;
      }

      setAuthChecked(true);
    });

    const { data: listener } = supabase.auth.onAuthStateChange((_event, session) => {
      if (!session) {
        router.replace('/login');
      }
    });

    return () => {
      isMounted = false;
      listener.subscription.unsubscribe();
    };
  }, [router]);

  if (!authChecked) {
    return null;
  }

  return (
    <div className="flex h-screen flex-col overflow-hidden">
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
