'use client';

import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';
import { usePathname } from 'next/navigation';
import { findActiveHref, tenantNav } from '@/lib/nav-config';
import type { CurrentRecord } from '@/lib/nav-records';

type TouchPayload = { action_key?: string; record?: CurrentRecord };

type NavContextValue = {
  /** Set by the staff shell; null/undefined disables the sidebar features. */
  tenantId: number | null;
  /** Areas the user may read (null = unknown, show everything). */
  areas: string[] | null;
  /** The record the current page is showing (feeds the breadcrumb). */
  record: CurrentRecord | null;
  setRecord: (record: CurrentRecord | null) => void;
  /** Bumped after tracking calls succeed so the sidebar can refresh. */
  version: number;
  /** Fire-and-forget usage tracking (never blocks or throws). */
  touch: (payload: TouchPayload) => void;
  /** Pages register an "is dirty?" check so navigation can warn before discarding changes. */
  registerGuard: (isDirty: () => boolean) => () => void;
  /** true = OK to leave (nothing dirty, or the user agreed to discard). */
  confirmLeave: () => boolean;
  /** The Quick Buttons dialog (opened from the avatar menu, shown by the breadcrumb bar). */
  quickButtonsOpen: boolean;
  setQuickButtonsOpen: (open: boolean) => void;
  /** Where a page may render its own sidebar content (null when the sidebar is not docked and open). */
  sidebarSlot: HTMLElement | null;
  setSidebarSlot: (el: HTMLElement | null) => void;
};

const noop = () => {};
const defaultValue: NavContextValue = {
  tenantId: null,
  areas: null,
  record: null,
  setRecord: noop,
  version: 0,
  touch: noop,
  registerGuard: () => noop,
  confirmLeave: () => true,
  quickButtonsOpen: false,
  setQuickButtonsOpen: noop,
  sidebarSlot: null,
  setSidebarSlot: noop,
};

const NavContext = createContext<NavContextValue>(defaultValue);

export const LEAVE_MESSAGE = 'You have unsaved changes. Leave this page without saving?';

export function NavProvider({ tenantId, areas = null, children }: { tenantId: number | null; areas?: string[] | null; children: React.ReactNode }) {
  const [record, setRecord] = useState<CurrentRecord | null>(null);
  const [version, setVersion] = useState(0);
  const [quickButtonsOpen, setQuickButtonsOpen] = useState(false);
  const [sidebarSlot, setSidebarSlot] = useState<HTMLElement | null>(null);
  const guards = useRef(new Set<() => boolean>());
  const tenantRef = useRef(tenantId);
  tenantRef.current = tenantId;
  const bumpTimer = useRef<ReturnType<typeof setTimeout>>();

  const touch = useCallback((payload: TouchPayload) => {
    const tid = tenantRef.current;
    if (!tid || (!payload.action_key && !payload.record)) return;
    try {
      void fetch('/api/nav/touch', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'same-origin',
        keepalive: true,
        body: JSON.stringify({ tenant_id: tid, ...payload }),
      })
        .then((res) => {
          if (!res.ok) return;
          clearTimeout(bumpTimer.current);
          bumpTimer.current = setTimeout(() => setVersion((v) => v + 1), 400);
        })
        .catch(noop);
    } catch {
      /* tracking must never affect the page */
    }
  }, []);

  const registerGuard = useCallback((isDirty: () => boolean) => {
    guards.current.add(isDirty);
    return () => {
      guards.current.delete(isDirty);
    };
  }, []);

  const anyDirty = useCallback(() => {
    let dirty = false;
    guards.current.forEach((g) => {
      try {
        if (g()) dirty = true;
      } catch {
        /* a broken guard must not block navigation */
      }
    });
    return dirty;
  }, []);

  const confirmLeave = useCallback(() => !anyDirty() || window.confirm(LEAVE_MESSAGE), [anyDirty]);

  // Closing the tab / reloading with unsaved changes.
  useEffect(() => {
    const onBeforeUnload = (e: BeforeUnloadEvent) => {
      if (!anyDirty()) return;
      e.preventDefault();
      e.returnValue = '';
    };
    window.addEventListener('beforeunload', onBeforeUnload);
    return () => window.removeEventListener('beforeunload', onBeforeUnload);
  }, [anyDirty]);

  const value = useMemo<NavContextValue>(
    () => ({ tenantId, areas, record, setRecord, version, touch, registerGuard, confirmLeave, quickButtonsOpen, setQuickButtonsOpen, sidebarSlot, setSidebarSlot }),
    [tenantId, areas, record, version, touch, registerGuard, confirmLeave, quickButtonsOpen, sidebarSlot],
  );

  return (
    <NavContext.Provider value={value}>
      <ActionTracker />
      {children}
    </NavContext.Provider>
  );
}

export function useNav() {
  return useContext(NavContext);
}

/** Counts a visit to each built menu entry (menu clicks, bookmarks and the back button alike). */
function ActionTracker() {
  const pathname = usePathname();
  const { tenantId, touch } = useNav();
  const last = useRef<string | null>(null);

  useEffect(() => {
    if (!tenantId) return;
    const href = findActiveHref(pathname, tenantNav);
    if (!href || href === last.current) return;
    last.current = href;
    touch({ action_key: href });
  }, [pathname, tenantId, touch]);

  return null;
}

/** Shows `record` in the breadcrumb while the page is mounted. */
export function useBreadcrumbRecord(record: CurrentRecord | null) {
  const { setRecord } = useNav();
  const type = record?.type;
  const key = record?.key;
  const label = record?.label;
  const sublabel = record?.sublabel;

  useEffect(() => {
    setRecord(type && key && label ? { type, key, label, sublabel } : null);
    return () => setRecord(null);
  }, [type, key, label, sublabel, setRecord]);
}

/** Adds `record` to the user's recent records (debounced, once per distinct record per mount). */
export function useTrackRecent(record: CurrentRecord | null) {
  const { touch } = useNav();
  const type = record?.type;
  const key = record?.key;
  const label = record?.label;
  const sublabel = record?.sublabel;

  useEffect(() => {
    if (!type || !key || !label) return;
    const t = setTimeout(() => touch({ record: { type, key, label, sublabel } }), 600);
    return () => clearTimeout(t);
  }, [type, key, label, sublabel, touch]);
}

/** Breadcrumb + recents in one call, for pages with a single "current record". */
export function useCurrentRecord(record: CurrentRecord | null) {
  useBreadcrumbRecord(record);
  useTrackRecent(record);
}

/** Registers an unsaved-changes check while the page is mounted. */
export function useNavGuard(isDirty: boolean) {
  const { registerGuard } = useNav();
  const ref = useRef(isDirty);
  ref.current = isDirty;
  useEffect(() => registerGuard(() => ref.current), [registerGuard]);
}
