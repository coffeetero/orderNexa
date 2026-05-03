import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

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

  // 2. DOMAIN LOGIC
  const hostname = host.split(':')[0];
  const parts = hostname.split('.');
  // Check if we have a subdomain (e.g., alpine.localhost or alpine.ordernexa.com)
  const subdomain = parts.length > (hostname.includes('localhost') ? 1 : 2) ? parts[0] : null;

  // 3. EXIT: If no subdomain or it's 'www', serve the main app normally
  if (!subdomain || subdomain === 'www' || subdomain === 'localhost') {
    console.log(`>>> MAIN DOMAIN: ${pathname}`);
    return NextResponse.next();
  }

  // 4. ROUTE LOGIC: Tenant vs Account
  const tenantKeywords = ['dashboard', 'orders', 'settings', 'profile', 'inventory', 'reports', 'billing', 'invoicing', 'payments','login'];
  const pathSegments = pathname.split('/').filter(Boolean);
  const firstSegment = pathSegments[0] || '';

  // If the URL is just 'alpine.localhost/', send to dashboard
  if (!firstSegment) {
     url.pathname = `/tenant/dashboard`;
     url.searchParams.set('tenant_slug', subdomain);
     return NextResponse.rewrite(url);
  }

  if (tenantKeywords.includes(firstSegment)) {
    // It's a tenant page (e.g., /orders)
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