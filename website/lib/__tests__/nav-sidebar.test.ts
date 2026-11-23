import { describe, expect, it } from 'vitest';
import { builtActions, firstBuiltHref, isAuthorized, tenantNav, type NavItem } from '@/lib/nav-config';
import { buildBreadcrumbs } from '@/lib/breadcrumbs';
import {
  isValidActionKey, MODULE_RECENTS, normalizeRecord, parseIdParam, recentTypesFor, recordHref,
} from '@/lib/nav-records';
import { normalizePins, selectQuickAccess, type ActionRow } from '@/lib/quick-access';

const allowed = builtActions(tenantNav);
const NOW = new Date('2026-11-22T12:00:00Z');
const row = (key: string, uses: number, daysAgo: number, pin: number | null = null): ActionRow => ({
  action_key: key, use_count: uses, last_used_at: new Date(NOW.getTime() - daysAgo * 86_400_000).toISOString(),
  is_pinned: pin !== null, pin_order: pin,
});

describe('builtActions / authorization', () => {
  it('lists only built entries with their module', () => {
    const hrefs = allowed.map((a) => a.href);
    expect(hrefs).toContain('/orders');
    expect(hrefs).not.toContain('/inventory'); // no Inventory landing page
    expect(allowed.find((a) => a.href === '/customers')).toMatchObject({ label: 'Customer Management', module: 'Customers' });
  });
  it('honours the requires hook', () => {
    const item: NavItem = { label: 'X', href: '/x', requires: ['TENANCY_USER'] };
    expect(isAuthorized(item, 'TENANCY_USER')).toBe(true);
    expect(isAuthorized(item, 'CUSTOMER_USER')).toBe(false);
    expect(isAuthorized({ label: 'Y', href: '/y' }, null)).toBe(true);
  });
  it('firstBuiltHref skips "Soon" entries', () => {
    const inventory = tenantNav.find((m) => m.label === 'Inventory')!;
    expect(firstBuiltHref(inventory)).toBe('/inventory/item-profile');
  });
});

describe('selectQuickAccess', () => {
  it('starts with the defaults (Item Management stands in for the missing Inventory landing page)', () => {
    expect(selectQuickAccess([], allowed, NOW)).toEqual(['/orders', '/customers', '/inventory/item-profile', '/orders/standing-mgmt']);
  });
  it('puts pins first, in pin order', () => {
    const rows = [row('/manage-orders', 1, 1, 2), row('/customers', 5, 1, 1)];
    expect(selectQuickAccess(rows, allowed, NOW).slice(0, 2)).toEqual(['/customers', '/manage-orders']);
  });
  it('ranks unpinned actions by use count, then recency, and fills with defaults', () => {
    const rows = [row('/manage-orders', 10, 2), row('/orders/standing', 10, 1), row('/customers', 3, 1)];
    expect(selectQuickAccess(rows, allowed, NOW)).toEqual(['/orders/standing', '/manage-orders', '/customers', '/orders']);
  });
  it('ignores usage older than 90 days', () => {
    const rows = [row('/manage-orders', 99, 200)];
    expect(selectQuickAccess(rows, allowed, NOW)).toEqual(['/orders', '/customers', '/inventory/item-profile', '/orders/standing-mgmt']);
  });
  it('never returns unbuilt or unknown actions, even if pinned', () => {
    const rows = [row('/production/mixing', 50, 1, 1), row('/nope', 50, 1)];
    expect(selectQuickAccess(rows, allowed, NOW)).toEqual(['/orders', '/customers', '/inventory/item-profile', '/orders/standing-mgmt']);
  });
  it('returns at most 4 with no duplicates', () => {
    const rows = [row('/orders', 5, 1, 1), row('/orders', 9, 1), row('/customers', 9, 1)];
    const out = selectQuickAccess(rows, allowed, NOW);
    expect(out).toHaveLength(4);
    expect(new Set(out).size).toBe(4);
  });
});

describe('normalizePins', () => {
  it('accepts an ordered list of built actions', () => {
    expect(normalizePins(['/customers', '/orders'], allowed)).toEqual(['/customers', '/orders']);
    expect(normalizePins([], allowed)).toEqual([]);
  });
  it('rejects too many, duplicates, unbuilt, and non-arrays', () => {
    expect(normalizePins(['/orders', '/customers', '/manage-orders', '/dashboard', '/inventory/item-profile'], allowed)).toBeNull();
    expect(normalizePins(['/orders', '/orders'], allowed)).toBeNull();
    expect(normalizePins(['/production/mixing'], allowed)).toBeNull();
    expect(normalizePins('/orders', allowed)).toBeNull();
    expect(normalizePins([42], allowed)).toBeNull();
  });
});

