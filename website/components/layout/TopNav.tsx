'use client';

import { Fragment, useState } from 'react';
import { GuardedLink as Link } from '@/components/layout/GuardedLink';
import { usePathname, useRouter } from 'next/navigation';
import {
  Bell,
  ChevronDown,
  LayoutGrid,
  CircleHelp as HelpCircle,
  LogOut,
  Menu,
  Palette,
  User,
  Wheat,
} from 'lucide-react';
import { cn } from '@/lib/utils';
import { useNav } from '@/components/layout/nav-context';
import { useIsMac } from '@/components/layout/QuickBar';
import { createClient } from '@/lib/supabase/client';
import { findActiveHref, findActiveMenu, type NavItem, type NavMenu } from '@/lib/nav-config';
import { Button } from '@/components/ui/button';
import { ThemeToggle } from '@/components/layout/ThemeToggle';
import { HealthHeart } from '@/components/layout/HealthHeart';
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from '@/components/ui/accordion';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import {
  Menubar,
  MenubarContent,
  MenubarGroup,
  MenubarItem,
  MenubarLabel,
  MenubarSeparator,
  MenubarMenu,
  MenubarTrigger,
} from '@/components/ui/menubar';
import { Sheet, SheetClose, SheetContent, SheetDescription, SheetTitle } from '@/components/ui/sheet';

const supabase = createClient();

function initials(name?: string | null): string | null {
  const parts = (name ?? '').trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return null;
  const first = parts[0][0];
  const last = parts.length > 1 ? parts[parts.length - 1][0] : (parts[0][1] ?? '');
  return (first + last).toUpperCase();
}

type TopNavProps = {
  menus: NavMenu[];
  /** Logo target (staff dashboard, or the customer's own dashboard). */
  homeHref: string;
  brand: string;
  userName?: string | null;
  /** Staff-only user-menu entries. Omit for customer users. */
  profileHref?: string;
  appearanceHref?: string;
  /** Staff with Health Checks access: shows the heart, linking here. */
  healthHref?: string;
};

const topLevelClass =
  'relative inline-flex h-9 items-center gap-1 rounded-md px-3 text-sm font-medium text-foreground/70 outline-none ' +
  'transition-colors hover:bg-muted hover:text-foreground focus-visible:ring-2 focus-visible:ring-ring ' +
  'focus:bg-transparent focus:text-foreground/70 focus-visible:bg-muted focus-visible:text-foreground ' +
  'data-[state=open]:bg-muted data-[state=open]:text-foreground';

const activeIndicator =
  'text-foreground after:absolute after:inset-x-3 after:-bottom-[10px] after:h-0.5 after:rounded-full after:bg-primary';

function SoonBadge() {
  return (
    <span className="ml-auto rounded-full bg-muted px-1.5 py-0.5 text-[10px] font-medium uppercase tracking-wide text-muted-foreground">
      Soon
    </span>
  );
}

