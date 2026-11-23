import { findActiveHref, findActiveMenu, firstBuiltHref, menuItems, normalizePath, type NavMenu } from '@/lib/nav-config';
import type { CurrentRecord } from '@/lib/nav-records';

export type Crumb = { label: string; href?: string };

/** Pages that are not in the menus but still deserve a breadcrumb. */
const EXTRA_PAGES: Record<string, string> = {
  '/profile': 'User Profile',
  '/settings': 'Account Settings',
};

/**
 * `Module › Page › Record`. The last crumb is the current location and has no href. Clicking the module goes to
 * its first built page; clicking the page leaves the record (e.g. back to an empty Customer Management).
 */
export function buildBreadcrumbs(pathname: string, menus: NavMenu[], record?: CurrentRecord | null): Crumb[] {
  const path = normalizePath(pathname);

  const extra = EXTRA_PAGES[path];
  if (extra) return [{ label: extra }];

  const menu = findActiveMenu(pathname, menus);
  const activeHref = findActiveHref(pathname, menus);
  if (!menu || !activeHref) return [];

  if (menu.href) return [{ label: menu.label }]; // top-level link such as Dashboard

  const item = menuItems(menu).find((i) => i.href === activeHref);
  if (!item) return [];

  const crumbs: Crumb[] = [{ label: menu.label, href: firstBuiltHref(menu) ?? undefined }];
  if (record) {
    crumbs.push({ label: item.label, href: item.href }, { label: record.label });
  } else {
    crumbs.push({ label: item.label });
  }
  return crumbs;
}
