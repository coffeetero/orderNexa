'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { Menu, Bell, Search, User, LogOut, Wheat, ChevronRight, Settings, Lock, CircleHelp as HelpCircle } from 'lucide-react';
import { useRouter } from 'next/navigation';
import { Button } from '@/components/ui/button';
import { ThemeToggle } from '@/components/layout/ThemeToggle';
import { createClient } from '@/lib/supabase/client';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';

const supabase = createClient();

interface DashboardHeaderProps {
  title: string;
  breadcrumb?: string;
  onMobileMenuOpen?: () => void;
  onSidebarToggle?: () => void;
  isSidebarCollapsed?: boolean;
  userName?: string;
  userRole?: string;
}

export function DashboardHeader({
  title,
  breadcrumb,
  onMobileMenuOpen,
  onSidebarToggle,
  isSidebarCollapsed = false,
  userName = 'Jacques Moreaux',
  userRole = 'Admin',
}: DashboardHeaderProps) {
  const router = useRouter();
  const [session, setSession] = useState<any>(null);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session);
    });

    const { data: listener } = supabase.auth.onAuthStateChange(
      (_event, session) => {
        setSession(session);
      }
    );

    return () => {
      listener.subscription.unsubscribe();
    };
  }, []);

  const handleLogout = async () => {
    await supabase.auth.signOut();
    setSession(null);
    router.replace('/login');
  };

  return (
    <header className="flex h-14 shrink-0 items-center justify-between border-b border-border bg-background px-4 sm:px-6">

      {/* LEFT SIDE: logo + breadcrumbs */}
      <div className="flex items-center gap-3">
        {onSidebarToggle && (
          <Button
            variant="ghost"
            size="icon"
            className="hidden h-8 w-8 lg:flex"
            onClick={onSidebarToggle}
            aria-label={isSidebarCollapsed ? 'Expand sidebar' : 'Collapse sidebar'}
          >
            <Menu className="h-4 w-4" />
          </Button>
        )}

        {onMobileMenuOpen && (
          <Button
            variant="ghost"
            size="icon"
            className="h-8 w-8 lg:hidden"
            onClick={onMobileMenuOpen}
          >
            <Menu className="h-4 w-4" />
          </Button>
        )}

        <Link href="/" className="flex items-center gap-2 group shrink-0">
          <div className="flex h-7 w-7 items-center justify-center rounded-full bg-primary/10 group-hover:bg-primary/20 transition-colors">
            <Wheat className="h-3.5 w-3.5 text-primary" />
          </div>
          <span
            className="hidden sm:block text-sm font-semibold text-foreground"
            style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
          >
            Alpine<span className="text-primary"> Bakery</span>
          </span>
        </Link>

        {breadcrumb && (
          <div className="hidden sm:flex items-center gap-1.5 text-xs text-muted-foreground">
            <ChevronRight className="h-3 w-3 shrink-0" />
            <span className="font-medium text-foreground/70">{title}</span>
            <ChevronRight className="h-3 w-3 shrink-0" />
            <span className="font-medium text-foreground">{breadcrumb}</span>
          </div>
        )}

        {!breadcrumb && (
          <div className="hidden sm:flex items-center gap-1.5 text-xs text-muted-foreground">
            <ChevronRight className="h-3 w-3 shrink-0" />
            <span className="font-medium text-foreground">{title}</span>
          </div>
        )}
      </div>

      {/* RIGHT SIDE */}
      <div className="flex items-center gap-2">
        <Button variant="ghost" size="icon" className="h-8 w-8 text-muted-foreground">
          <Search className="h-4 w-4" />
        </Button>

        <Button variant="ghost" size="icon" className="h-8 w-8 text-muted-foreground relative">
          <Bell className="h-4 w-4" />
          <span className="absolute top-1.5 right-1.5 h-1.5 w-1.5 rounded-full bg-primary" />
        </Button>

        <ThemeToggle />

        {session ? (
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button
                variant="ghost"
                className="flex items-center gap-2 pl-2 border-l border-border h-auto px-2 hover:bg-muted"
              >
                <div className="flex h-7 w-7 items-center justify-center rounded-full bg-primary/15 text-primary">
                  <User className="h-3.5 w-3.5" />
                </div>

                <div className="hidden sm:block text-left">
                  <p className="text-xs font-medium text-foreground leading-none">
                    {userName}
                  </p>
                  <p className="text-[10px] text-muted-foreground">
                    {userRole}
                  </p>
                </div>
              </Button>
            </DropdownMenuTrigger>

            <DropdownMenuContent align="end" className="w-56">
              <DropdownMenuItem>
                <User className="mr-2 h-4 w-4" />
                <span>User Profile</span>
              </DropdownMenuItem>
              <DropdownMenuItem>
                <Settings className="mr-2 h-4 w-4" />
                <span>Account Settings</span>
              </DropdownMenuItem>
              <DropdownMenuItem>
                <Bell className="mr-2 h-4 w-4" />
                <span>Notification Preferences</span>
              </DropdownMenuItem>
              <DropdownMenuItem>
                <Lock className="mr-2 h-4 w-4" />
                <span>Security</span>
              </DropdownMenuItem>

              <DropdownMenuSeparator />

              <DropdownMenuItem>
                <HelpCircle className="mr-2 h-4 w-4" />
                <span>Help</span>
              </DropdownMenuItem>
              <DropdownMenuItem onClick={handleLogout}>
                <LogOut className="mr-2 h-4 w-4" />
                <span>Logout</span>
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        ) : (
          <Button
            variant="default"
            size="sm"
            onClick={() => router.push('/login')}
          >
            Login
          </Button>
        )}
      </div>
    </header>
  );
}
