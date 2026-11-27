import { existsSync } from 'fs';
import path from 'path';
import { describe, expect, it } from 'vitest';
import {
  customerNav,
  findActiveHref,
  findActiveMenu,
  menuItems,
  normalizePath,
  tenantNav,
} from '@/lib/nav-config';

const root = path.resolve(__dirname, '../..');
const pageExists = (dir: string) => existsSync(path.join(root, dir, 'page.tsx'));

describe('tenantNav matches the real routes', () => {
  const items = tenantNav.flatMap(menuItems);

  it('every non-"soon" entry has a page', () => {
    for (const item of items.filter((i) => !i.soon)) {
      expect(pageExists(`app/tenant${item.href}`), `${item.href} has no page`).toBe(true);
    }
  });

  it('every "soon" entry still has no page (remove the flag once it is built)', () => {
    for (const item of items.filter((i) => i.soon)) {
      expect(pageExists(`app/tenant${item.href}`), `${item.href} now exists - drop soon`).toBe(false);
    }
  });

  it('keeps every route the old sidebar exposed', () => {
    const hrefs = new Set(items.map((i) => i.href));
    for (const href of [
      '/dashboard', '/orders', '/orders/standing', '/orders/standing-mgmt', '/manage-orders',
      '/customers', '/inventory/item-profile', '/production/analysis', '/financials/ar',
      '/inventory/nutrition', '/orders/callup', '/orders/import', '/financials/returns', '/admin/production', '/production/process', '/production/report', '/production/labels', '/production/packaging', '/production/routes', '/production/deliveries', '/financials/credits',
    ]) {
      expect(hrefs.has(href), href).toBe(true);
    }
    expect(items.length).toBe(1 + 8 + 7 + 3 + 9 + 10 + 11 + 5 + 1 - 1 + 1 + 6 + 4); // + Inventory > Purchasing (Vendors, Vendor Items, 2 planned, 2026-11-26); + Operations > Delivery (Routes Maintenance + 5 planned fleet screens, 2026-11-26); + Financials > Enter Payments (Manage Payments became Payment History, 2026-11-25); - Orders > Returns & Credits (moved to Financials > Enter Returns, 2026-11-25); Dashboard + old sidebar sections + Admin > Appearance, Application Settings, Production > Process Run, Process Run + Orders > Export Orders + Production > Print Invoices + Organizer (Sheets and 4 planned) + Customers Import/Export split in two
  });
});

describe('customerNav', () => {
  const base = '/hoboken-bread-dist';
  const items = customerNav(base).flatMap(menuItems);

  it('maps every entry to an existing customer-portal page', () => {
    for (const item of items) {
      const rest = item.href.slice(base.length);
      expect(pageExists(`app/[account_slug]${rest}`), item.href).toBe(true);
    }
  });
});

describe('findActiveHref', () => {
  it('prefers the most specific match', () => {
    expect(findActiveHref('/orders/standing', tenantNav)).toBe('/orders/standing');
    expect(findActiveHref('/orders/standing-mgmt', tenantNav)).toBe('/orders/standing-mgmt');
    expect(findActiveHref('/orders', tenantNav)).toBe('/orders');
  });
  it('maps dynamic sub-routes to their section entry', () => {
    expect(findActiveHref('/orders/123/edit', tenantNav)).toBe('/orders');
    expect(findActiveHref('/orders/new', tenantNav)).toBe('/orders');
  });
  it('understands the internal /tenant prefix', () => {
    expect(findActiveHref('/tenant/manage-orders', tenantNav)).toBe('/manage-orders');
    expect(findActiveHref('/tenant', tenantNav)).toBe('/dashboard');
    expect(normalizePath('/tenant/orders/')).toBe('/orders');
  });
  it('never marks a "soon" item active, and returns null for unknown paths', () => {
    expect(findActiveHref('/production/mixing', tenantNav)).toBeNull();
    expect(findActiveHref('/profile', tenantNav)).toBeNull();
  });
  it('does not confuse /orders with a sibling like /orders-archive', () => {
    expect(findActiveHref('/orders-archive', tenantNav)).toBeNull();
  });
  it('works for the customer portal base path', () => {
    const nav = customerNav('/acme');
    expect(findActiveHref('/acme', nav)).toBe('/acme');
    expect(findActiveHref('/acme/orders/history', nav)).toBe('/acme/orders/history');
    expect(findActiveMenu('/acme/invoicing/history', nav)?.label).toBe('Invoicing');
  });
});

describe('findActiveMenu', () => {
  it('returns the parent menu of the active page', () => {
    expect(findActiveMenu('/orders/standing', tenantNav)?.label).toBe('Operations');
    expect(findActiveMenu('/inventory/item-profile', tenantNav)?.label).toBe('Inventory');
    expect(findActiveMenu('/dashboard', tenantNav)?.label).toBe('Dashboard');
  });
});

import { visibleMenus } from '../nav-config';
describe('visibleMenus', () => {
  it('hides the Admin menu unless the user can read an admin area', () => {
    const labels = (areas: string[] | null) => visibleMenus(tenantNav, areas).map((m) => m.label);
    expect(labels(['orders.enter'])).not.toContain('Admin');
    expect(labels(['orders.enter', 'admin.users'])).toContain('Admin');
    expect(labels(null)).toContain('Admin');
    expect(labels([])).toContain('Operations');
  });
});
