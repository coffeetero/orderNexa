import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/** POST /api/pricebooks/items { tenant_id, pricebook_id, entries: [{item_id, item_price, is_active?, remove?}] } → number of entries applied */
export async function POST(request: Request) {
  const body = await readBody(request);
  const id = toInt(body?.pricebook_id);
  if (!body || id === null || !Array.isArray(body.entries)) return NextResponse.json({ error: 'pricebook_id and entries are required' }, { status: 400 });
  return adminRpc(body.tenant_id, 'fnd_pricebook_items_set', { p_pricebook_id: id, p_entries: body.entries });
}
