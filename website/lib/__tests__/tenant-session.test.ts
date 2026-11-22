import { describe, expect, it } from 'vitest';
import { checkTenantSession, decodeTenantClaims, isTenantFreePath } from '../tenant-session';

function token(app_metadata: object) {
  const b64 = (o: object) => Buffer.from(JSON.stringify(o)).toString('base64url');
  return `${b64({ alg: 'none' })}.${b64({ app_metadata })}.sig`;
}

describe('checkTenantSession', () => {
  it('sends a session without a tenant claim to the picker', () => {
    expect(checkTenantSession(null, null)).toBe('select');
    expect(checkTenantSession({}, 'alpine-bakery')).toBe('select');
    expect(checkTenantSession({ tenant_id: null }, null)).toBe('select');
  });
  it('accepts a matching tenant address or a bare host', () => {
    expect(checkTenantSession({ tenant_id: 1, tenant_slug: 'alpine-bakery' }, 'alpine-bakery')).toBe('ok');
    expect(checkTenantSession({ tenant_id: 1, tenant_slug: 'alpine-bakery' }, null)).toBe('ok');
  });
  it('rejects a session for another tenant than the address', () => {
    expect(checkTenantSession({ tenant_id: 1, tenant_slug: 'alpine-bakery' }, 'other-bakery')).toBe('select');
  });
});

describe('decodeTenantClaims', () => {
  it('reads app_metadata and survives garbage', () => {
    expect(decodeTenantClaims(token({ tenant_id: 5, tenant_slug: 'x' }))).toEqual({ tenant_id: 5, tenant_slug: 'x' });
    expect(decodeTenantClaims('nope')).toBeNull();
    expect(decodeTenantClaims(null)).toBeNull();
  });
});

describe('isTenantFreePath', () => {
  it('lets public pages and the picker through', () => {
    expect(isTenantFreePath('/')).toBe(true);
    expect(isTenantFreePath('/login')).toBe(true);
    expect(isTenantFreePath('/select-tenant')).toBe(true);
    expect(isTenantFreePath('/dashboard')).toBe(false);
    expect(isTenantFreePath('/alpine-account/orders')).toBe(false);
  });
});
