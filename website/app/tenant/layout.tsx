'use client';

import { useState, useEffect } from 'react';
import { useRouter, usePathname } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';
import { TenantSidebar } from '@/components/layout/TenantSidebar';
import { DashboardHeader } from '@/components/layout/DashboardHeader';

const supabase = createClient();

const breadcrumbMap: Record<string, string> = {
  '/tenant': 'Dashboard',
  '/tenant/orders': 'Orders',
  '/tenant/customers': 'Customers',
};

export default function TenantLayout({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const pathname = usePathname();

  const [collapsed, setCollapsed] = useState(false);
  const [mobileOpen, setMobileOpen] = useState(false);
  const [loading, setLoading] = useState(true);

  const breadcrumb = breadcrumbMap[pathname] ?? '';

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      if (!data.session) {
        router.replace('/login');
      } else {
        setLoading(false);
      }
    });
  }, []);

  if (loading) {
    return <div className="p-6">Loading...</div>;
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

        <main className="flex-1 overflow-y-auto bg-background p-4 sm:p-6 scrollbar-thin">
          {children}
        </main>
      </div>
    </div>
  );
}
