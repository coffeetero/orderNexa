import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * GET    /api/admin/roles?tenant_id=n                         → roles
 * GET    /api/admin/roles?tenant_id=n&access=1&role_id=n      → access matrix of a role (or &audience=TENANT|CUSTOMER for a new one)
 * POST   /api/admin/roles { tenant_id, role: {role_id?, role_name, role_audience, is_active, access: [...]} } → role_id
 * DELETE /api/admin/roles?tenant_id=n&role_id=n
 */
export async function GET(request: Request) {
  const q = new URL(request.url).searchParams;
  if (q.get('access')) {
    const audience = q.get('audience') === 'CUSTOMER' ? 'CUSTOMER' : 'TENANT';
    return adminRpc(q.get('tenant_id'), 'fnd_role_access_get', { p_role_id: toInt(q.get('role_id')), p_audience: audience });
  }
  return adminRpc(q.get('tenant_id'), 'fnd_roles_get', {});
}

export async function POST(request: Request) {
  const body = await readBody(request);
  if (!body || typeof body.role !== 'object') return NextResponse.json({ error: 'role is required' }, { status: 400 });
  return adminRpc(body.tenant_id, 'fnd_role_save', { p_payload: body.role });
}

export async function DELETE(request: Request) {
  const q = new URL(request.url).searchParams;
  const roleId = toInt(q.get('role_id'));
  if (roleId === null) return NextResponse.json({ error: 'role_id is required' }, { status: 400 });
  return adminRpc(q.get('tenant_id'), 'fnd_role_delete', { p_role_id: roleId });
}
