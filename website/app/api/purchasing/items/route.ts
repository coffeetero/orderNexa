import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * GET    /api/purchasing/items?tenant_id=n[&vendor_id=n]   → vendor items, all or one vendor's (po_vendor_items_get)
 * GET    /api/purchasing/items?tenant_id=n&prices=n        → price history of one item (po_vendor_item_prices_get)
 * GET    /api/purchasing/items?tenant_id=n&options=1       → vendor and ingredient pick lists (po_options_get)
 * POST   /api/purchasing/items { tenant_id, item }         → creates or saves an item (po_vendor_item_save)
 * DELETE /api/purchasing/items?tenant_id=n&id=n            → deletes an item and its price history (po_vendor_item_delete)
 */
export async function GET(request: Request) {
  const q = new URL(request.url).searchParams;
  const tenant = q.get('tenant_id');
  if (q.get('options')) return adminRpc(tenant, 'po_options_get', {});
  if (q.has('prices')) {
    const id = toInt(q.get('prices'));
    if (id === null) return NextResponse.json({ error: 'Invalid item id' }, { status: 400 });
    return adminRpc(tenant, 'po_vendor_item_prices_get', { p_vendor_item_id: id });
  }
  const vendor = q.get('vendor_id');
  const vendorId = vendor ? toInt(vendor) : null;
  if (vendor && vendorId === null) return NextResponse.json({ error: 'Invalid vendor_id' }, { status: 400 });
  return adminRpc(tenant, 'po_vendor_items_get', { p_vendor_id: vendorId });
}

export async function POST(request: Request) {
  const body = await readBody(request);
  if (!body || typeof body.item !== 'object' || body.item === null) {
    return NextResponse.json({ error: 'The item is missing' }, { status: 400 });
  }
  return adminRpc(body.tenant_id, 'po_vendor_item_save', { p_item: body.item });
}

export async function DELETE(request: Request) {
  const q = new URL(request.url).searchParams;
  const id = toInt(q.get('id'));
  if (id === null) return NextResponse.json({ error: 'Invalid id' }, { status: 400 });
  return adminRpc(q.get('tenant_id'), 'po_vendor_item_delete', { p_vendor_item_id: id });
}
