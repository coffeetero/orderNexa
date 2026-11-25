import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * GET    /api/inventory/nutrition?tenant_id=n             → items with label status (inv_item_nutrition_list_get)
 * GET    /api/inventory/nutrition?tenant_id=n&item_id=n   → one item's profile and computed label (inv_item_nutrition_get)
 * POST   /api/inventory/nutrition { tenant_id, profile }  → saves the profile as a draft (inv_item_nutrition_save)
 * DELETE /api/inventory/nutrition?tenant_id=n&item_id=n   → deletes the profile (inv_item_nutrition_delete)
 */
export async function GET(request: Request) {
  const q = new URL(request.url).searchParams;
  if (!q.has('item_id')) return adminRpc(q.get('tenant_id'), 'inv_item_nutrition_list_get', {});
  const id = toInt(q.get('item_id'));
  if (id === null) return NextResponse.json({ error: 'Invalid item_id' }, { status: 400 });
  return adminRpc(q.get('tenant_id'), 'inv_item_nutrition_get', { p_item_id: id });
}

export async function POST(request: Request) {
  const body = await readBody(request);
  if (!body || typeof body.profile !== 'object' || body.profile === null) return NextResponse.json({ error: 'profile is required' }, { status: 400 });
  return adminRpc(body.tenant_id, 'inv_item_nutrition_save', { p_payload: body.profile });
}

export async function DELETE(request: Request) {
  const q = new URL(request.url).searchParams;
  const id = toInt(q.get('item_id'));
  if (id === null) return NextResponse.json({ error: 'Invalid item_id' }, { status: 400 });
  return adminRpc(q.get('tenant_id'), 'inv_item_nutrition_delete', { p_item_id: id });
}
