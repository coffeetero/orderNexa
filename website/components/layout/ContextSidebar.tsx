'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { usePathname } from 'next/navigation';
import { ArrowDown, ArrowUp, Pencil, Pin, PinOff, Plus } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { GuardedLink } from '@/components/layout/GuardedLink';
import { useNav } from '@/components/layout/nav-context';
import { builtActions, findActiveHref, findActiveMenu, tenantNav } from '@/lib/nav-config';
import { MODULE_RECENTS, recordHref, type RecentRow } from '@/lib/nav-records';
import { QUICK_ACCESS_SLOTS } from '@/lib/quick-access';
import { cn } from '@/lib/utils';

type SidebarData = { quickAccess: string[]; pinned: string[]; recents: RecentRow[] };

const rowClass =
  'flex h-8 w-full items-center gap-2 rounded-md px-2 text-left text-sm text-foreground/80 outline-none ' +
  'transition-colors hover:bg-muted hover:text-foreground focus-visible:ring-2 focus-visible:ring-ring';

function SectionTitle({ children, action }: { children: React.ReactNode; action?: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between px-2 pb-1">
      <h2 className="text-[11px] font-semibold uppercase tracking-wider text-muted-foreground">{children}</h2>
      {action}
    </div>
  );
}

/**
 * Quick Access (the user's 3 most useful actions) + recent records for the current module.
 * Content comes from /api/nav/sidebar; it never blocks the page it sits beside.
 */
