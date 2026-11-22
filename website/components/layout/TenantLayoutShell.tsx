'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { TopNav } from '@/components/layout/TopNav';
import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { ContextSidebar } from '@/components/layout/ContextSidebar';
import { NavProvider } from '@/components/layout/nav-context';
import { AccountAppearanceLoader } from '@/components/theme/AppearanceProvider';
import { Sheet, SheetContent, SheetDescription, SheetTitle } from '@/components/ui/sheet';
import { createClient } from '@/lib/supabase/client';
import { tenantNav, visibleMenus } from '@/lib/nav-config';
import { SIDEBAR_COLLAPSED, SIDEBAR_COOKIE, SIDEBAR_OPEN } from '@/lib/sidebar-pref';
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
  /** Tenant the sidebar tracks activity for. Omit to hide the sidebar and its toggle. */
  tenantId?: number | null;
  /** Initial docked-sidebar state from the cookie. */
  sidebarCollapsed?: boolean;
  /** Areas the user may read; menus that require other areas are hidden. Omit to show every menu. */
  areas?: string[] | null;
};

const DOCKED_QUERY = '(min-width: 1280px)';

export function TenantLayoutShell({
  children,
  sidebarHomeHref = '/dashboard',
  contentClassName,
  userName,
  userRole,
  tenantId = null,
  sidebarCollapsed = false,
  areas = null,
}: TenantLayoutShellProps) {
  const router = useRouter();
  const [authChecked, setAuthChecked] = useState(false);
  const [collapsed, setCollapsed] = useState(sidebarCollapsed);
  const [drawerOpen, setDrawerOpen] = useState(false);
  // Wide screens dock the sidebar; narrower ones use the drawer. Tracked so the toggle reports the real state.
  const [docked, setDocked] = useState(true);

  useEffect(() => {
    const mq = window.matchMedia(DOCKED_QUERY);
    const update = () => {
      setDocked(mq.matches);
      if (mq.matches) setDrawerOpen(false);
    };
    update();
    mq.addEventListener('change', update);
    return () => mq.removeEventListener('change', update);
  }, []);

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

  const hasSidebar = tenantId !== null;

  // Wide screens: show/hide the docked sidebar (remembered). Narrower screens: open/close the drawer.
  const toggleSidebar = () => {
    if (docked) {
      const next = !collapsed;
      setCollapsed(next);
      try {
        document.cookie = `${SIDEBAR_COOKIE}=${next ? SIDEBAR_COLLAPSED : SIDEBAR_OPEN}; path=/; max-age=31536000; SameSite=Lax`;
      } catch {
        /* preference just won't persist */
      }
    } else {
      setDrawerOpen((open) => !open);
    }
  };

  return (
    <NavProvider tenantId={tenantId} areas={areas}>
      <AccountAppearanceLoader />
      <div className="flex h-screen flex-col overflow-hidden">
        <TopNav
          menus={visibleMenus(tenantNav, areas)}
          homeHref={sidebarHomeHref}
          brand="Alpine Bakery"
          userName={userName}
          userRole={userRole}
          profileHref="/tenant/profile"
          appearanceHref="/profile/appearance"
        />

        <Breadcrumbs
          showSidebarToggle={hasSidebar}
          sidebarOpen={docked ? !collapsed : drawerOpen}
          onToggleSidebar={toggleSidebar}
        />

        <div className="flex min-h-0 flex-1">
          {/* main comes first in the DOM (Tab reaches the page before the sidebar) but is shown to the right. */}
          <main className="order-2 min-w-0 flex-1 overflow-y-auto bg-background px-[10px] pb-[1px] scrollbar-thin">
            <div className={cn('mx-auto h-full w-full max-w-[1440px]', contentClassName)}>{children}</div>
          </main>

          {hasSidebar && !collapsed && (
            <aside
              id="context-sidebar"
              aria-label="Quick access and recent records"
              className="order-1 hidden w-[260px] shrink-0 overflow-y-auto border-r border-border bg-muted/20 scrollbar-thin xl:block"
            >
              <ContextSidebar />
            </aside>
          )}
        </div>

        {hasSidebar && (
          <Sheet open={drawerOpen} onOpenChange={setDrawerOpen}>
            <SheetContent side="left" className="w-[88vw] max-w-[300px] p-0">
              <SheetTitle className="sr-only">Quick access and recent records</SheetTitle>
              <SheetDescription className="sr-only">Your most-used actions and recently opened records</SheetDescription>
              <div className="h-full overflow-y-auto pt-8">
                <ContextSidebar onNavigate={() => setDrawerOpen(false)} />
              </div>
            </SheetContent>
          </Sheet>
        )}
      </div>
    </NavProvider>
  );
}
