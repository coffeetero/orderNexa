/**
 * Host/path routing rules used by middleware.ts (kept pure so they can be unit-tested).
 *
 * Staff pages live under app/tenant/* but are served at canonical URLs (/dashboard, /orders, …) via a
 * rewrite. They resolve their tenant from the signed-in user's JWT, not from the host, so the rewrite
 * applies on tenant subdomains (alpine.ordernexa.com) and on bare hosts (localhost, 127.0.0.1) alike.
 * Customer-portal pages (/<account_slug>) still require a tenant subdomain.
 */
export const TENANT_KEYWORDS = [
  'dashboard',
  'orders',
  'manage-orders',
  'settings',
  'profile',
  'inventory',
  'reports',
  'billing',
  'invoicing',
  'payments',
  'customers',
  'production',
  'financials',
] as const;

export type TenantRoute =
  | { type: 'next' }
  | { type: 'redirect'; to: string }
  | { type: 'rewrite'; to: string; tenantSlug: string | null };

export function resolveTenantRoute(pathname: string, subdomain: string | null): TenantRoute {
  // Canonical URLs are /orders, /customers, … — not /tenant/…
  if (pathname === '/tenant' || pathname.startsWith('/tenant/')) {
    const afterTenant = pathname.slice('/tenant'.length);
    if (afterTenant === '' || afterTenant === '/') return { type: 'redirect', to: '/dashboard' };
    return { type: 'redirect', to: afterTenant.startsWith('/') ? afterTenant : `/${afterTenant}` };
  }

  if (pathname === '/') return { type: 'next' };

  const firstSegment = pathname.split('/').filter(Boolean)[0] ?? '';
  if ((TENANT_KEYWORDS as readonly string[]).includes(firstSegment)) {
    return { type: 'rewrite', to: `/tenant${pathname}`, tenantSlug: subdomain };
  }

  return { type: 'next' };
}
