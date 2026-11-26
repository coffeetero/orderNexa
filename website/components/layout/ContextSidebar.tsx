'use client';

import { useEffect, useState } from 'react';
import { usePathname, useSearchParams } from 'next/navigation';
import { GuardedLink } from '@/components/layout/GuardedLink';
import { useNav } from '@/components/layout/nav-context';
import { findActiveHref, findActiveMenu, tenantNav } from '@/lib/nav-config';
import { recentListsFor, recordHref, type RecentRow } from '@/lib/nav-records';
import { cn } from '@/lib/utils';

type SidebarData = { recents: RecentRow[] };

const rowClass =
  'flex h-6 w-full items-center gap-2 rounded-md px-2 text-left text-sm text-foreground/80 outline-none ' +
  'transition-colors hover:bg-muted hover:text-foreground focus-visible:ring-2 focus-visible:ring-ring';

function SectionTitle({ children, action }: { children: React.ReactNode; action?: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between px-2 pb-1">
      <h2 className="text-[13.5px] font-bold uppercase tracking-wider text-muted-foreground">{children}</h2>
      {action}
    </div>
  );
}

/**
 * The page's own sidebar: recent records chosen per page (see PAGE_RECENTS), and the Admin sections.
 * Content comes from /api/nav/sidebar; it never blocks the page it sits beside.
 */
export function ContextSidebar({ onNavigate }: { onNavigate?: () => void }) {
  const pathname = usePathname();
  const { tenantId, version, areas } = useNav();
  const searchParams = useSearchParams();
  const adminMenu = tenantNav.find((m) => m.label === 'Admin');
  const [data, setData] = useState<SidebarData | null>(null);
  const [failed, setFailed] = useState(false);

  const moduleLabel = findActiveMenu(pathname, tenantNav)?.label ?? null;
  const activeHref = findActiveHref(pathname, tenantNav);

  useEffect(() => {
    if (!tenantId) return;
    const ac = new AbortController();
    fetch(`/api/nav/sidebar?tenant_id=${tenantId}&module=${encodeURIComponent(moduleLabel ?? '')}&page=${encodeURIComponent(activeHref ?? '')}`, {
      credentials: 'same-origin',
      signal: ac.signal,
    })
      .then((res) => (res.ok ? res.json() : Promise.reject(new Error('bad status'))))
      .then((json: { data?: SidebarData }) => {
        if (json.data) {
          setData(json.data);
          setFailed(false);
        }
      })
      .catch((err: Error) => {
        if (err.name !== 'AbortError') setFailed(true);
      });
    return () => ac.abort();
  }, [tenantId, moduleLabel, activeHref, version]);

  if (!tenantId) return null;

  const recentLists = recentListsFor(activeHref, moduleLabel);

  const currentSection = searchParams.get('section');
  const adminGroups = moduleLabel === 'Admin' && adminMenu
    ? (adminMenu.groups ?? [])
        .map((g) => ({ ...g, items: g.items.filter((i) => !i.area || areas === null || areas.includes(i.area)) }))
        .filter((g) => g.items.length > 0)
    : [];

  return (
    <div className="flex h-full flex-col gap-5 px-2 py-3" data-testid="context-sidebar">
      {adminGroups.length > 0 && (
        <nav aria-label="Admin sections" data-testid="admin-sections" className="space-y-3 border-t border-border pt-4">
          {adminGroups.map((g) => (
            <section key={g.heading}>
              <SectionTitle>{g.heading}</SectionTitle>
              <ul className="space-y-0">
                {g.items.flatMap((item) => {
                  if (item.sections) {
                    // The group is the page: each section is its own entry.
                    const onPage = item.href === activeHref;
                    return item.sections.map((sec, idx) => {
                      const on = onPage && (currentSection ?? item.sections![0].key) === sec.key;
                      return (
                        <li key={`${item.href}-${sec.key}`}>
                          <GuardedLink
                            href={idx === 0 ? item.href : `${item.href}?section=${sec.key}`}
                            onClick={onNavigate}
                            aria-current={on ? 'page' : undefined}
                            className={cn(rowClass, on && 'bg-accent font-medium text-accent-foreground')}
                          >
                            <span className="min-w-0 flex-1 truncate">{sec.label}</span>
                          </GuardedLink>
                        </li>
                      );
                    });
                  }
                  const isActive = item.href === activeHref;
                  if (item.soon) {
                    return [(
                      <li key={item.href}>
                        <span aria-disabled="true" className={cn(rowClass, 'cursor-default text-muted-foreground hover:bg-transparent hover:text-muted-foreground')}>
                          <span className="min-w-0 flex-1 truncate">{item.label}</span>
                          <span className="shrink-0 text-[10px] uppercase tracking-wide">Soon</span>
                        </span>
                      </li>
                    )];
                  }
                  return [(
                    <li key={item.href}>
                      <GuardedLink
                        href={item.href}
                        onClick={onNavigate}
                        aria-current={isActive ? 'page' : undefined}
                        className={cn(rowClass, isActive && 'bg-accent font-medium text-accent-foreground')}
                      >
                        <span className="min-w-0 flex-1 truncate">{item.label}</span>
                      </GuardedLink>
                    </li>
                  )];
                })}
              </ul>
            </section>
          ))}
        </nav>
      )}
      {recentLists.map(({ type, title }) => {
        const rows = (data?.recents ?? []).filter((r) => r.record_type === type);
        return (
          <section key={type} aria-label={title}>
            <SectionTitle>{title}</SectionTitle>
            {!data ? (
              <div aria-hidden="true" className="h-6 animate-pulse rounded-md bg-muted/60" />
            ) : rows.length === 0 ? (
              <p className="px-2 text-xs text-muted-foreground">
                {type === 'production_run'
                  ? 'Recent runs appear here once Production pages exist.'
                  : 'Nothing yet. Records you open show up here.'}
              </p>
            ) : (
              <ul className="space-y-0">
                {rows.map((row) => {
                  const href = recordHref(row.record_type, row.record_key, moduleLabel);
                  return (
                    <li key={`${row.record_type}-${row.record_key}`}>
                      {href ? (
                        <GuardedLink href={href} onClick={onNavigate} title={row.label} className={rowClass}>
                          <span className="min-w-0 flex-1 truncate">{row.label}</span>
                        </GuardedLink>
                      ) : (
                        <span className={cn(rowClass, 'cursor-default hover:bg-transparent')} title={row.label}>
                          <span className="min-w-0 flex-1 truncate">{row.label}</span>
                        </span>
                      )}
                    </li>
                  );
                })}
              </ul>
            )}
          </section>
        );
      })}
      {failed && <p className="px-2 text-xs text-muted-foreground">Couldn&apos;t refresh. Showing the last list.</p>}
    </div>
  );
}
