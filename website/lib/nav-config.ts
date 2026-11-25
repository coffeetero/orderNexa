/**
 * Single source of truth for top navigation (desktop menubar + mobile drawer).
 *
 * `soon: true` marks entries whose page does not exist yet. They render greyed-out and are not
 * clickable (instead of linking to a bare 404). When you build a page, remove its `soon` flag —
 * lib/__tests__/nav-config.test.ts fails if a flag is stale in either direction.
 */
export type UserType = 'TENANCY_USER' | 'CUSTOMER_USER';
export type NavItem = {
  label: string;
  href: string;
  soon?: boolean;
  /** Restrict to these user types. Omit = every staff user. Hook for real permissions later. */
  requires?: UserType[];
  /** fnd_areas key the user must be able to read to see this entry in the sidebar section list. */
  area?: string;
  /** Sections of a long page, listed under it in the sidebar; the page shows the one in ?section=. */
  sections?: { key: string; label: string }[];
};
export type NavGroup = { heading?: string; items: NavItem[] };
export type NavMenu = {
  label: string;
  /** Top-level link (no dropdown). */
  href?: string;
  /** Hide the whole menu unless the user may read at least one of these areas (fnd_areas keys). Omit = always shown. */
  requiresAnyArea?: string[];
  groups?: NavGroup[];
};

/** Staff navigation. Hrefs are canonical tenant-host URLs (middleware rewrites them to /tenant/…). */
export const tenantNav: NavMenu[] = [
  { label: 'Dashboard', href: '/dashboard' },
  {
    label: 'Orders',
    groups: [
      {
        heading: 'Entry',
        items: [
          { label: 'Enter Orders', href: '/orders' },
          { label: 'Manage Orders', href: '/manage-orders' },
          { label: 'Import Orders', href: '/orders/import' },
          { label: 'Export Orders', href: '/orders/export' },
        ],
      },
      {
        heading: 'Standing',
        items: [
          { label: 'Standing Order Mgt', href: '/orders/standing-mgmt' },
          { label: 'Post Standing Orders', href: '/orders/standing' },
          { label: 'Call Up List', href: '/orders/callup', soon: true },
        ],
      },
      {
        heading: 'Adjustments',
        items: [{ label: 'Returns & Credits', href: '/orders/returns', soon: true }],
      },
    ],
  },
  {
    label: 'Production',
    groups: [
      {
        heading: 'Planning',
        items: [
          { label: 'Order Analysis', href: '/production/analysis', soon: true },
          { label: 'Estimate Production', href: '/production/estimate', soon: true },
        ],
      },
      {
        heading: 'Floor',
        items: [
          { label: 'Process Run', href: '/production/process' },
          { label: 'Confirm Deliveries', href: '/production/deliveries' },
          { label: "Baker's Report", href: '/production/report' },
          { label: 'Mixing Sheets', href: '/production/mixing', soon: true },
          { label: 'Packing Labels', href: '/production/labels' },
          { label: 'Print Invoices', href: '/production/invoices' },
          { label: 'Packaging List', href: '/production/packaging' },
          { label: 'Route Delivery Report', href: '/production/routes' },
        ],
      },
    ],
  },
  {
    label: 'Customers',
    groups: [
      {
        heading: 'Profiles',
        items: [
          { label: 'Customer Management', href: '/customers' },
        ],
      },
      {
        heading: 'Reporting',
        items: [
          { label: 'Reports', href: '/customers/reports', soon: true },
          { label: 'Import Customers', href: '/customers/import', area: 'customers.import' },
          { label: 'Export Customers', href: '/customers/export', area: 'customers.exports' },
        ],
      },
    ],
  },
  {
    label: 'Inventory',
    groups: [
      {
        heading: 'Items',
        items: [
          { label: 'Item Management', href: '/inventory/item-profile' },
          { label: 'Pricing Books', href: '/inventory/pricing' },
        ],
      },
      {
        heading: 'Costing',
        items: [
          { label: 'Recipes', href: '/inventory/recipes', soon: true },
          { label: 'Costing & COGS', href: '/inventory/costing', soon: true },
          { label: 'Waste Tracking', href: '/inventory/waste', soon: true },
        ],
      },
      {
        heading: 'Nutrition',
        items: [
          { label: 'Nutritional Analysis', href: '/inventory/nutrition', soon: true },
          { label: 'Nutrition Labels', href: '/inventory/labels' },
        ],
      },
      {
        heading: 'Insight',
        items: [
          { label: 'Reports', href: '/inventory/reports', soon: true },
          { label: 'Analysis', href: '/inventory/analysis', soon: true },
        ],
      },
    ],
  },
  {
    label: 'Financials',
    groups: [
      {
        heading: 'Receivables',
        items: [
          { label: 'AR Open Balances', href: '/financials/ar' },
          { label: 'AR Aging Report', href: '/financials/aging' },
          { label: 'Customer Statements', href: '/financials/statements' },
        ],
      },
      {
        heading: 'Cash',
        items: [
          { label: 'Manage Payments', href: '/financials/payments', soon: true },
          { label: 'Cash Reconciliation', href: '/financials/cash', soon: true },
        ],
      },
      {
        heading: 'Adjustments',
        items: [
          { label: 'Enter Credits', href: '/financials/credits' },
          { label: 'Enter Returns', href: '/financials/returns', soon: true },
        ],
      },
      {
        heading: 'Reporting',
        items: [
          { label: 'Sales Reports', href: '/financials/sales' },
          { label: 'Revenue Forecasting', href: '/financials/forecast' },
        ],
      },
    ],
  },
  {
    label: 'Organizer',
    requiresAnyArea: ['organizer.sheets'],
    groups: [
      {
        items: [
          { label: 'Sheets', href: '/organizer/sheets', area: 'organizer.sheets' },
          { label: 'Documents', href: '/organizer/documents', soon: true },
          { label: 'Calendar', href: '/organizer/calendar', soon: true },
          { label: 'Contacts', href: '/organizer/contacts', soon: true },
          { label: 'Tasks', href: '/organizer/tasks', soon: true },
        ],
      },
    ],
  },
  // The whole menu (and every page under /admin) needs an admin area; see requiresAnyArea. Appearance lives in the avatar menu.
  {
    label: 'Admin',
    requiresAnyArea: ['admin.roles', 'admin.customer-roles', 'admin.users', 'admin.groups', 'admin.channels', 'admin.production', 'admin.security'],
    groups: [
      {
        heading: 'Application Settings',
        items: [
          {
            label: 'Application Settings',
            href: '/admin/production',
            area: 'admin.production',
            sections: [
              { key: 'codes', label: 'Production codes' },
              { key: 'methods', label: 'Delivery methods' },
              { key: 'numbering', label: 'Formats' },
              { key: 'pricing', label: 'Pricing' },
              { key: 'runs', label: 'Upcoming runs' },
            ],
          },
          { label: 'Security', href: '/admin/security', area: 'admin.security' },
          { label: 'Health Checks', href: '/admin/health', area: 'admin.health' },
        ],
      },
      {
        heading: 'Company Settings',
        items: [
          { label: 'Roles', href: '/admin/roles', area: 'admin.roles' },
          { label: 'Users', href: '/admin/users', area: 'admin.users' },
          { label: 'Phone & Messaging', href: '/admin/channels', area: 'admin.channels' },
        ],
      },
      {
        heading: 'Customer Settings',
        items: [
          { label: 'Customer Roles', href: '/admin/customer-roles', area: 'admin.customer-roles' },
          { label: 'Customer Users', href: '/admin/customer-users', area: 'admin.users' },
          { label: 'Customer Groups', href: '/admin/groups', area: 'admin.groups' },
        ],
      },
    ],
  },
];

