import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';

export const dynamic = 'force-dynamic';

/**
 * GET  /api/admin/email-sender?tenant_id=n → { tenant_name, email_from_address, email_reply_to }
 * POST /api/admin/email-sender { tenant_id, email_from_address, email_reply_to }
 */
export async function GET(request: Request) {
  return adminRpc(new URL(request.url).searchParams.get('tenant_id'), 'fnd_tenant_email_get', {});
}

export async function POST(request: Request) {
  const body = await readBody(request);
  if (!body) return NextResponse.json({ error: 'Invalid body' }, { status: 400 });
  const text = (v: unknown) => (typeof v === 'string' ? v : '');
  return adminRpc(body.tenant_id, 'fnd_tenant_email_save', {
    p_email_from_address: text(body.email_from_address),
    p_email_reply_to: text(body.email_reply_to),
  });
}
