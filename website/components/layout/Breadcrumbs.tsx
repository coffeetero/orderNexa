'use client';

import { Fragment } from 'react';
import { usePathname } from 'next/navigation';
import { ChevronRight, PanelLeft } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { GuardedLink } from '@/components/layout/GuardedLink';
import { useNav } from '@/components/layout/nav-context';
import { QuickBar } from '@/components/layout/QuickBar';
import { buildBreadcrumbs } from '@/lib/breadcrumbs';
import { tenantNav } from '@/lib/nav-config';
import { cn } from '@/lib/utils';

type BreadcrumbsProps = {
  /** Shows the sidebar toggle at the left of the strip. */
  showSidebarToggle?: boolean;
  sidebarOpen?: boolean;
  onToggleSidebar?: () => void;
};

/** `Module › Page › Record`, directly under the top navigation; screen search and quick buttons at the right. */
export function Breadcrumbs({ showSidebarToggle, sidebarOpen, onToggleSidebar }: BreadcrumbsProps) {
  const pathname = usePathname();
  const { record } = useNav();
  const crumbs = buildBreadcrumbs(pathname, tenantNav, record);

  return (
    <div className="flex h-[42px] shrink-0 items-center gap-2 border-b border-border bg-muted/30 px-3 text-xs sm:px-4">
      {showSidebarToggle && (
        <Button
          type="button"
          variant="ghost"
          size="icon"
          className="h-8 w-8 shrink-0 text-muted-foreground hover:text-foreground"
          onClick={onToggleSidebar}
          aria-label={sidebarOpen ? 'Hide sidebar' : 'Show sidebar'}
          aria-expanded={!!sidebarOpen}
          aria-controls="context-sidebar"
        >
          <PanelLeft className="h-5 w-5" />
        </Button>
      )}

      <nav aria-label="Breadcrumb" className="min-w-0">
        <ol className="flex min-w-0 items-center gap-1.5 text-muted-foreground">
          {crumbs.map((crumb, i) => {
            const isLast = i === crumbs.length - 1;
            return (
              <Fragment key={`${i}-${crumb.label}`}>
                {i > 0 && (
                  <li aria-hidden="true" className={cn('shrink-0', crumbs.length > 2 && i === 1 && 'max-sm:hidden')}>
                    <ChevronRight className="h-3 w-3" />
                  </li>
                )}
                <li
                  className={cn(
                    'min-w-0 truncate',
                    // On phones keep only the last two crumbs.
                    crumbs.length > 2 && i === 0 && 'max-sm:hidden',
                    isLast && 'font-medium text-foreground',
                  )}
                  aria-current={isLast ? 'page' : undefined}
                >
                  {crumb.href && !isLast ? (
                    <GuardedLink href={crumb.href} className="hover:text-foreground hover:underline">
                      {crumb.label}
                    </GuardedLink>
                  ) : (
                    crumb.label
                  )}
                </li>
              </Fragment>
            );
          })}
        </ol>
      </nav>

      <QuickBar />
    </div>
  );
}
