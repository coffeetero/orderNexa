'use client';

import { createContext, useContext, useEffect, useLayoutEffect, useState, useSyncExternalStore } from 'react';
import { applyToDocument, htmlMode, type ModeChoice } from '@/lib/theme/apply';
import {
  accountAppearance, defaultThemeOverride, deviceAppearance, resolveAppearance, themePreview, writeCookie,
  DEFAULT_APPEARANCE, DEFAULT_MODE, readAppearance, toLocal, readLocal, type AppearancePrefs, type LocalAppearance,
} from '@/lib/theme/prefs';
import { DEFAULT_THEME, variantOf, type ThemeDef, type ThemeMode } from '@/lib/theme/themes';

const AppearanceContext = createContext<{ last: LocalAppearance | null }>({ last: null });

const noop = () => {};
const sub = <T,>(s: { subscribe: (l: () => void) => () => void; get: () => T }, server: T) =>
  () => useSyncExternalStore(s.subscribe, s.get, () => server);
const usePreview = sub<ThemeDef | null>(themePreview, null);
const useDevice = sub<LocalAppearance | null>(deviceAppearance, null);
const useAccount = sub<AppearancePrefs | undefined>(accountAppearance, undefined);
const useOverride = sub<boolean>(defaultThemeOverride, false);

/** Follows the operating system's light/dark setting. */
export function useOsDark(): boolean {
  const [dark, setDark] = useState(false);
  useEffect(() => {
    let mq: MediaQueryList | undefined;
    try { mq = window.matchMedia('(prefers-color-scheme: dark)'); } catch { return; }
    setDark(mq.matches);
    const on = () => setDark(mq!.matches);
    mq.addEventListener('change', on);
    return () => mq!.removeEventListener('change', on);
  }, []);
  return dark;
}

export interface AppearanceState {
  /** The saved choice (no try-on): this device's override, else the account's, else the last one applied here. */
  current: LocalAppearance;
  /** What is on screen now (adds try-on and the portal override). */
  shown: LocalAppearance;
  /** The light/dark variant on screen. */
  mode: ThemeMode;
  account: AppearancePrefs | undefined;
  device: LocalAppearance | null;
  preview: ThemeDef | null;
  osDark: boolean;
}

export function useAppearanceState(): AppearanceState {
  const { last } = useContext(AppearanceContext);
  const preview = usePreview();
  const device = useDevice();
  const account = useAccount();
  const override = useOverride();
  const osDark = useOsDark();
  const current = resolveAppearance({ preview: null, device, account, last });
  let shown = resolveAppearance({ preview, device, account, last });
  if (override) shown = { mode: shown.mode, theme: DEFAULT_THEME };
  const h = htmlMode(shown.theme, shown.mode);
  const mode: ThemeMode = h === 'system' ? (osDark ? 'dark' : 'light') : h;
  return { current, shown, mode, account, device, preview, osDark };
}

/** Applies the theme in effect to the page and keeps the cookie (what the server paints first) in step. Mounted once, in the root layout. */
export function AppearanceProvider({ initial, children }: { initial: ReturnType<typeof toLocal> | null; children: React.ReactNode }) {
  const last = readLocal(initial);
  return (
    <AppearanceContext.Provider value={{ last }}>
      <Applier />
      {children}
    </AppearanceContext.Provider>
  );
}

function Applier() {
  const s = useAppearanceState();
  const override = useOverride();
  const key = JSON.stringify([s.shown, s.osDark]);
  const currentKey = JSON.stringify(s.current);
  useLayoutEffect(() => {
    applyToDocument(document, s.shown.theme, s.shown.mode, s.osDark);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key]);
  useEffect(() => {
    // Remember what the user chose (not a try-on, not the portal's forced default) for the server's first paint.
    if (!s.preview && !override) writeCookie(s.current);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [currentKey, s.preview, override]);
  return null;
}

/** Loads the signed-in staff user's saved appearance once (staff shell only). */
export function AccountAppearanceLoader() {
  useEffect(() => {
    let live = true;
    fetch('/api/preferences/appearance', { credentials: 'same-origin' })
      .then((r) => (r.ok ? r.json() : null))
      .then((j: { data?: unknown } | null) => {
        if (!live || !j) return;
        accountAppearance.set(j.data ? readAppearance(j.data) : { ...DEFAULT_APPEARANCE });
      })
      .catch(noop);
    return () => { live = false; };
  }, []);
  return null;
}

/** Keeps the default theme (Hearth) while mounted: the customer portal does not follow staff themes. */
export function ForceDefaultTheme() {
  useLayoutEffect(() => { defaultThemeOverride.set(true); return () => defaultThemeOverride.set(false); }, []);
  return null;
}

// ------------------------------------------------------------------ saving
export async function saveAccountAppearance(a: AppearancePrefs): Promise<{ ok: true } | { ok: false; error: string }> {
  try {
    const res = await fetch('/api/preferences/appearance', {
      method: 'POST', credentials: 'same-origin', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ appearance: a }),
    });
    const j = (await res.json().catch(() => ({}))) as { data?: unknown; error?: string };
    if (!res.ok) return { ok: false, error: j.error ?? 'Your appearance could not be saved. Try again.' };
    accountAppearance.set(readAppearance(j.data));
    return { ok: true };
  } catch {
    return { ok: false, error: 'Your appearance could not be saved. Check your connection and try again.' };
  }
}

/** Saves a mode + theme choice: on this device when "this device only" is on or there is no account to save to, else with the account. */
export async function chooseAppearance(next: LocalAppearance, s: Pick<AppearanceState, 'device' | 'account'>): Promise<boolean> {
  if (s.device || !s.account) { deviceAppearance.write(next); return true; }
  const r = await saveAccountAppearance({ ...s.account, mode: next.mode, themeId: next.theme.id });
  return r.ok;
}

export const nextQuickMode = (mode: ThemeMode): ModeChoice => (mode === 'dark' ? 'light' : 'dark');
export { DEFAULT_MODE, variantOf };
