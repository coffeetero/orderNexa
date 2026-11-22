import { createServerClient } from '@supabase/ssr';
import type { CookieOptions } from '@supabase/ssr';
import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';
import { parseTenantSubdomain } from '@/lib/tenant-subdomain';
import { resolveTenantRoute } from '@/lib/tenant-routing';
import { checkTenantSession, decodeTenantClaims, isTenantFreePath } from '@/lib/tenant-session';

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

  let signedIn = false;
  try {
    const { data } = await supabase.auth.getUser();
    signedIn = !!data?.user;
  } catch {
    // Stale or revoked refresh token — avoid failing the whole request; RSC uses getSessionUser() too.
  }

  // Tenant host routing (e.g. alpine.localhost or alpine.ordernexa.com). Staff routes are also served on
  // bare hosts (localhost, 127.0.0.1) — see lib/tenant-routing.ts.
  const subdomain = parseTenantSubdomain(host);

  // One active tenancy per session: a signed-in user without a tenancy claim, or on another tenant's address,
  // must pick one first (the picker is skipped automatically when there is nothing to choose).
  if (signedIn && !isTenantFreePath(pathname)) {
    const { data: sessionData } = await supabase.auth.getSession();
    const claims = decodeTenantClaims(sessionData.session?.access_token);
    if (checkTenantSession(claims, subdomain) === 'select') {
      const pickUrl = request.nextUrl.clone();
      pickUrl.pathname = '/select-tenant';
      pickUrl.search = `?next=${encodeURIComponent(pathname + request.nextUrl.search)}`;
      const pickResponse = NextResponse.redirect(pickUrl);
      copyAuthCookies(response, pickResponse);
      return pickResponse;
    }
  }

  const route = resolveTenantRoute(pathname, subdomain);

  if (route.type === 'redirect') {
    const redirectUrl = request.nextUrl.clone();
    redirectUrl.pathname = route.to;
    const redirectResponse = NextResponse.redirect(redirectUrl);
    copyAuthCookies(response, redirectResponse);
    return redirectResponse;
  }

  if (route.type === 'rewrite') {
    url.pathname = route.to;
    if (route.tenantSlug) url.searchParams.set('tenant_slug', route.tenantSlug);
    console.log(`>>> TENANT REWRITE: ${subdomain ?? 'bare host'}${pathname} -> ${url.pathname}`);

    const rewriteResponse = NextResponse.rewrite(url, {
      request: { headers: requestHeaders },
    });
    copyAuthCookies(response, rewriteResponse);
    return rewriteResponse;
  }

  console.log(`>>> ${subdomain ? `ACCOUNT NEXT: ${subdomain}` : 'MAIN DOMAIN:'}${pathname}`);
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
