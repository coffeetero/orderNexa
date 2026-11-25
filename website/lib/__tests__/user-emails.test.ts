import { describe, expect, it } from 'vitest';
import { acceptLink, accessEmail, fromHeader, inviteEmail, requestOrigin, resetEmail, tenantOrigin, type Sender } from '@/lib/email/user-emails';
import { isTenantFreePath } from '@/lib/tenant-session';

const alpine: Sender = { sender_name: 'Alpine Bakery', sender_address: 'orders@alpinebakerynj.com', reply_to: 'office@alpinebakerynj.com' };
const who = (sender = alpine) => ({ to: 'buyer@example.com', userName: 'Pat <Buyer>', tenantName: 'Alpine Bakery', sender, fallbackAddress: 'invites@ordernexa.com' });

describe('fromHeader', () => {
  it("uses the tenancy's own address when it has one", () => {
    expect(fromHeader(alpine, 'invites@ordernexa.com')).toBe('"Alpine Bakery" <orders@alpinebakerynj.com>');
  });
  it("falls back to OrderNexa's address under the tenancy's name", () => {
    expect(fromHeader({ ...alpine, sender_address: null }, 'invites@ordernexa.com')).toBe('"Alpine Bakery" <invites@ordernexa.com>');
  });
  it('strips characters that could break the header', () => {
    expect(fromHeader({ sender_name: 'A"B\r\nBcc: x', sender_address: null, reply_to: null }, 'i@o.com')).toBe('"ABBcc: x" <i@o.com>');
  });
});

describe('emails', () => {
  const link = acceptLink('https://alpine-bakery.ordernexa.com', 'abc+/=', 'invite');
  it('builds our own accept link with the token encoded', () => {
    expect(link).toBe('https://alpine-bakery.ordernexa.com/auth/accept?type=invite&token_hash=abc%2B%2F%3D');
  });
  it('invite carries the link, the reply-to and escapes names in html', () => {
    const e = inviteEmail(who(), link);
    expect(e.from).toBe('"Alpine Bakery" <orders@alpinebakerynj.com>');
    expect(e.replyTo).toBe('office@alpinebakerynj.com');
    expect(e.subject).toContain('Alpine Bakery');
    expect(e.text).toContain(link);
    expect(e.html).toContain('Pat &lt;Buyer&gt;');
    expect(e.html).not.toContain('<Buyer>');
  });
  it('omits reply-to when the tenancy has none, and does not greet by an email address', () => {
    const e = resetEmail({ ...who({ sender_name: 'OrderNexa', sender_address: null, reply_to: null }), userName: 'pat@example.com' }, link);
    expect(e.replyTo).toBeUndefined();
    expect(e.text.startsWith('Hello,')).toBe(true);
  });
  it("never names OrderNexa in a customer's email, but does for staff", () => {
    const customer = { ...who(), customer: true };
    const own = 'https://bps.alpinebakerynj.com/auth/accept?type=invite&token_hash=abc';   // wording only; the link is whatever address the site is on
    for (const e of [inviteEmail(customer, own), accessEmail(customer, 'https://x/login'), resetEmail(customer, own)]) {
      expect(`${e.subject} ${e.text} ${e.html}`).not.toMatch(/ordernexa/i);
      expect(e.subject).toContain('Alpine Bakery');
    }
    const staff = { ...who({ sender_name: 'OrderNexa', sender_address: null, reply_to: null }), userName: 'Pat' };
    expect(inviteEmail(staff, 'https://x/a').subject).toContain('OrderNexa');
  });
  it('access email points at sign in, with no token', () => {
    const e = accessEmail(who(), 'https://x/login');
    expect(e.text).toContain('https://x/login');
    expect(e.text).not.toContain('token_hash');
  });
});

describe('requestOrigin', () => {
  it('keeps the tenant subdomain from the Host header', () => {
    const r = new Request('http://localhost:3000/api/x', { headers: { host: 'alpine-bakery.localhost:3000' } });
    expect(requestOrigin(r)).toBe('http://alpine-bakery.localhost:3000');
  });
  it('prefers the proxy headers', () => {
    const r = new Request('http://10.0.0.1/api/x', { headers: { host: '10.0.0.1', 'x-forwarded-host': 'alpine-bakery.ordernexa.com', 'x-forwarded-proto': 'https' } });
    expect(requestOrigin(r)).toBe('https://alpine-bakery.ordernexa.com');
  });
});

describe('tenantOrigin', () => {
  it('puts the tenancy in front of the configured site address', () => {
    expect(tenantOrigin('https://ordernexa.com', 'alpine-bakery')).toBe('https://alpine-bakery.ordernexa.com');
    expect(tenantOrigin('http://localhost:3000/', 'alpine-bakery')).toBe('http://alpine-bakery.localhost:3000');
    expect(tenantOrigin('https://ordernexa.com', null)).toBe('https://ordernexa.com');
  });
});

describe('isTenantFreePath', () => {
  it('lets invite and reset pages through without a tenancy', () => {
    expect(isTenantFreePath('/auth/accept')).toBe(true);
    expect(isTenantFreePath('/forgot-password')).toBe(true);
    expect(isTenantFreePath('/authors')).toBe(false);
    expect(isTenantFreePath('/dashboard')).toBe(false);
  });
});
