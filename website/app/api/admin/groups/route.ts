import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * GET    /api/admin/groups?tenant_id=n              → customer groups
 * GET    /api/admin/groups?tenant_id=n&options=1    → top-level customers for the picker
 * POST   /api/admin/groups { tenant_id, group: {group_id?, group_name, is_active, customer_ids: []} } → group_id
 * DELETE /api/admin/groups?tenant_id=n&group_id=n
 */
export async function GET(request: Request) {
  const q = new URL(request.url).searchParams;
  return adminRpc(q.get('tenant_id'), q.get('options') ? 'fnd_customer_options_get' : 'fnd_customer_groups_get', {});
}

export async function POST(request: Request) {
  const body = await readBody(request);
  if (!body || typeof body.group !== 'object') return NextResponse.json({ error: 'group is required' }, { status: 400 });
  return adminRpc(body.tenant_id, 'fnd_customer_group_save', { p_payload: body.group });
}

export async function DELETE(request: Request) {
  const q = new URL(request.url).searchParams;
  const groupId = toInt(q.get('group_id'));
  if (groupId === null) return NextResponse.json({ error: 'group_id is required' }, { status: 400 });
  return adminRpc(q.get('tenant_id'), 'fnd_customer_group_delete', { p_group_id: groupId });
}
