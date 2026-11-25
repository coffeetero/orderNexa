import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * POST /api/customers/import/:id { tenant_id, action: 'apply' }
 *      → checks the rows again and inserts the new / updates the changed customers (fnd_customer_import_apply)
 */
export async function POST(request: Request, { params }: { params: { id: string } }) {
  const id = toInt(params.id);
  const body = await readBody(request);
  if (id === null || !body) return NextResponse.json({ error: 'Invalid request' }, { status: 400 });
  if (body.action !== 'apply') return NextResponse.json({ error: "action must be 'apply'" }, { status: 400 });
  return adminRpc(body.tenant_id, 'fnd_customer_import_apply', { p_customer_import_id: id });
}