export function TopNav({
  menus,
  homeHref,
  brand,
  userName,
  profileHref,
  healthHref,
  appearanceHref,
}: TopNavProps) {
  const router = useRouter();
  const pathname = usePathname();
  const [drawerOpen, setDrawerOpen] = useState(false);
  const { tenantId, setQuickButtonsOpen, quickHrefs } = useNav();
  const isMac = useIsMac();

  const activeHref = findActiveHref(pathname, menus);
  const activeMenu = findActiveMenu(pathname, menus);

  const handleLogout = async () => {
    await supabase.auth.signOut();
    router.replace('/login');
  };

  // Quick-button keys (Alt+Shift+1..4) next to the screens the user put on them
  const quickKey = (href: string) => {
    const i = quickHrefs.indexOf(href);
    return i < 0 ? null : `${isMac ? '⌥⇧' : 'Alt+Shift+'}${i + 1}`;
  };

  const desktopItem = (item: NavItem) => (
    <Fragment key={item.href}>
    {item.divider && <MenubarSeparator className="mx-2 my-1" />}
    <MenubarItem
      asChild
      disabled={item.soon}
      className="gap-2 py-1 pl-5 data-[disabled]:opacity-60"
    >
      {item.soon ? (
        <span title="Coming soon" aria-disabled="true">
          {item.label}
          <SoonBadge />
        </span>
      ) : (
        <Link
          href={item.href}
          aria-current={item.href === activeHref ? 'page' : undefined}
          className={cn('cursor-pointer', item.href === activeHref && 'bg-accent font-medium text-accent-foreground', item.bold && 'font-semibold')}
        >
          {item.label}
          {quickKey(item.href) && (
            <span className="ml-auto pl-4 text-[10px] tabular-nums text-muted-foreground">{quickKey(item.href)}</span>
          )}
        </Link>
      )}
    </MenubarItem>
    </Fragment>
  );

  return (
    <header className="bps-topnav sticky top-0 z-40 flex h-14 shrink-0 items-center gap-2 border-b border-border bg-background/95 px-3 backdrop-blur supports-[backdrop-filter]:bg-background/80 sm:px-4">
      {/* Mobile menu button */}
      <Button
        variant="ghost"
        size="icon"
        className="h-9 w-9 lg:hidden"
        onClick={() => setDrawerOpen(true)}
        aria-label="Open navigation menu"
      >
        <Menu className="h-5 w-5" />
      </Button>

      {/* Brand */}
      <Link href={homeHref} className="mr-1 flex items-center gap-2 lg:mr-4">
        <Wheat className="h-5 w-5 text-primary" />
        <span
          className="hidden text-base font-semibold sm:inline"
          style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
        >
          {brand}
        </span>
      </Link>

      {/* Desktop navigation */}
      <Menubar
        aria-label="Main navigation"
        className="hidden h-auto flex-1 space-x-0.5 border-0 bg-transparent p-0 shadow-none lg:flex"
      >
        {menus.map((menu) => {
          const isActiveMenu = activeMenu?.label === menu.label;

          if (menu.href) {
            return (
              <Link
                key={menu.label}
                href={menu.href}
                aria-current={menu.href === activeHref ? 'page' : undefined}
                className={cn(topLevelClass, isActiveMenu && activeIndicator)}
              >
                {menu.label}
              </Link>
            );
          }

          const groups = menu.groups ?? [];
          const columns = menu.columns ?? (groups.length >= 3 ? 2 : 1);

          return (
            <MenubarMenu key={menu.label}>
              <MenubarTrigger className={cn(topLevelClass, 'cursor-pointer bg-transparent', isActiveMenu && activeIndicator)}>
                {menu.label}
                <ChevronDown className="h-3 w-3 opacity-60" />
              </MenubarTrigger>
              <MenubarContent
                className={cn(
                  'max-h-[calc(100vh-5rem)] overflow-y-auto p-2',
                  columns === 3 && 'grid w-[44rem] grid-cols-3 gap-x-4 gap-y-3',
                  columns === 2 && 'grid w-[32rem] grid-cols-2 gap-x-4 gap-y-3',
                  columns === 1 && 'min-w-[16rem] space-y-2',
                )}
              >
                {groups.map((group, gi) => (
                  <MenubarGroup key={group.heading ?? gi} className="space-y-px">
                    {group.heading && (
                      <MenubarLabel className="mb-0.5 border-b border-border px-2 pb-1 pt-1 text-[11px] font-bold uppercase tracking-wider text-primary">
                        {group.heading}
                      </MenubarLabel>
                    )}
                    {group.items.map(desktopItem)}
                  </MenubarGroup>
                ))}
              </MenubarContent>
            </MenubarMenu>
          );
        })}
      </Menubar>

      <div className="flex-1 lg:hidden" />

      {/* Right-hand controls */}
      <div className="flex items-center gap-1">
        {healthHref && <HealthHeart href={healthHref} />}
        <Button variant="ghost" size="icon" className="relative hidden h-9 w-9 text-muted-foreground sm:inline-flex" aria-label="Notifications">
          <Bell className="h-4 w-4" />
          <span className="absolute right-2 top-2 h-1.5 w-1.5 rounded-full bg-primary" />
        </Button>
        <ThemeToggle />

        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="ghost" className="ml-1 h-9 border-l border-border px-2 hover:bg-muted" aria-label={`User menu${userName ? `, ${userName}` : ''}`}>
              <span className="flex h-8 w-8 items-center justify-center rounded-full bg-primary/15 text-xs font-semibold text-primary">
                {initials(userName) ?? <User className="h-3.5 w-3.5" />}
              </span>
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-56">
            <DropdownMenuLabel className="truncate font-normal">
              <span className="block truncate text-sm font-medium">{userName || 'Signed-in user'}</span>
            </DropdownMenuLabel>
            <DropdownMenuSeparator />
            {profileHref && (
              <DropdownMenuItem onClick={() => router.push(profileHref)}>
                <User className="mr-2 h-4 w-4" />
                User Profile
              </DropdownMenuItem>
            )}
            {appearanceHref && (
              <DropdownMenuItem onClick={() => router.push(appearanceHref)}>
                <Palette className="mr-2 h-4 w-4" />
                Appearance
              </DropdownMenuItem>
            )}
            {tenantId && (
              <DropdownMenuItem onClick={() => setQuickButtonsOpen(true)}>
                <LayoutGrid className="mr-2 h-4 w-4" />
                Quick Buttons
              </DropdownMenuItem>
            )}
            <DropdownMenuItem disabled>
              <Bell className="mr-2 h-4 w-4" />
              Notification Preferences
              <SoonBadge />
            </DropdownMenuItem>
            <DropdownMenuSeparator />
            <DropdownMenuItem disabled>
              <HelpCircle className="mr-2 h-4 w-4" />
              Help
              <SoonBadge />
            </DropdownMenuItem>
            <DropdownMenuItem onClick={() => router.push('/')}>
              <Wheat className="mr-2 h-4 w-4" />
              Back to Site
            </DropdownMenuItem>
            <DropdownMenuItem onClick={handleLogout}>
              <LogOut className="mr-2 h-4 w-4" />
              Logout
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>

      {/* Mobile drawer */}
      <Sheet open={drawerOpen} onOpenChange={setDrawerOpen}>
        <SheetContent side="left" className="flex w-[88vw] max-w-sm flex-col gap-0 p-0">
          <SheetTitle className="sr-only">Navigation</SheetTitle>
          <SheetDescription className="sr-only">Site navigation menu</SheetDescription>

          <div className="flex h-14 shrink-0 items-center gap-2 border-b border-border px-4">
            <Wheat className="h-5 w-5 text-primary" />
            <span className="text-base font-semibold" style={{ fontFamily: "'Playfair Display', Georgia, serif" }}>
              {brand}
            </span>
          </div>

          <nav aria-label="Mobile navigation" className="flex-1 overflow-y-auto px-2 py-3">
            <Accordion type="single" collapsible defaultValue={activeMenu && !activeMenu.href ? activeMenu.label : undefined}>
              {menus.map((menu) =>
                menu.href ? (
                  <SheetClose asChild key={menu.label}>
                    <Link
                      href={menu.href}
                      aria-current={menu.href === activeHref ? 'page' : undefined}
                      className={cn(
                        'flex h-11 items-center rounded-md px-3 text-sm font-medium hover:bg-muted',
                        menu.href === activeHref ? 'bg-accent text-accent-foreground' : 'text-foreground/80',
                      )}
                    >
                      {menu.label}
                    </Link>
                  </SheetClose>
                ) : (
                  <AccordionItem key={menu.label} value={menu.label} className="border-b-0">
                    <AccordionTrigger
                      className={cn(
                        'h-11 rounded-md px-3 py-0 text-sm font-medium hover:bg-muted hover:no-underline',
                        activeMenu?.label === menu.label ? 'text-primary' : 'text-foreground/80',
                      )}
                    >
                      {menu.label}
                    </AccordionTrigger>
                    <AccordionContent className="pb-1">
                      {(menu.groups ?? []).map((group, gi) => (
                        <div key={group.heading ?? gi} className="mb-1">
                          {group.heading && (
                            <p className="px-3 pb-1 pt-2 text-[11px] font-semibold uppercase tracking-wider text-muted-foreground">
                              {group.heading}
                            </p>
                          )}
                          {group.items.map((item) =>
                            item.soon ? (
                              <span
                                key={item.href}
                                aria-disabled="true"
                                className="flex h-10 items-center rounded-md pl-6 pr-3 text-sm text-muted-foreground/70"
                              >
                                {item.label}
                                <SoonBadge />
                              </span>
                            ) : (
                              <SheetClose asChild key={item.href}>
                                <Link
                                  href={item.href}
                                  aria-current={item.href === activeHref ? 'page' : undefined}
                                  className={cn(
                                    'flex h-10 items-center rounded-md pl-6 pr-3 text-sm hover:bg-muted',
                                    item.href === activeHref ? 'bg-accent font-medium text-accent-foreground' : 'text-foreground/80',
                                    item.bold && 'font-semibold',
                                  )}
                                >
                                  {item.label}
                                </Link>
                              </SheetClose>
                            ),
                          )}
                        </div>
                      ))}
                    </AccordionContent>
                  </AccordionItem>
                ),
              )}
            </Accordion>
          </nav>

          <div className="shrink-0 border-t border-border p-2">
            <SheetClose asChild>
              <Link href="/" className="flex h-10 items-center gap-2 rounded-md px-3 text-sm text-muted-foreground hover:bg-muted hover:text-foreground">
                <Wheat className="h-4 w-4" />
                Back to Site
              </Link>
            </SheetClose>
          </div>
        </SheetContent>
      </Sheet>
    </header>
  );
}
