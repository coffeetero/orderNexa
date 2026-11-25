import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/** POST /api/inventory/nutrition/approve { tenant_id, item_id, approve } → approves the label, or (approve false) puts it back to draft */
export async function POST(request: Request) {
  const body = await readBody(request);
  const id = toInt(body?.item_id);
  if (!body || id === null) return NextResponse.json({ error: 'item_id is required' }, { status: 400 });
  return adminRpc(body.tenant_id, 'inv_item_nutrition_approve', { p_item_id: id, p_approve: body.approve !== false });
}
