import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { createServiceClient } from '@/lib/supabase/service';
import { readBody } from '@/lib/api/admin-rpc';
import { requireStaff, toInt } from '@/lib/api/nav';
import { sendEmail } from '@/lib/email/send';
import { acceptLink, accessEmail, defaultFromAddress, inviteEmail, linkOrigin, type Sender } from '@/lib/email/user-emails';

export const dynamic = 'force-dynamic';

interface Prepared extends Sender {
  email: string; user_name: string | null; user_type: string; auth_user_id: string | null; signed_in: boolean; tenant_name: string; tenant_slug: string | null;
}

/**
 * POST /api/admin/users/invite { tenant_id, user_id } → { sent, email, link? }
 * Someone who never signed in gets a link to choose a password (the first invite also creates their login);
 * someone who already has a login just gets told where to sign in. When email is not set up, nothing is sent and
 * the link comes back so it can be passed on by hand.
 */
export async function POST(request: Request) {
  const body = await readBody(request);
  const tenantId = toInt(body?.tenant_id);
  const userId = toInt(body?.user_id);
  if (tenantId === null || userId === null) return NextResponse.json({ error: 'tenant_id and user_id are required' }, { status: 400 });
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;

  const db = createClient();
  const { data, error } = await db.rpc('fnd_user_invite_prepare', { p_tenant_id: tenantId, p_user_id: userId });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  const u = data as Prepared;
  const origin = linkOrigin(request, u.tenant_slug);
  const who = { to: u.email, userName: u.user_name, tenantName: u.tenant_name, sender: u, fallbackAddress: defaultFromAddress(), customer: u.user_type === 'CUSTOMER_USER' };

  let authUserId = u.auth_user_id;
  let link: string;
  let email;
  if (u.signed_in && authUserId) {
    link = `${origin}/login`;
    email = accessEmail(who, link);
  } else {
    const admin = createServiceClient().auth.admin;
    // A new person: create their login with an invite token. Their login may already exist (an earlier invite,
    // or a login made elsewhere) — then a recovery token lets them choose a password the same way.
    let gen = authUserId ? null : await admin.generateLink({ type: 'invite', email: u.email });
    let type: 'invite' | 'recovery' = 'invite';
    if (!gen || gen.error) {
      if (gen?.error && gen.error.code !== 'email_exists' && !/already been registered/i.test(gen.error.message)) {
        return NextResponse.json({ error: gen.error.message }, { status: 400 });
      }
      gen = await admin.generateLink({ type: 'recovery', email: u.email });
      type = 'recovery';
      if (gen.error) return NextResponse.json({ error: gen.error.message }, { status: 400 });
    }
    authUserId = gen.data.user.id;
    link = acceptLink(origin, gen.data.properties.hashed_token, type);
    email = inviteEmail(who, link);
  }

  const rec = await db.rpc('fnd_user_invite_record', { p_tenant_id: tenantId, p_user_id: userId, p_auth_user_id: authUserId });
  if (rec.error) return NextResponse.json({ error: rec.error.message }, { status: 400 });

  const result = await sendEmail(email);
  return NextResponse.json({
    data: { sent: result.sent, email: u.email, ...(result.sent ? {} : { link, reason: result.error }) },
  });
}