export function ContextSidebar({ onNavigate }: { onNavigate?: () => void }) {
  const pathname = usePathname();
  const { tenantId, version } = useNav();
  const [data, setData] = useState<SidebarData | null>(null);
  const [failed, setFailed] = useState(false);
  const [reloadKey, setReloadKey] = useState(0);

  const moduleLabel = findActiveMenu(pathname, tenantNav)?.label ?? null;
  const activeHref = findActiveHref(pathname, tenantNav);
  const actions = useMemo(() => builtActions(tenantNav), []);
  const byHref = useMemo(() => new Map(actions.map((a) => [a.href, a])), [actions]);

  useEffect(() => {
    if (!tenantId) return;
    const ac = new AbortController();
    fetch(`/api/nav/sidebar?tenant_id=${tenantId}&module=${encodeURIComponent(moduleLabel ?? '')}`, {
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
  }, [tenantId, moduleLabel, version, reloadKey]);

  const savePins = useCallback(
    async (keys: string[]) => {
      setData((prev) => (prev ? { ...prev, pinned: keys } : prev)); // optimistic
      try {
        const res = await fetch('/api/nav/pins', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          credentials: 'same-origin',
          body: JSON.stringify({ action_keys: keys }),
        });
        if (!res.ok) throw new Error('save failed');
      } catch {
        setFailed(true);
      } finally {
        setReloadKey((k) => k + 1);
      }
    },
    [],
  );

  if (!tenantId) return null;

  const recentLists = moduleLabel ? MODULE_RECENTS[moduleLabel] ?? [] : [];

  return (
    <div className="flex h-full flex-col gap-5 px-2 py-3" data-testid="context-sidebar">
      <section aria-labelledby="qa-title">
        <SectionTitle
          action={
            data ? (
              <QuickAccessEditor
                pinned={data.pinned}
                actions={actions}
                onChange={savePins}
              />
            ) : null
          }
        >
          <span id="qa-title">Quick access</span>
        </SectionTitle>
        <ul className="space-y-0.5">
          {data
            ? data.quickAccess.map((href) => {
                const action = byHref.get(href);
                if (!action) return null;
                const isPinned = data.pinned.includes(href);
                return (
                  <li key={href}>
                    <GuardedLink
                      href={href}
                      onClick={onNavigate}
                      title={action.module}
                      aria-current={href === activeHref ? 'page' : undefined}
                      className={cn(rowClass, href === activeHref && 'bg-accent font-medium text-accent-foreground')}
                    >
                      <span className="min-w-0 flex-1 truncate">{action.label}</span>
                      {isPinned && <Pin className="h-3 w-3 shrink-0 text-muted-foreground" aria-label="Pinned" />}
                    </GuardedLink>
                  </li>
                );
              })
            : [0, 1, 2].map((i) => (
                <li key={i} aria-hidden="true" className="h-8 animate-pulse rounded-md bg-muted/60" />
              ))}
        </ul>
        {failed && <p className="px-2 pt-1 text-xs text-muted-foreground">Couldn&apos;t refresh. Showing the last list.</p>}
      </section>

      {recentLists.map(({ type, title }) => {
        const rows = (data?.recents ?? []).filter((r) => r.record_type === type);
        return (
          <section key={type} aria-label={title}>
            <SectionTitle>{title}</SectionTitle>
            {!data ? (
              <div aria-hidden="true" className="h-8 animate-pulse rounded-md bg-muted/60" />
            ) : rows.length === 0 ? (
              <p className="px-2 text-xs text-muted-foreground">
                {type === 'production_run'
                  ? 'Recent runs appear here once Production pages exist.'
                  : 'Nothing yet. Records you open show up here.'}
              </p>
            ) : (
              <ul className="space-y-0.5">
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
    </div>
  );
}

/** Pin, unpin and reorder Quick Access (up to 3). Keyboard accessible: plain buttons, no drag-only controls. */
function QuickAccessEditor({
  pinned,
  actions,
  onChange,
}: {
  pinned: string[];
  actions: { href: string; label: string; module: string }[];
  onChange: (keys: string[]) => void;
}) {
  const label = (href: string) => actions.find((a) => a.href === href)?.label ?? href;
  const available = actions.filter((a) => !pinned.includes(a.href));
  const full = pinned.length >= QUICK_ACCESS_SLOTS;

  const move = (i: number, dir: -1 | 1) => {
    const next = [...pinned];
    const j = i + dir;
    if (j < 0 || j >= next.length) return;
    [next[i], next[j]] = [next[j], next[i]];
    onChange(next);
  };

  return (
    <Popover>
      <PopoverTrigger asChild>
        <Button type="button" variant="ghost" size="icon" className="h-6 w-6 text-muted-foreground" aria-label="Customize quick access">
          <Pencil className="h-3.5 w-3.5" />
        </Button>
      </PopoverTrigger>
      <PopoverContent align="start" className="w-72 p-3">
        <p className="text-sm font-medium">Pinned actions</p>
        <p className="mb-2 text-xs text-muted-foreground">
          Pin up to {QUICK_ACCESS_SLOTS}. Open slots fill with the ones you use most.
        </p>

        {pinned.length === 0 ? (
          <p className="mb-2 text-xs text-muted-foreground">Nothing pinned yet.</p>
        ) : (
          <ul className="mb-3 space-y-1">
            {pinned.map((href, i) => (
              <li key={href} className="flex items-center gap-1 rounded-md border border-border px-2 py-1 text-sm">
                <span className="min-w-0 flex-1 truncate">{label(href)}</span>
                <Button type="button" variant="ghost" size="icon" className="h-6 w-6" disabled={i === 0} onClick={() => move(i, -1)} aria-label={`Move ${label(href)} up`}>
                  <ArrowUp className="h-3.5 w-3.5" />
                </Button>
                <Button type="button" variant="ghost" size="icon" className="h-6 w-6" disabled={i === pinned.length - 1} onClick={() => move(i, 1)} aria-label={`Move ${label(href)} down`}>
                  <ArrowDown className="h-3.5 w-3.5" />
                </Button>
                <Button type="button" variant="ghost" size="icon" className="h-6 w-6" onClick={() => onChange(pinned.filter((p) => p !== href))} aria-label={`Unpin ${label(href)}`}>
                  <PinOff className="h-3.5 w-3.5" />
                </Button>
              </li>
            ))}
          </ul>
        )}

        <p className="mb-1 text-xs font-medium text-muted-foreground">{full ? 'Unpin one to add another' : 'Add to quick access'}</p>
        <ul className="max-h-48 space-y-0.5 overflow-y-auto">
          {available.map((a) => (
            <li key={a.href}>
              <button
                type="button"
                disabled={full}
                onClick={() => onChange([...pinned, a.href])}
                className="flex h-8 w-full items-center gap-2 rounded-md px-2 text-left text-sm hover:bg-muted disabled:opacity-50 disabled:hover:bg-transparent"
                aria-label={`Pin ${a.label}`}
              >
                <Plus className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
                <span className="min-w-0 flex-1 truncate">{a.label}</span>
                <span className="shrink-0 text-[11px] text-muted-foreground">{a.module}</span>
              </button>
            </li>
          ))}
        </ul>
      </PopoverContent>
    </Popover>
  );
}
