import type { BuiltAction } from '@/lib/nav-config';

export const QUICK_ACCESS_SLOTS = 4;
const WINDOW_DAYS = 90;

/** Shown until the user has history. There is no Inventory landing page, so Item Management stands in (see FALLBACK). */
export const DEFAULT_QUICK_ACCESS = ['/orders', '/customers', '/inventory'];
export const FALLBACK_QUICK_ACCESS = ['/inventory/item-profile', '/orders/standing-mgmt', '/manage-orders'];

export type ActionRow = {
  action_key: string;
  use_count: number;
  last_used_at: string | null;
  is_pinned: boolean;
  pin_order: number | null;
};

/**
 * The (up to 4) menu actions for Quick Access:
 *   1. pinned actions, in pin order
 *   2. most-used actions in the last 90 days (use_count, then recency)
 *   3. defaults, then fallbacks, for any slot still empty
 * Only actions in `allowed` (built + authorized for this user) are ever returned.
 */
export function selectQuickAccess(
  rows: ActionRow[],
  allowed: BuiltAction[],
  now: Date = new Date(),
  slots: number = QUICK_ACCESS_SLOTS,
): string[] {
  const ok = new Set(allowed.map((a) => a.href));
  const picked: string[] = [];
  const add = (key: string) => {
    if (picked.length < slots && ok.has(key) && !picked.includes(key)) picked.push(key);
  };

  rows
    .filter((r) => r.is_pinned)
    .sort((a, b) => (a.pin_order ?? 99) - (b.pin_order ?? 99))
    .forEach((r) => add(r.action_key));

  const cutoff = now.getTime() - WINDOW_DAYS * 86_400_000;
  rows
    .filter((r) => !r.is_pinned && r.use_count > 0 && r.last_used_at && new Date(r.last_used_at).getTime() >= cutoff)
    .sort((a, b) => b.use_count - a.use_count || new Date(b.last_used_at!).getTime() - new Date(a.last_used_at!).getTime())
    .forEach((r) => add(r.action_key));

  DEFAULT_QUICK_ACCESS.forEach(add);
  FALLBACK_QUICK_ACCESS.forEach(add);
  return picked;
}

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
