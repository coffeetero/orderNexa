import { NextResponse } from 'next/server';
import { readBody } from '@/lib/api/admin-rpc';
import { createServiceClient } from '@/lib/supabase/service';
import { sendEmail } from '@/lib/email/send';
import { defaultFromAddress, emailChangedNotice, linkOrigin } from '@/lib/email/user-emails';
import { emailChangeSecret, readEmailChangeToken } from '@/lib/email/email-change-token';

export const dynamic = 'force-dynamic';

const OUR_SENDER = { sender_name: null, sender_address: null, reply_to: null };

/**
 * POST /api/profile/email/confirm { token } → { data: { email } }
 * Opened from the link sent to the new address, signed in or not (opening it proves the new mailbox is theirs). Changes
 * the sign-in email (the trigger fnd_user_email_sync updates fnd_users), then tells the OLD address. A link whose account
 * no longer has the old address (changed again since) does nothing.
 */
export async function POST(request: Request) {
  const body = await readBody(request);
  const change = readEmailChangeToken(typeof body?.token === 'string' ? body.token : '', emailChangeSecret());
  if (!change) return NextResponse.json({ error: 'This link has expired or is not valid. Ask for a new one from your profile.' }, { status: 400 });

  const svc = createServiceClient();
  const got = await svc.auth.admin.getUserById(change.uid);
  const current = got.data.user?.email ?? '';
  if (got.error || !current) return NextResponse.json({ error: 'This link is not valid.' }, { status: 400 });
  if (current.toLowerCase() === change.to.toLowerCase()) return NextResponse.json({ data: { email: change.to, already: true } });
  if (current.toLowerCase() !== change.from.toLowerCase()) {
    return NextResponse.json({ error: 'Your email has changed since this link was sent, so it no longer applies.' }, { status: 409 });
  }

  const free = await svc.rpc('fnd_email_available', { p_email: change.to, p_auth_user_id: change.uid });
  if (free.error || free.data !== true) return NextResponse.json({ error: 'Another user already signs in with that address.' }, { status: 409 });

  const upd = await svc.auth.admin.updateUserById(change.uid, { email: change.to, email_confirm: true });
  if (upd.error) return NextResponse.json({ error: 'The email could not be changed. Try again, or ask your administrator.' }, { status: 500 });

  const me = await svc.from('fnd_users').select('user_name').eq('auth_user_id', change.uid).limit(1).maybeSingle();
  const notice = await sendEmail(emailChangedNotice(
    { to: change.from, userName: me.data?.user_name ?? null, tenantName: 'OrderNexa', sender: OUR_SENDER, fallbackAddress: defaultFromAddress() },
    change.to, `${linkOrigin(request, null)}/login`));
  if (!notice.sent) console.error('[email-change] notice to the old address was not sent:', notice.error);
  return NextResponse.json({ data: { email: change.to } });
}
