/**
 * Appearance choices: Light / Dark / Follow system, the selected theme and the user's own themes.
 *
 * - With the account: `fnd_user_preferences.appearance` (jsonb), through /api/preferences/appearance, so every device gets them.
 * - "This device only": an override in localStorage (mode + theme; the theme's colours are included when it is one of the user's own).
 * - The cookie `bps_appearance` holds what is APPLIED on this device (account choice or device override), so the server can render the first
 *   paint in the right colours. Colours only; nothing sensitive.
 * - Try-on: a theme shown for a moment from Admin › Appearance. Memory only.
 * Storage access is wrapped in try/catch: a private window or blocked storage falls back to the defaults.
 */
import { isModeChoice, type ModeChoice } from './apply';
import { CUSTOM_LIMIT, DEFAULT_THEME, findTheme, isBuiltinId, readTheme, type ThemeDef } from './themes';

export interface AppearancePrefs { mode: ModeChoice; themeId: string; custom: ThemeDef[] }
/** BPS has always been light by default (no system detection), so the default stays light. */
export const DEFAULT_MODE: ModeChoice = 'light';
export const DEFAULT_APPEARANCE: AppearancePrefs = { mode: DEFAULT_MODE, themeId: DEFAULT_THEME.id, custom: [] };

/** Validated appearance prefs (stored data is untrusted): known mode, at most CUSTOM_LIMIT valid own themes (built-in ids refused). */
export function readAppearance(v: unknown): AppearancePrefs {
  const o = v && typeof v === 'object' ? (v as Record<string, unknown>) : {};
  const custom: ThemeDef[] = []; const ids = new Set<string>();
  for (const x of Array.isArray(o.custom) ? o.custom : []) {
    if (custom.length >= CUSTOM_LIMIT) break;
    const t = readTheme(x);
    if (t && !isBuiltinId(t.id) && !ids.has(t.id)) { ids.add(t.id); custom.push(t); }
  }
  const themeId = typeof o.themeId === 'string' && findTheme(o.themeId, custom) ? o.themeId : DEFAULT_THEME.id;
  return { mode: isModeChoice(o.mode) ? o.mode : DEFAULT_MODE, themeId, custom };
}

/** A choice that carries its own colours (device override, cookie). */
export interface LocalAppearance { mode: ModeChoice; theme: ThemeDef }
export function readLocal(v: unknown): LocalAppearance | null {
  if (!v || typeof v !== 'object') return null;
  const o = v as Record<string, unknown>;
  const theme = typeof o.themeId === 'string' && isBuiltinId(o.themeId) ? findTheme(o.themeId) : readTheme(o.theme);
  return theme && isModeChoice(o.mode) ? { mode: o.mode, theme } : null;
}
/** Compact form: built-in themes by id, own themes with their colours. */
export const toLocal = (a: LocalAppearance) => (isBuiltinId(a.theme.id) ? { mode: a.mode, themeId: a.theme.id } : { mode: a.mode, theme: a.theme });

// ------------------------------------------------------------------ the cookie (server + browser)
export const APPEARANCE_COOKIE = 'bps_appearance';
/** Cookie text for `a`; null (cookie removed) when it equals the defaults. */
export function cookieValue(a: LocalAppearance): string | null {
  return a.mode === DEFAULT_MODE && a.theme.id === DEFAULT_THEME.id ? null : encodeURIComponent(JSON.stringify(toLocal(a)));
}
/** What a request's cookie says (null when absent or not valid). Safe for untrusted input. */
export function readCookie(raw: string | undefined | null): LocalAppearance | null {
  if (!raw || raw.length > 4000) return null;
  for (const text of [raw, safeDecode(raw)]) {
    try { const r = readLocal(JSON.parse(text)); if (r) return r; } catch { /* try the next form */ }
  }
  return null;
}
const safeDecode = (s: string) => { try { return decodeURIComponent(s); } catch { return ''; } };

// ------------------------------------------------------------------ small observable stores (browser)
type Listener = () => void;
function store<T>(read: () => T) {
  let value = read(); const ls = new Set<Listener>();
  return {
    get: () => value,
    set(v: T) { value = v; ls.forEach((l) => l()); },
    reload() { value = read(); ls.forEach((l) => l()); },
    subscribe(l: Listener) { ls.add(l); return () => { ls.delete(l); }; },
  };
}
const lsGet = (k: string): unknown => { try { const raw = window.localStorage.getItem(k); return raw ? JSON.parse(raw) : null; } catch { return null; } };
const lsSet = (k: string, v: unknown) => { try { if (v === null) window.localStorage.removeItem(k); else window.localStorage.setItem(k, JSON.stringify(v)); } catch { /* not remembered */ } };

export const DEVICE_KEY = 'bps.appearance.device';
const deviceStore = store<LocalAppearance | null>(() => (typeof window === 'undefined' ? null : readLocal(lsGet(DEVICE_KEY))));
/** "This device only" override (null = follow the account). */
export const deviceAppearance = {
  get: deviceStore.get, subscribe: deviceStore.subscribe, reload: deviceStore.reload,
  write(a: LocalAppearance | null) { lsSet(DEVICE_KEY, a ? toLocal(a) : null); deviceStore.set(a); },
};
/** The theme being tried on (Admin › Appearance), shown instead of the saved one while set. */
export const themePreview = store<ThemeDef | null>(() => null);

/** Writes the cookie for what is now applied (1 year, whole site). */
export function writeCookie(a: LocalAppearance): void {
  try {
    const v = cookieValue(a);
    document.cookie = v === null
      ? `${APPEARANCE_COOKIE}=; path=/; max-age=0; SameSite=Lax`
      : `${APPEARANCE_COOKIE}=${v}; path=/; max-age=31536000; SameSite=Lax`;
  } catch { /* not remembered */ }
}

/** What is shown: try-on, else this device's override, else the account's choice, else the cookie (last applied), else the default theme / Light. */
export function resolveAppearance(a: { preview: ThemeDef | null; device: LocalAppearance | null; account: AppearancePrefs | undefined; last: LocalAppearance | null }): LocalAppearance {
  const base: LocalAppearance = a.device
    ?? (a.account ? { mode: a.account.mode, theme: findTheme(a.account.themeId, a.account.custom) ?? DEFAULT_THEME } : null)
    ?? a.last ?? { mode: DEFAULT_MODE, theme: DEFAULT_THEME };
  return a.preview ? { mode: base.mode, theme: a.preview } : base;
}

/** The signed-in staff user's saved choice (undefined until loaded, or when this user has no account preferences, e.g. a customer). */
export const accountAppearance = store<AppearancePrefs | undefined>(() => undefined);
/** While true the default theme (Hearth) is shown whatever was chosen on this device: the customer portal keeps the default look. */
export const defaultThemeOverride = store<boolean>(() => false);
