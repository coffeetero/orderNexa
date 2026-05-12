'use client';

import { useEffect, useState } from 'react';
import { usePathname, useRouter } from 'next/navigation';
import { TenantSidebar } from '@/components/layout/TenantSidebar';
import { DashboardHeader } from '@/components/layout/DashboardHeader';
import { createClient } from '@/lib/supabase/client';

const breadcrumbMap: Record<string, string> = {
  '/': 'Home',
  '/dashboard': 'Dashboard',
  '/orders': 'Enter Orders',
  '/orders/new': 'Enter Orders',
  '/manage-orders': 'Manage Orders',
  '/customers': 'Customers',
  '/inventory/item-profile': 'Item Profile',
  // Legacy paths (e.g. main host without subdomain)
  '/tenant': 'Dashboard',
  '/tenant/dashboard': 'Dashboard',
  '/tenant/orders': 'Enter Orders',
  '/tenant/orders/new': 'Enter Orders',
  '/tenant/manage-orders': 'Manage Orders',
  '/tenant/customers': 'Customers',
  '/tenant/inventory/item-profile': 'Item Profile',
};

/** Resolves breadcrumb label for dynamic routes not in the static map. */
function resolveBreadcrumb(pathname: string): string {
  const staticLabel = breadcrumbMap[pathname];
  if (staticLabel) return staticLabel;
  if (/^\/orders\/\d+\/edit$/.test(pathname)) return 'Edit Order';
  if (/^\/tenant\/orders\/\d+\/edit$/.test(pathname)) return 'Edit Order';
  return '';
}

type TenantLayoutShellProps = {
  children: React.ReactNode;
  /** Logo / home target for tenancy staff vs customer-in-tenant shell */
  sidebarHomeHref?: string;
};

export function TenantLayoutShell({ children, sidebarHomeHref = '/dashboard' }: TenantLayoutShellProps) {
  const router = useRouter();
  const pathname = usePathname();
  const [collapsed, setCollapsed] = useState(false);
  const [mobileOpen, setMobileOpen] = useState(false);
  const [authChecked, setAuthChecked] = useState(false);

  const breadcrumb = resolveBreadcrumb(pathname);

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
        homeHref={sidebarHomeHref}
      />

      <div className="flex flex-1 flex-col overflow-hidden">
        <DashboardHeader
          title="Bakery Dashboard"
          breadcrumb={breadcrumb}
          onMobileMenuOpen={() => setMobileOpen(true)}
          userName="Jacques Moreaux"
          userRole="Bakery Admin"
        />

        <main className="flex-1 overflow-y-auto bg-background pb-[1px] px-[10px] scrollbar-thin">
          {children}
        </main>
      </div>
    </div>
  );
}
