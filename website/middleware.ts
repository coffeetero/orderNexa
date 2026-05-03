import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';
import { parseTenantSubdomain } from '@/lib/tenant-subdomain';

export async function middleware(request: NextRequest) {
  const url = request.nextUrl.clone();
  const host = request.headers.get('host') || '';
  const { pathname } = url;

  // 1. SHIELD: Do not touch static assets or API routes
  if (
    pathname.startsWith('/_next') ||
    pathname.startsWith('/api') ||
    pathname.startsWith('/login') ||
    pathname.startsWith('/auth') ||
    pathname.includes('.')
  ) {
    return NextResponse.next();
  }

  // 2. DOMAIN LOGIC (e.g., alpine.localhost or alpine.ordernexa.com)
  const subdomain = parseTenantSubdomain(host);

  // 3. EXIT: If no tenant subdomain, serve the main app normally
  if (!subdomain) {
    console.log(`>>> MAIN DOMAIN: ${pathname}`);
    return NextResponse.next();
  }

  // Subdomain root: let `/` through so app/page.tsx handles session + redirects
  if (pathname === '/') {
    return NextResponse.next();
  }

  // 4. ROUTE LOGIC: Tenant vs Account
  const tenantKeywords = [
    'dashboard',
    'orders',
    'settings',
    'profile',
    'inventory',
    'reports',
    'billing',
    'invoicing',
    'payments',
  ];
  const firstSegment = pathname.split('/').filter(Boolean)[0] ?? '';

  if (tenantKeywords.includes(firstSegment)) {
    url.pathname = `/tenant${pathname}`;
    console.log(`>>> TENANT REWRITE: ${subdomain}${pathname} -> ${url.pathname}`);
  } else {
    // It's a customer slug (e.g., /the-new-york-hilton)
    url.pathname = `/account${pathname}`;
    console.log(`>>> ACCOUNT REWRITE: ${subdomain}${pathname} -> ${url.pathname}`);
  }

  url.searchParams.set('tenant_slug', subdomain);
  return NextResponse.rewrite(url);
}

export const config = {
  matcher: [
    /*
     * Match all request paths except for the ones starting with:
     * - api (API routes)
     * - _next/static (static files)
     * - _next/image (image optimization files)
     * - favicon.ico (favicon file)
     */
    '/((?!api|_next/static|_next/image|favicon.ico).*)',
  ],
};