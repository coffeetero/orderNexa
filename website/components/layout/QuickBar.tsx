'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import {
  Banknote, Building2, CalendarDays, ClipboardList, Factory, FileText, LayoutDashboard, type LucideIcon,
  Package, Pencil, Search, Settings, Truck, Users, Wallet,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { GuardedLink } from '@/components/layout/GuardedLink';
import { useNav } from '@/components/layout/nav-context';
import { tenantNav, visibleMenus, type BuiltAction } from '@/lib/nav-config';
import { DEFAULT_QUICK_BUTTONS, QUICK_ACCESS_SLOTS, selectQuickButtons } from '@/lib/quick-access';
import { cn } from '@/lib/utils';

const HREF_ICONS: Record<string, LucideIcon> = {
  '/orders': ClipboardList,
  '/financials/enter-payments': Banknote,
  '/customers': Users,
  '/inventory/item-profile': Package,
  '/dashboard': LayoutDashboard,
};
const MODULE_ICONS: Record<string, LucideIcon> = {
  Operations: Factory,
  Customers: Building2,
  Inventory: Package,
  Financials: Wallet,
  Organizer: CalendarDays,
  Admin: Settings,
};
function iconFor(a: BuiltAction): LucideIcon {
  if (a.href.startsWith('/delivery')) return Truck;
  return HREF_ICONS[a.href] ?? MODULE_ICONS[a.module] ?? FileText;
}

/** Screen search and the user's 4 quick buttons, at the right end of the breadcrumb bar. */
export function QuickBar() {
  const { tenantId, areas, version } = useNav();
  const [pinned, setPinned] = useState<string[] | null>(null);

  // Screens this user may open (built, menu visible, area readable).
  const actions = useMemo<BuiltAction[]>(
    () =>
      visibleMenus(tenantNav, areas).flatMap((m) =>
        m.href
          ? [{ href: m.href, label: m.label, module: m.label }]
          : (m.groups ?? []).flatMap((g) =>
              g.items
                .filter((i) => !i.soon && (!i.requires || i.requires.includes('TENANCY_USER')) && (!i.area || areas === null || areas.includes(i.area)))
                .map((i) => ({ href: i.href, label: i.label, module: m.label })),
            ),
      ),
    [areas],
  );
  const byHref = useMemo(() => new Map(actions.map((a) => [a.href, a])), [actions]);

  useEffect(() => {
    if (!tenantId) return;
    const ac = new AbortController();
    fetch(`/api/nav/sidebar?tenant_id=${tenantId}&module=`, { credentials: 'same-origin', signal: ac.signal })
      .then((res) => (res.ok ? res.json() : Promise.reject(new Error('bad status'))))
      .then((json: { data?: { pinned: string[] } }) => setPinned(json.data?.pinned ?? []))
      .catch((err: Error) => {
        if (err.name !== 'AbortError') setPinned([]);
      });
    return () => ac.abort();
  }, [tenantId, version]);

  const buttons = selectQuickButtons(pinned ?? [], actions);

  const save = useCallback(async (keys: string[]) => {
    setPinned(keys);
    await fetch('/api/nav/pins', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      credentials: 'same-origin',
      body: JSON.stringify({ action_keys: keys }),
    }).catch(() => undefined);
  }, []);

  if (!tenantId) return null;

  return (
    <div className="ml-auto flex shrink-0 items-center gap-1">
      <ScreenSearch actions={actions} />
      <div className="flex items-center" role="group" aria-label="Quick buttons">
        {pinned !== null &&
          buttons.map((href) => {
            const a = byHref.get(href)!;
            const Icon = iconFor(a);
            return (
              <Button key={href} asChild variant="ghost" size="icon" className="h-8 w-8 text-muted-foreground hover:text-foreground">
                <GuardedLink href={href} aria-label={a.label} title={a.label}>
                  <Icon className="h-5 w-5" />
                </GuardedLink>
              </Button>
            );
          })}
        {pinned !== null && <ButtonsEditor buttons={buttons} actions={actions} onSave={save} />}
      </div>
    </div>
  );
}

