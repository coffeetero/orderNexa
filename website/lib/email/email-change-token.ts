import { createHmac, timingSafeEqual } from 'crypto';

/**
 * The signed link that confirms a change of sign-in email (Profile › Change email). Stateless: the link carries who, from
 * which address, to which address and until when, signed with a server-only key, so no table is needed. It only works
 * while the account still has the old address, so it cannot be replayed after a later change. Valid 24 hours.
 */
export interface EmailChange { uid: string; from: string; to: string; exp: number }

export const EMAIL_CHANGE_HOURS = 24;
const b64 = (s: Buffer | string) => Buffer.from(s).toString('base64url');
const sign = (payload: string, secret: string) => createHmac('sha256', `bps-email-change:${secret}`).update(payload).digest('base64url');

export function makeEmailChangeToken(c: Omit<EmailChange, 'exp'>, secret: string, now = Date.now()): string {
  const payload = b64(JSON.stringify({ ...c, exp: now + EMAIL_CHANGE_HOURS * 3_600_000 }));
  return `${payload}.${sign(payload, secret)}`;
}

/** The change a token asks for, or null when it is malformed, tampered with or expired. */
export function readEmailChangeToken(token: string, secret: string, now = Date.now()): EmailChange | null {
  const [payload, sig, extra] = (token || '').split('.');
  if (!payload || !sig || extra !== undefined || !secret) return null;
  const want = Buffer.from(sign(payload, secret));
  const got = Buffer.from(sig);
  if (want.length !== got.length || !timingSafeEqual(want, got)) return null;
  try {
    const c = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')) as EmailChange;
    if (typeof c.uid !== 'string' || typeof c.from !== 'string' || typeof c.to !== 'string' || typeof c.exp !== 'number') return null;
    return c.exp > now ? c : null;
  } catch { return null; }
}

/** The key: SUPABASE_SERVICE_ROLE_KEY already exists on every server and never reaches the browser. */
export const emailChangeSecret = () => process.env.SUPABASE_SERVICE_ROLE_KEY || '';

export const isEmail = (v: string) => /^[^\s@<>"]+@[^\s@<>"]+\.[^\s@<>"]+$/.test(v) && v.length <= 254;
