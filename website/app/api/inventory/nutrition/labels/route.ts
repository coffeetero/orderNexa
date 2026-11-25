import { NextResponse } from 'next/server';
import { adminRpc } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/** GET /api/inventory/nutrition/labels?tenant_id=n&item_ids=1,2,3 → labels to print (inv_nutrition_labels_get) */
export async function GET(request: Request) {
  const q = new URL(request.url).searchParams;
  const ids = (q.get('item_ids') ?? '').split(',').filter(Boolean).map(toInt);
  if (ids.length === 0 || ids.some((n) => n === null)) return NextResponse.json({ error: 'item_ids is required' }, { status: 400 });
  return adminRpc(q.get('tenant_id'), 'inv_nutrition_labels_get', { p_item_ids: ids });
}
