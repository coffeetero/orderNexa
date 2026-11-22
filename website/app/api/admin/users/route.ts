import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * GET  /api/admin/users?tenant_id=n → users of the tenancy with their role and group ids
 * POST /api/admin/users { tenant_id, user_id, role_ids: [], group_ids: [], is_active }
 */
export async function GET(request: Request) {
  return adminRpc(new URL(request.url).searchParams.get('tenant_id'), 'fnd_users_get', {});
}

export async function POST(request: Request) {
  const body = await readBody(request);
  const userId = toInt(body?.user_id);
  if (!body || userId === null) return NextResponse.json({ error: 'user_id is required' }, { status: 400 });
  const ids = (v: unknown) => (Array.isArray(v) ? v.map(toInt).filter((n): n is number => n !== null) : []);
  return adminRpc(body.tenant_id, 'fnd_user_access_save', {
    p_user_id: userId,
    p_role_ids: ids(body.role_ids),
    p_group_ids: ids(body.group_ids),
    p_is_active: body.is_active !== false,
  });
}
