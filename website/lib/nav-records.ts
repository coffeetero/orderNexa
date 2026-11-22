/**
 * Recent-record rules shared by the sidebar, the API routes and the pages that report a "current record".
 * Pure (no React / no Supabase) so it can be unit-tested.
 */
export const RECORD_TYPES = ['customer', 'order', 'item', 'production_run'] as const;
export type RecordType = (typeof RECORD_TYPES)[number];

export type CurrentRecord = {
  type: RecordType;
  /** Customer/order/item id, or 'YYYY-MM-DD|CODE' for a production run. */
  key: string;
  /** e.g. "10700 · HOBOKEN BREAD DIST" */
  label: string;
  sublabel?: string | null;
};

export type RecentRow = {
  record_type: RecordType;
  record_key: string;
  label: string;
  sublabel: string | null;
  last_accessed_at: string;
};

/** Which recent lists each module shows, in order. Keys are top-level menu labels in nav-config. */
export const MODULE_RECENTS: Record<string, { type: RecordType; title: string }[]> = {
  Customers: [{ type: 'customer', title: 'Recent customers' }],
  Orders: [
    { type: 'customer', title: 'Recent customers' },
    { type: 'order', title: 'Recent orders' },
  ],
  Inventory: [{ type: 'item', title: 'Recent items' }],
  Production: [{ type: 'production_run', title: 'Recent production runs' }],
};

export function recentTypesFor(module: string | null | undefined): RecordType[] {
  return (module ? MODULE_RECENTS[module] ?? [] : []).map((r) => r.type);
}

const KEY_RE = /^[A-Za-z0-9|:_.-]{1,64}$/;

/** Normalizes untrusted input from the API; null when it is not acceptable. */
export function normalizeRecord(input: unknown): CurrentRecord | null {
  if (typeof input !== 'object' || input === null) return null;
  const o = input as Record<string, unknown>;
  const type = o.type;
  if (typeof type !== 'string' || !(RECORD_TYPES as readonly string[]).includes(type)) return null;
  const key = typeof o.key === 'string' || typeof o.key === 'number' ? String(o.key).trim() : '';
  if (!KEY_RE.test(key)) return null;
  const label = typeof o.label === 'string' ? o.label.trim().slice(0, 200) : '';
  if (!label) return null;
  const sub = typeof o.sublabel === 'string' ? o.sublabel.trim().slice(0, 200) : '';
  return { type: type as RecordType, key, label, sublabel: sub || null };
}

const ACTION_KEY_RE = /^\/[a-z0-9/_-]*$/;
export function isValidActionKey(key: unknown): key is string {
  return typeof key === 'string' && key.length <= 120 && ACTION_KEY_RE.test(key);
}

/**
 * One-click navigation target for a recent record, or null when its page does not exist yet.
 * `module` is the top-level menu the sidebar is showing (a recent customer opens Enter Orders under
 * Orders, and Customer Profiles under Customers).
 */
export function recordHref(type: RecordType, key: string, module: string | null | undefined): string | null {
  const k = encodeURIComponent(key);
  switch (type) {
    case 'customer':
      return module === 'Orders' ? `/orders?customer=${k}` : `/customers?customer=${k}`;
    case 'order':
      return /^\d+$/.test(key) ? `/orders/${key}/edit` : null;
    case 'item':
      return `/inventory/item-profile?item=${k}`;
    case 'production_run':
      return null; // no Production pages yet
  }
}

/** Parses a positive integer id from a URL parameter. */
export function parseIdParam(value: string | string[] | null | undefined): number | null {
  const v = Array.isArray(value) ? value[0] : value;
  if (!v || !/^\d{1,18}$/.test(v)) return null;
  const n = Number(v);
  return Number.isSafeInteger(n) && n > 0 ? n : null;
}