describe('recent records', () => {
  it('maps modules to the lists they show', () => {
    expect(recentTypesFor('Customers')).toEqual(['customer']);
    expect(recentTypesFor('Orders')).toEqual(['customer', 'order']);
    expect(recentTypesFor('Inventory')).toEqual(['item']);
    expect(recentTypesFor('Production')).toEqual(['production_run']);
    expect(recentTypesFor('Financials')).toEqual([]);
    expect(recentTypesFor(null)).toEqual([]);
    expect(Object.keys(MODULE_RECENTS).every((m) => tenantNav.some((n) => n.label === m))).toBe(true);
  });
  it('builds deep links per module', () => {
    expect(recordHref('customer', '10700', 'Orders')).toBe('/orders?customer=10700');
    expect(recordHref('customer', '10700', 'Customers')).toBe('/customers?customer=10700');
    expect(recordHref('order', '55', 'Orders')).toBe('/orders/55/edit');
    expect(recordHref('order', 'abc', 'Orders')).toBeNull();
    expect(recordHref('item', '9', 'Inventory')).toBe('/inventory/item-profile?item=9');
    expect(recordHref('production_run', '2026-11-23|AM', 'Production')).toBeNull();
  });
  it('validates and normalizes untrusted records', () => {
    expect(normalizeRecord({ type: 'customer', key: 10700, label: '  10700 · HOBOKEN  ', sublabel: '' }))
      .toEqual({ type: 'customer', key: '10700', label: '10700 · HOBOKEN', sublabel: null });
    expect(normalizeRecord({ type: 'production_run', key: '2026-11-23|AM', label: 'AM run' })?.key).toBe('2026-11-23|AM');
    expect(normalizeRecord({ type: 'customer', key: '1 OR 1=1', label: 'x' })).toBeNull();
    expect(normalizeRecord({ type: 'secret', key: '1', label: 'x' })).toBeNull();
    expect(normalizeRecord({ type: 'item', key: '1', label: '   ' })).toBeNull();
    expect(normalizeRecord(null)).toBeNull();
    expect(normalizeRecord({ type: 'item', key: '1', label: 'x'.repeat(500) })?.label).toHaveLength(200);
  });
  it('validates action keys and id params', () => {
    expect(isValidActionKey('/orders/standing-mgmt')).toBe(true);
    expect(isValidActionKey('orders')).toBe(false);
    expect(isValidActionKey('/Orders')).toBe(false);
    expect(isValidActionKey("/x'; drop table")).toBe(false);
    expect(parseIdParam('123')).toBe(123);
    expect(parseIdParam(['7', '8'])).toBe(7);
    expect(parseIdParam('12abc')).toBeNull();
    expect(parseIdParam('0')).toBeNull();
    expect(parseIdParam(null)).toBeNull();
  });
});

describe('buildBreadcrumbs', () => {
  it('shows Module > Page', () => {
    expect(buildBreadcrumbs('/customers', tenantNav)).toEqual([
      { label: 'Customers', href: '/customers' },
      { label: 'Customer Management' },
    ]);
  });
  it('adds the selected record and makes the page crumb a link', () => {
    const record = { type: 'customer' as const, key: '10700', label: 'Hoboken Bread Dist' };
    expect(buildBreadcrumbs('/customers', tenantNav, record)).toEqual([
      { label: 'Customers', href: '/customers' },
      { label: 'Customer Management', href: '/customers' },
      { label: 'Hoboken Bread Dist' },
    ]);
  });
  it("sends a module crumb to the module's first built page", () => {
    expect(buildBreadcrumbs('/inventory/item-profile', tenantNav)[0]).toEqual({ label: 'Inventory', href: '/inventory/item-profile' });
    expect(buildBreadcrumbs('/orders/standing', tenantNav)[0]).toEqual({ label: 'Orders', href: '/orders' });
  });
  it('handles dashboard, extra pages, edit-order and the internal /tenant prefix', () => {
    expect(buildBreadcrumbs('/dashboard', tenantNav)).toEqual([{ label: 'Dashboard' }]);
    expect(buildBreadcrumbs('/tenant/profile', tenantNav)).toEqual([{ label: 'User Profile' }]);
    expect(buildBreadcrumbs('/orders/55/edit', tenantNav, { type: 'order', key: '55', label: '0115-1087' }).map((c) => c.label))
      .toEqual(['Orders', 'Enter Orders', '0115-1087']);
    expect(buildBreadcrumbs('/tenant/manage-orders', tenantNav).map((c) => c.label)).toEqual(['Orders', 'Manage Orders']);
  });
  it('returns nothing for unknown pages', () => {
    expect(buildBreadcrumbs('/nowhere', tenantNav)).toEqual([]);
  });
});

describe('sidebar preference cookie', () => {
  it('is a plain string constant shared by server and client (regression: it was imported from a client module)', async () => {
    const pref = await import('@/lib/sidebar-pref');
    expect(typeof pref.SIDEBAR_COOKIE).toBe('string');
    expect([pref.SIDEBAR_COLLAPSED, pref.SIDEBAR_OPEN]).toEqual(['collapsed', 'open']);
  });
});
