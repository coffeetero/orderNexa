import { describe, expect, it } from 'vitest';
import { parseTenantSubdomain } from '@/lib/tenant-subdomain';

describe('parseTenantSubdomain', () => {
  it('returns the tenant label on tenant hosts', () => {
    expect(parseTenantSubdomain('alpine-bakery.localhost:3000')).toBe('alpine-bakery');
    expect(parseTenantSubdomain('alpine.ordernexa.com')).toBe('alpine');
  });
  it('returns null for apex, www and bare localhost', () => {
    expect(parseTenantSubdomain('localhost:3000')).toBeNull();
    expect(parseTenantSubdomain('ordernexa.com')).toBeNull();
    expect(parseTenantSubdomain('www.ordernexa.com')).toBeNull();
  });
  it('does not treat IPv4 literals as a tenant (regression: 127.0.0.1 parsed as "127")', () => {
    expect(parseTenantSubdomain('127.0.0.1:3000')).toBeNull();
    expect(parseTenantSubdomain('192.168.1.20')).toBeNull();
  });
});
