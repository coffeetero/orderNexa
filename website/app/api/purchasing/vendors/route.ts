import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * GET    /api/purchasing/vendors?tenant_id=n               → the vendor list (po_vendors_get)
 * POST   /api/purchasing/vendors { tenant_id, vendor }     → creates or saves a vendor (po_vendor_save)
 * DELETE /api/purchasing/vendors?tenant_id=n&id=n          → deletes a vendor with no items (po_vendor_delete)
 */
export async function GET(request: Request) {
  return adminRpc(new URL(request.url).searchParams.get('tenant_id'), 'po_vendors_get', {});
}

export async function POST(request: Request) {
  const body = await readBody(request);
  if (!body || typeof body.vendor !== 'object' || body.vendor === null) {
    return NextResponse.json({ error: 'The vendor is missing' }, { status: 400 });
  }
  return adminRpc(body.tenant_id, 'po_vendor_save', { p_vendor: body.vendor });
}

export async function DELETE(request: Request) {
  const q = new URL(request.url).searchParams;
  const id = toInt(q.get('id'));
  if (id === null) return NextResponse.json({ error: 'Invalid id' }, { status: 400 });
  return adminRpc(q.get('tenant_id'), 'po_vendor_delete', { p_vendor_id: id });
}