/** Menus the user may see, given the areas they can read (null = unknown, show everything). */
export function visibleMenus(menus: NavMenu[], areas: string[] | null): NavMenu[] {
  if (areas === null) return menus;
  return menus.filter((m) => !m.requiresAnyArea || m.requiresAnyArea.some((a) => areas.includes(a)));
}

/** Customer-portal navigation under `/<account_slug>`. */
export function customerNav(basePath: string): NavMenu[] {
  return [
    { label: 'Dashboard', href: basePath },
    {
      label: 'Orders',
      groups: [
        {
          items: [
            { label: 'Manage Orders', href: `${basePath}/orders` },
            { label: 'Order History', href: `${basePath}/orders/history` },
          ],
        },
      ],
    },
    {
      label: 'Invoicing',
      groups: [
        {
          items: [
            { label: 'Statements', href: `${basePath}/invoicing` },
            { label: 'Invoice History', href: `${basePath}/invoicing/history` },
            { label: 'Documents', href: `${basePath}/invoicing/documents` },
          ],
        },
      ],
    },
    {
      label: 'Payments',
      groups: [
        {
          items: [
            { label: 'Manage Payments', href: `${basePath}/payments` },
            { label: 'Payment History', href: `${basePath}/payments/history` },
          ],
        },
      ],
    },
  ];
}

export function menuItems(menu: NavMenu): NavItem[] {
  if (menu.href) return [{ label: menu.label, href: menu.href }];
  return (menu.groups ?? []).flatMap((g) => g.items);
}

/** Canonical path: strips the internal `/tenant` prefix and any trailing slash. */
export function normalizePath(pathname: string): string {
  let p = pathname.replace(/\/+$/, '') || '/';
  if (p === '/tenant') return '/dashboard';
  if (p.startsWith('/tenant/')) p = p.slice('/tenant'.length);
  return p;
}

/**
 * The single nav href that matches the current page: the longest href that equals the path or is a
 * path-segment prefix of it (so /orders/standing wins over /orders, and /orders/12/edit maps to /orders).
 */
export function findActiveHref(pathname: string, menus: NavMenu[]): string | null {
  const path = normalizePath(pathname);
  let best: string | null = null;
  for (const menu of menus) {
    for (const item of menuItems(menu)) {
      if (item.soon) continue;
      const matches = path === item.href || path.startsWith(item.href + '/');
      if (matches && (best === null || item.href.length > best.length)) best = item.href;
    }
  }
  return best;
}

/** The menu (top-level entry) containing the active href, for highlighting the parent. */
export function findActiveMenu(pathname: string, menus: NavMenu[]): NavMenu | null {
  const active = findActiveHref(pathname, menus);
  if (!active) return null;
  return menus.find((m) => menuItems(m).some((i) => i.href === active)) ?? null;
}

/** Top-level menu label + item for every built (non-"soon") entry the user may open. */
export type BuiltAction = { href: string; label: string; module: string };

export function isAuthorized(item: NavItem, userType: UserType | null | undefined): boolean {
  return !item.requires || (!!userType && item.requires.includes(userType));
}

export function builtActions(menus: NavMenu[], userType: UserType | null | undefined = 'TENANCY_USER'): BuiltAction[] {
  const out: BuiltAction[] = [];
  for (const menu of menus) {
    for (const item of menuItems(menu)) {
      if (item.soon || !isAuthorized(item, userType)) continue;
      out.push({ href: item.href, label: item.label, module: menu.label });
    }
  }
  return out;
}

/** First built entry of a menu (where a "Module" breadcrumb leads). */
export function firstBuiltHref(menu: NavMenu): string | null {
  return menuItems(menu).find((i) => !i.soon)?.href ?? null;
}
