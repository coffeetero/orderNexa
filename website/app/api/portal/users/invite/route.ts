import { NextResponse } from 'next/server';
import { getSessionUser } from '@/lib/supabase/server';
import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { readBody } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';
import { sendUserInvite } from '@/lib/api/user-invite';

export const dynamic = 'force-dynamic';

/** POST /api/portal/users/invite { user_id } → { data: { sent, email, link? } }: a customer administrator invites one of their users. */
export async function POST(request: Request) {
  if (!(await getSessionUser())) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  const tenantId = await getCurrentTenantId();
  const body = await readBody(request);
  const userId = toInt(body?.user_id);
  if (tenantId === null || userId === null) return NextResponse.json({ error: 'user_id is required' }, { status: 400 });
  return sendUserInvite(request, tenantId, userId);
}
