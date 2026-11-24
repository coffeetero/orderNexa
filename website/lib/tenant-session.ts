/**
 * Decides whether a signed-in session may proceed, based on the tenancy claims in its access token.
 * Pure so it can be unit-tested; used by middleware.ts. The claims are written by bps_access_token_hook.
 */
export type TenantClaims = { tenant_id?: number | string | null; tenant_slug?: string | null };

/** 'ok' = proceed; 'select' = send the user to the tenancy picker. */
export function checkTenantSession(claims: TenantClaims | null, hostSubdomain: string | null): 'ok' | 'select' {
  if (!claims || claims.tenant_id == null || claims.tenant_id === '') return 'select';
  // On a tenant address the session must belong to that same tenancy.
  if (hostSubdomain && claims.tenant_slug && claims.tenant_slug !== hostSubdomain) return 'select';
  return 'ok';
}

/** Reads app_metadata from a JWT without verifying it (the caller already validated the session with getUser). */
export function decodeTenantClaims(accessToken: string | null | undefined): TenantClaims | null {
  if (!accessToken) return null;
  try {
    const payload = accessToken.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
    const json = JSON.parse(atob(payload.padEnd(payload.length + ((4 - (payload.length % 4)) % 4), '=')));
    return (json.app_metadata ?? {}) as TenantClaims;
  } catch {
    return null;
  }
}

/** Paths that never need a tenancy (public pages, the picker itself, and accepting an invite / resetting a password). */
export function isTenantFreePath(pathname: string): boolean {
  return pathname === '/' || pathname === '/login' || pathname === '/forgot-password' || pathname === '/select-tenant'
    || pathname.startsWith('/select-tenant/') || pathname.startsWith('/auth/');
}
