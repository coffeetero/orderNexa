'use client';

import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';
import { usePathname } from 'next/navigation';
import { findActiveHref, tenantNav } from '@/lib/nav-config';
import {
  AlertDialog, AlertDialogCancel, AlertDialogContent, AlertDialogDescription,
  AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import { Button } from '@/components/ui/button';
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
  registerGuard: (isDirty: () => boolean, save?: () => Promise<boolean>) => () => void;
  /**
   * true = nothing unsaved, go ahead. false = there are unsaved changes: the "Unsaved changes" dialog opens
   * (Cancel / Leave without saving / Save when the page can save) and runs onLeave if the user leaves.
   */
  confirmLeave: (onLeave?: () => void) => boolean;
  /** The Quick Buttons dialog (opened from the avatar menu, shown by the breadcrumb bar). */
  quickButtonsOpen: boolean;
  setQuickButtonsOpen: (open: boolean) => void;
  /** The screens on the user's quick buttons, in order (Alt+Shift+1..4); the menu shows their keys. */
  quickHrefs: string[];
  setQuickHrefs: (hrefs: string[]) => void;
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
  quickHrefs: [],
  setQuickHrefs: noop,
  sidebarSlot: null,
  setSidebarSlot: noop,
};

const NavContext = createContext<NavContextValue>(defaultValue);

export const LEAVE_MESSAGE = 'You have unsaved changes. Leave this page without saving?';

export function NavProvider({ tenantId, areas = null, children }: { tenantId: number | null; areas?: string[] | null; children: React.ReactNode }) {
  const [record, setRecord] = useState<CurrentRecord | null>(null);
  const [version, setVersion] = useState(0);
  const [quickButtonsOpen, setQuickButtonsOpen] = useState(false);
  const [quickHrefs, setQuickHrefs] = useState<string[]>([]);
  const [sidebarSlot, setSidebarSlot] = useState<HTMLElement | null>(null);
  type Guard = { isDirty: () => boolean; save?: () => Promise<boolean> };
  const guards = useRef(new Set<Guard>());
  const [leaveOpen, setLeaveOpen] = useState(false);
  const [leaveCanSave, setLeaveCanSave] = useState(false);
  const [leaveSaving, setLeaveSaving] = useState(false);
  const pendingLeave = useRef<(() => void) | null>(null);
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

  const registerGuard = useCallback((isDirty: () => boolean, save?: () => Promise<boolean>) => {
    const guard: Guard = { isDirty, save };
    guards.current.add(guard);
    return () => {
      guards.current.delete(guard);
    };
  }, []);

  const dirtyGuards = useCallback(() => {
    const out: Guard[] = [];
    guards.current.forEach((g) => {
      try {
        if (g.isDirty()) out.push(g);
      } catch {
        /* a broken guard must not block navigation */
      }
    });
    return out;
  }, []);
  const anyDirty = useCallback(() => dirtyGuards().length > 0, [dirtyGuards]);

  const confirmLeave = useCallback((onLeave?: () => void) => {
    const dirty = dirtyGuards();
    if (dirty.length === 0) return true;
    pendingLeave.current = onLeave ?? null;
    setLeaveCanSave(dirty.every((g) => g.save));
    setLeaveOpen(true);
    return false;
  }, [dirtyGuards]);

  const leave = useCallback(() => {
    setLeaveOpen(false);
    const go = pendingLeave.current;
    pendingLeave.current = null;
    go?.();
  }, []);

  const saveAndLeave = useCallback(async () => {
    setLeaveSaving(true);
    try {
      for (const g of dirtyGuards()) {
        if (!g.save || !(await g.save())) { setLeaveOpen(false); return; } // the page shows why it could not save
      }
      leave();
    } finally {
      setLeaveSaving(false);
    }
  }, [dirtyGuards, leave]);

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
    () => ({ tenantId, areas, record, setRecord, version, touch, registerGuard, confirmLeave, quickButtonsOpen, setQuickButtonsOpen, quickHrefs, setQuickHrefs, sidebarSlot, setSidebarSlot }),
    [tenantId, areas, record, version, touch, registerGuard, confirmLeave, quickButtonsOpen, quickHrefs, sidebarSlot],
  );

  return (
    <NavContext.Provider value={value}>
      <ActionTracker />
      {children}
      <AlertDialog open={leaveOpen} onOpenChange={(open) => { if (!open && !leaveSaving) setLeaveOpen(false); }}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Unsaved changes</AlertDialogTitle>
            <AlertDialogDescription>
              {leaveCanSave ? 'Save your changes before leaving this page?' : LEAVE_MESSAGE}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={leaveSaving}>Cancel</AlertDialogCancel>
            <Button variant="outline" onClick={leave} disabled={leaveSaving}>Leave without saving</Button>
            {leaveCanSave && <Button onClick={() => void saveAndLeave()} disabled={leaveSaving}>{leaveSaving ? 'Saving…' : 'Save'}</Button>}
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
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
/** Registers the page's "has unsaved changes" state; with onSave the leave dialog also offers Save (true = saved). */
export function useNavGuard(isDirty: boolean, onSave?: () => Promise<boolean>) {
  const { registerGuard } = useNav();
  const ref = useRef(isDirty);
  ref.current = isDirty;
  const saveRef = useRef(onSave);
  saveRef.current = onSave;
  const canSave = Boolean(onSave);
  useEffect(
    () => registerGuard(() => ref.current, canSave ? () => saveRef.current?.() ?? Promise.resolve(false) : undefined),
    [registerGuard, canSave],
  );
}
