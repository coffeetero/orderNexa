import { NextResponse } from 'next/server';
import { requireStaff } from '@/lib/api/nav';
import { readBody } from '@/lib/api/admin-rpc';
import { getSessionUser } from '@/lib/supabase/server';
import { createServiceClient } from '@/lib/supabase/service';
import { sendEmail } from '@/lib/email/send';
import { defaultFromAddress, emailChangeEmail, linkOrigin } from '@/lib/email/user-emails';
import { emailChangeSecret, isEmail, makeEmailChangeToken } from '@/lib/email/email-change-token';

export const dynamic = 'force-dynamic';

const OUR_SENDER = { sender_name: null, sender_address: null, reply_to: null };

/**
 * POST /api/profile/email { email } → { data: { sent, email } }
 * The signed-in staff member asks to sign in with a new email. A confirmation link goes to the NEW address; nothing
 * changes until it is opened (/auth/confirm-email). The new address must not belong to another BPS user.
 * Without email set up (local development) the link comes back in the answer instead; never on a production server.
 */
export async function POST(request: Request) {
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;
  const user = await getSessionUser();
  if (!user?.email) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const body = await readBody(request);
  const next = typeof body?.email === 'string' ? body.email.trim() : '';
  if (!isEmail(next)) return NextResponse.json({ error: 'Enter a valid email address.' }, { status: 400 });
  if (next.toLowerCase() === user.email.toLowerCase()) return NextResponse.json({ error: 'That is already your email.' }, { status: 400 });

  const svc = createServiceClient();
  const free = await svc.rpc('fnd_email_available', { p_email: next, p_auth_user_id: user.id });
  if (free.error) return NextResponse.json({ error: 'The address could not be checked. Try again.' }, { status: 500 });
  if (free.data !== true) return NextResponse.json({ error: 'Another user already signs in with that address.' }, { status: 409 });

  const me = await svc.from('fnd_users').select('user_name').eq('auth_user_id', user.id).limit(1).maybeSingle();
  const token = makeEmailChangeToken({ uid: user.id, from: user.email, to: next }, emailChangeSecret());
  const link = `${linkOrigin(request, null)}/auth/confirm-email?token=${encodeURIComponent(token)}`;
  const result = await sendEmail(emailChangeEmail(
    { to: next, userName: me.data?.user_name ?? null, tenantName: 'OrderNexa', sender: OUR_SENDER, fallbackAddress: defaultFromAddress() }, link));
  if (!result.sent && process.env.NODE_ENV === 'production') {
    return NextResponse.json({ error: 'The confirmation email could not be sent. Try again later.' }, { status: 502 });
  }
  return NextResponse.json({ data: { sent: result.sent, email: next, ...(result.sent ? {} : { link }) } });
}
