import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/** POST /api/inventory/nutrition/copy { tenant_id, from_item_id, to_item_id } → copies a profile onto another item as a draft */
export async function POST(request: Request) {
  const body = await readBody(request);
  const from = toInt(body?.from_item_id);
  const to = toInt(body?.to_item_id);
  if (!body || from === null || to === null) return NextResponse.json({ error: 'from_item_id and to_item_id are required' }, { status: 400 });
  return adminRpc(body.tenant_id, 'inv_item_nutrition_copy', { p_from_item_id: from, p_to_item_id: to });
}
