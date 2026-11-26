import type { BuiltAction } from '@/lib/nav-config';

export const QUICK_ACCESS_SLOTS = 4;
/** Validates a requested pin list (ordered, unique, max 4, built + authorized only). */
export function normalizePins(keys: unknown, allowed: BuiltAction[]): string[] | null {
  if (!Array.isArray(keys) || keys.length > QUICK_ACCESS_SLOTS) return null;
  const ok = new Set(allowed.map((a) => a.href));
  const out: string[] = [];
  for (const k of keys) {
    if (typeof k !== 'string' || !ok.has(k) || out.includes(k)) return null;
    out.push(k);
  }
  return out;
}

/** The 4 icon buttons in the breadcrumb bar, until the user assigns their own (decided 2026-11-26). */
export const DEFAULT_QUICK_BUTTONS = ['/orders', '/financials/enter-payments', '/customers', '/inventory/item-profile'];

/** Buttons = the user's pinned actions in order, then the defaults for any empty slot. Only allowed actions. */
export function selectQuickButtons(pinned: string[], allowed: BuiltAction[], slots: number = QUICK_ACCESS_SLOTS): string[] {
  const ok = new Set(allowed.map((a) => a.href));
  const out: string[] = [];
  for (const href of [...pinned, ...DEFAULT_QUICK_BUTTONS]) {
    if (out.length < slots && ok.has(href) && !out.includes(href)) out.push(href);
  }
  return out;
}