/** Assign a screen to each of the 4 buttons. Saved as the user's pins (shared with sidebar Quick access). */
function ButtonsEditor({ buttons, actions, onSave }: { buttons: string[]; actions: BuiltAction[]; onSave: (keys: string[]) => void }) {
  const [open, setOpen] = useState(false);
  const [draft, setDraft] = useState<string[]>(buttons);
  const modules = useMemo(() => Array.from(new Set(actions.map((a) => a.module))), [actions]);

  return (
    <Popover
      open={open}
      onOpenChange={(o) => {
        setOpen(o);
        if (o) setDraft(buttons);
      }}
    >
      <PopoverTrigger asChild>
        <Button variant="ghost" size="icon" className="h-8 w-8 text-muted-foreground hover:text-foreground" aria-label="Choose quick buttons" title="Choose quick buttons">
          <Pencil className="h-4 w-4" />
        </Button>
      </PopoverTrigger>
      <PopoverContent align="end" className="w-72 space-y-2 p-3 text-sm">
        <p className="text-xs font-medium text-muted-foreground">Quick buttons</p>
        {Array.from({ length: QUICK_ACCESS_SLOTS }, (_, i) => (
          <label key={i} className="flex items-center gap-2">
            <span className="w-4 text-xs text-muted-foreground">{i + 1}</span>
            <select
              className="h-8 flex-1 rounded-md border border-input bg-background px-2 text-sm"
              value={draft[i] ?? ''}
              onChange={(e) => setDraft((d) => {
                const next = [...d];
                next[i] = e.target.value;
                return next;
              })}
            >
              {modules.map((m) => (
                <optgroup key={m} label={m}>
                  {actions.filter((a) => a.module === m).map((a) => (
                    <option key={a.href} value={a.href}>{a.label}</option>
                  ))}
                </optgroup>
              ))}
            </select>
          </label>
        ))}
        <div className="flex items-center justify-between pt-1">
          <Button type="button" variant="ghost" size="sm" onClick={() => setDraft(DEFAULT_QUICK_BUTTONS)}>Defaults</Button>
          <div className="flex gap-2">
            <Button type="button" variant="outline" size="sm" onClick={() => setOpen(false)}>Cancel</Button>
            <Button
              type="button"
              size="sm"
              onClick={() => {
                onSave(draft.filter((h, i) => h && draft.indexOf(h) === i));
                setOpen(false);
              }}
            >
              Save
            </Button>
          </div>
        </div>
      </PopoverContent>
    </Popover>
  );
}

/** Find a screen by name; Ctrl+K / ⌘K focuses it. */
function ScreenSearch({ actions }: { actions: BuiltAction[] }) {
  const router = useRouter();
  const { confirmLeave } = useNav();
  const inputRef = useRef<HTMLInputElement>(null);
  const [q, setQ] = useState('');
  const [active, setActive] = useState(0);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        inputRef.current?.focus();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  const term = q.trim().toLowerCase();
  const matches = term
    ? actions.filter((a) => `${a.label} ${a.module}`.toLowerCase().includes(term)).slice(0, 8)
    : [];

  const go = (a: BuiltAction) => {
    if (!confirmLeave()) return;
    setQ('');
    setOpen(false);
    inputRef.current?.blur();
    router.push(a.href);
  };

  return (
    <div className="relative hidden sm:block">
      <Search className="pointer-events-none absolute left-2 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
      <input
        ref={inputRef}
        type="search"
        role="combobox"
        aria-expanded={open && matches.length > 0}
        aria-controls="screen-search-list"
        aria-label="Search screens"
        placeholder="Search screens  (Ctrl+K)"
        value={q}
        onChange={(e) => {
          setQ(e.target.value);
          setActive(0);
          setOpen(true);
        }}
        onFocus={() => setOpen(true)}
        onBlur={() => setTimeout(() => setOpen(false), 150)}
        onKeyDown={(e) => {
          if (e.key === 'ArrowDown') { e.preventDefault(); setActive((i) => Math.min(i + 1, matches.length - 1)); }
          else if (e.key === 'ArrowUp') { e.preventDefault(); setActive((i) => Math.max(i - 1, 0)); }
          else if (e.key === 'Enter' && matches[active]) { e.preventDefault(); go(matches[active]); }
          else if (e.key === 'Escape') { setQ(''); inputRef.current?.blur(); }
        }}
        className="h-8 w-60 text-sm rounded-md border border-input bg-background pl-7 pr-2 placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-ring"
      />
      {open && matches.length > 0 && (
        <ul id="screen-search-list" role="listbox" className="absolute right-0 z-50 mt-1 w-72 overflow-hidden rounded-md border border-border bg-popover py-1 text-sm text-popover-foreground shadow-md">
          {matches.map((a, i) => (
            <li
              key={a.href}
              role="option"
              aria-selected={i === active}
              onMouseDown={(e) => { e.preventDefault(); go(a); }}
              onMouseEnter={() => setActive(i)}
              className={cn('flex cursor-pointer items-center justify-between gap-3 px-3 py-1.5', i === active && 'bg-accent text-accent-foreground')}
            >
              <span className="truncate">{a.label}</span>
              <span className="shrink-0 text-xs text-muted-foreground">{a.module}</span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
