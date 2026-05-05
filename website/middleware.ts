import { createServerClient } from '@supabase/ssr';
import type { CookieOptions } from '@supabase/ssr';
import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';
import { parseTenantSubdomain } from '@/lib/tenant-subdomain';

function copyAuthCookies(from: NextResponse, to: NextResponse) {
  for (const cookie of from.cookies.getAll()) {
    to.cookies.set(cookie);
  }
}

export async function middleware(request: NextRequest) {
  const url = request.nextUrl.clone();
  const host = request.headers.get('host') || '';
  const { pathname } = url;

  // Static / build / API — skip auth refresh (matcher already excludes most API/static)
  if (
    pathname.startsWith('/_next') ||
    pathname.startsWith('/api') ||
    pathname.includes('.')
  ) {
    return NextResponse.next();
  }

  const requestHeaders = request.headers;

  let response = NextResponse.next({
    request: { headers: requestHeaders },
  });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      db: {
        schema: process.env.NEXT_PUBLIC_DB_SCHEMA || 'public',
      },
      cookies: {
        get(name: string) {
          return request.cookies.get(name)?.value;
        },
        set(name: string, value: string, options: CookieOptions) {
          response = NextResponse.next({
            request: { headers: requestHeaders },
          });
          response.cookies.set(name, value, options);
        },
        remove(name: string, options: CookieOptions) {
          response = NextResponse.next({
            request: { headers: requestHeaders },
          });
          response.cookies.set(name, '', { ...options, maxAge: 0 });
        },
      },
    }
  );

  try {
    await supabase.auth.getUser();
  } catch {
    // Stale or revoked refresh token — avoid failing the whole request; RSC uses getSessionUser() too.
  }

  // Tenant host routing (e.g. alpine.localhost or alpine.ordernexa.com)
  const subdomain = parseTenantSubdomain(host);

  if (!subdomain) {
    console.log(`>>> MAIN DOMAIN: ${pathname}`);
    return response;
  }

  // Canonical URLs on tenant hosts are /orders, /customers, … — not /tenant/…
  // (Rewrites only affect the internal route; the bar shows whatever clients navigate to.)
  if (pathname.startsWith('/tenant')) {
    const redirectUrl = request.nextUrl.clone();
    const afterTenant = pathname.slice('/tenant'.length);
    if (afterTenant === '' || afterTenant === '/') {
      redirectUrl.pathname = '/dashboard';
    } else {
      redirectUrl.pathname = afterTenant.startsWith('/') ? afterTenant : `/${afterTenant}`;
    }
    const redirectResponse = NextResponse.redirect(redirectUrl);
    copyAuthCookies(response, redirectResponse);
    return redirectResponse;
  }

  if (pathname === '/') {
    return response;
  }

  const tenantKeywords = [
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
  ];
  const firstSegment = pathname.split('/').filter(Boolean)[0] ?? '';

  if (tenantKeywords.includes(firstSegment)) {
    url.pathname = `/tenant${pathname}`;
    url.searchParams.set('tenant_slug', subdomain);
    console.log(`>>> TENANT REWRITE: ${subdomain}${pathname} -> ${url.pathname}`);

    const rewriteResponse = NextResponse.rewrite(url, {
      request: { headers: requestHeaders },
    });
    copyAuthCookies(response, rewriteResponse);
    return rewriteResponse;
  }

  console.log(`>>> ACCOUNT NEXT: ${subdomain}${pathname}`);
  return response;
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
