import { describe, expect, it } from 'vitest';
import { isEmail, makeEmailChangeToken, readEmailChangeToken } from '@/lib/email/email-change-token';
import { emailChangeEmail, emailChangedNotice } from '@/lib/email/user-emails';

const c = { uid: '9b9b43b7-5a4c-4cbd-b5f4-b0585cbc393b', from: 'old@example.com', to: 'new@example.com' };
const T0 = 1_800_000_000_000;

describe('email change token', () => {
  it('round-trips while fresh', () => {
    const t = makeEmailChangeToken(c, 'secret', T0);
    expect(readEmailChangeToken(t, 'secret', T0 + 60_000)).toMatchObject(c);
  });
  it('expires after 24 hours', () => {
    const t = makeEmailChangeToken(c, 'secret', T0);
    expect(readEmailChangeToken(t, 'secret', T0 + 24 * 3_600_000 + 1)).toBeNull();
  });
  it('refuses another key, a changed payload and junk', () => {
    const t = makeEmailChangeToken(c, 'secret', T0);
    expect(readEmailChangeToken(t, 'other', T0)).toBeNull();
    const [, sig] = t.split('.');
    const forged = Buffer.from(JSON.stringify({ ...c, to: 'attacker@example.com', exp: T0 + 1e9 })).toString('base64url');
    expect(readEmailChangeToken(`${forged}.${sig}`, 'secret', T0)).toBeNull();
    for (const junk of ['', 'x', 'a.b', `${t}.extra`]) expect(readEmailChangeToken(junk, 'secret', T0)).toBeNull();
    expect(readEmailChangeToken(t, '', T0)).toBeNull();
  });
  it('checks email shape', () => {
    expect(isEmail('moraglen@ordernexa.com')).toBe(true);
    for (const bad of ['', 'moraglen', 'a@b', 'a b@c.com', '<a@b.com>']) expect(isEmail(bad)).toBe(false);
  });
});

describe('email change emails', () => {
  const who = { to: 'new@example.com', userName: 'Glen', tenantName: 'OrderNexa', sender: { sender_name: null, sender_address: null, reply_to: null }, fallbackAddress: 'invites@ordernexa.com' };
  it('confirmation goes to the new address with the link', () => {
    const e = emailChangeEmail(who, 'https://x/auth/confirm-email?token=abc');
    expect(e.to).toBe('new@example.com');
    expect(e.text).toContain('https://x/auth/confirm-email?token=abc');
    expect(e.from).toBe('"OrderNexa" <invites@ordernexa.com>');
    expect(e.text).toMatch(/PASSWORD STAYS THE SAME/);
  });
  it('notice names the new address and says to contact the administrator', () => {
    const e = emailChangedNotice({ ...who, to: 'old@example.com' }, 'new@example.com', 'https://x/login');
    expect(e.to).toBe('old@example.com');
    expect(e.text).toContain('new@example.com');
    expect(e.text).toMatch(/administrator/);
  });
});
