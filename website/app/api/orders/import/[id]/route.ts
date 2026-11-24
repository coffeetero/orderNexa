import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * POST   /api/orders/import/:id { tenant_id, action: 'approve' } → approves the import; its orders join production (om_order_import_approve)
 * DELETE /api/orders/import/:id?tenant_id=n                      → deletes a not-approved import and its orders (om_order_import_delete)
 */
export async function POST(request: Request, { params }: { params: { id: string } }) {
  const id = toInt(params.id);
  const body = await readBody(request);
  if (id === null || !body) return NextResponse.json({ error: 'Invalid request' }, { status: 400 });
  if (body.action !== 'approve') return NextResponse.json({ error: "action must be 'approve'" }, { status: 400 });
  return adminRpc(body.tenant_id, 'om_order_import_approve', { p_order_import_id: id });
}

export async function DELETE(request: Request, { params }: { params: { id: string } }) {
  const id = toInt(params.id);
  if (id === null) return NextResponse.json({ error: 'Invalid id' }, { status: 400 });
  return adminRpc(new URL(request.url).searchParams.get('tenant_id'), 'om_order_import_delete', { p_order_import_id: id });
}
