/**
 * Returns the tenant subdomain label from the Host header, or null on apex / www / bare localhost.
 * Matches middleware routing rules.
 */
export function parseTenantSubdomain(host: string): string | null {
  const hostname = host.split(':')[0];
  // 127.0.0.1 / other IPv4 literals have no tenant subdomain (would otherwise parse as "127").
  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(hostname)) return null;
  const parts = hostname.split('.');
  const subdomain =
    parts.length > (hostname.includes('localhost') ? 1 : 2) ? parts[0] : null;

  if (!subdomain || subdomain === 'www' || subdomain === 'localhost') {
    return null;
  }

  return subdomain;
}
