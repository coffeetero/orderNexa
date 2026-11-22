import { describe, expect, it } from 'vitest';
import { resolveTenantRoute, TENANT_KEYWORDS } from '@/lib/tenant-routing';

describe('resolveTenantRoute', () => {
  it('rewrites staff routes to /tenant/* on a tenant subdomain and passes the slug', () => {
    expect(resolveTenantRoute('/dashboard', 'alpine')).toEqual({ type: 'rewrite', to: '/tenant/dashboard', tenantSlug: 'alpine' });
    expect(resolveTenantRoute('/orders/standing', 'alpine')).toEqual({ type: 'rewrite', to: '/tenant/orders/standing', tenantSlug: 'alpine' });
  });

  it('also rewrites staff routes on bare hosts (regression: /dashboard 404ed on localhost after login)', () => {
    expect(resolveTenantRoute('/dashboard', null)).toEqual({ type: 'rewrite', to: '/tenant/dashboard', tenantSlug: null });
    expect(resolveTenantRoute('/orders/123/edit', null)).toEqual({ type: 'rewrite', to: '/tenant/orders/123/edit', tenantSlug: null });
  });

  it('covers every staff keyword', () => {
    for (const k of TENANT_KEYWORDS) {
      expect(resolveTenantRoute(`/${k}`, null).type).toBe('rewrite');
    }
  });

  it('redirects /tenant/* to the canonical URL on any host', () => {
    expect(resolveTenantRoute('/tenant', null)).toEqual({ type: 'redirect', to: '/dashboard' });
    expect(resolveTenantRoute('/tenant/', 'alpine')).toEqual({ type: 'redirect', to: '/dashboard' });
    expect(resolveTenantRoute('/tenant/orders/new', null)).toEqual({ type: 'redirect', to: '/orders/new' });
  });

  it('leaves the home page, login and customer slugs alone', () => {
    expect(resolveTenantRoute('/', 'alpine')).toEqual({ type: 'next' });
    expect(resolveTenantRoute('/', null)).toEqual({ type: 'next' });
    expect(resolveTenantRoute('/login', null)).toEqual({ type: 'next' });
    expect(resolveTenantRoute('/hoboken-bread-dist/orders', 'alpine')).toEqual({ type: 'next' });
  });

  it('only matches whole path segments', () => {
    expect(resolveTenantRoute('/orders-archive', null)).toEqual({ type: 'next' });
    expect(resolveTenantRoute('/tenants', null)).toEqual({ type: 'next' });
  });
});
