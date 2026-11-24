import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/** POST /api/admin/users/create { tenant_id, email, user_name, user_type, customer_id?, role_ids, group_ids } → { data: user_id } */
export async function POST(request: Request) {
  const body = await readBody(request);
  if (!body) return NextResponse.json({ error: 'Invalid body' }, { status: 400 });
  const ids = (v: unknown) => (Array.isArray(v) ? v.map(toInt).filter((n): n is number => n !== null) : []);
  return adminRpc(body.tenant_id, 'fnd_user_create', {
    p_email: typeof body.email === 'string' ? body.email : '',
    p_user_name: typeof body.user_name === 'string' ? body.user_name : '',
    p_user_type: typeof body.user_type === 'string' ? body.user_type : '',
    p_customer_id: toInt(body.customer_id),
    p_role_ids: ids(body.role_ids),
    p_group_ids: ids(body.group_ids),
  });
}
