import { NextResponse } from 'next/server';
import { headers } from 'next/headers';
import { createServiceClient } from '@/lib/supabase/service';
import { parseTenantSubdomain } from '@/lib/tenant-subdomain';
import { sendEmail } from '@/lib/email/send';
import { acceptLink, defaultFromAddress, requestOrigin, resetEmail, type Sender } from '@/lib/email/user-emails';

export const dynamic = 'force-dynamic';

interface ResetTarget extends Sender { email: string; user_name: string | null; tenant_name: string }

/**
 * POST /api/auth/forgot { email } → always { ok: true }, so the page never reveals whether an email has an account.
 * An active user with a login gets a link to choose a new password, from their bakery (customers) or OrderNexa (staff).
 */
export async function POST(request: Request) {
  const body = await request.json().catch(() => ({}));
  const emailAddr = typeof body?.email === 'string' ? body.email.trim() : '';
  if (!emailAddr) return NextResponse.json({ error: 'Email is required' }, { status: 400 });

  const svc = createServiceClient();
  const { data, error } = await svc.rpc('fnd_user_reset_prepare', {
    p_email: emailAddr, p_host_slug: parseTenantSubdomain(headers().get('host') || ''),
  });
  if (error) console.error('[forgot] lookup failed:', error.message);
  const t = data as ResetTarget | null;
  if (t) {
    const gen = await svc.auth.admin.generateLink({ type: 'recovery', email: t.email });
    if (gen.error) {
      console.error('[forgot] link failed:', gen.error.message);
    } else {
      const link = acceptLink(requestOrigin(request),gen.data.properties.hashed_token, 'recovery');
      const result = await sendEmail(resetEmail(
        { to: t.email, userName: t.user_name, tenantName: t.tenant_name, sender: t, fallbackAddress: defaultFromAddress() }, link));
      if (!result.sent) {
        console.error('[forgot] not sent:', result.error);
        if (process.env.NODE_ENV !== 'production') console.info('[forgot] dev link:', link);
      }
    }
  }
  return NextResponse.json({ ok: true });
}
