import { NextResponse } from 'next/server';
import { readBody } from '@/lib/api/admin-rpc';
import { requireStaff, toInt } from '@/lib/api/nav';
import { sendUserInvite } from '@/lib/api/user-invite';

export const dynamic = 'force-dynamic';

/** POST /api/admin/users/invite { tenant_id, user_id } → { data: { sent, email, link? } } (see lib/api/user-invite.ts) */
export async function POST(request: Request) {
  const body = await readBody(request);
  const tenantId = toInt(body?.tenant_id);
  const userId = toInt(body?.user_id);
  if (tenantId === null || userId === null) return NextResponse.json({ error: 'tenant_id and user_id are required' }, { status: 400 });
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;
  return sendUserInvite(request, tenantId, userId);
}
