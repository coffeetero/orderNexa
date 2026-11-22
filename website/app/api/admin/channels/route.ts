import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * GET    /api/admin/channels?tenant_id=n → the tenant's phone / SMS / WhatsApp numbers
 * POST   /api/admin/channels { tenant_id, number: {phone_number_id?, phone_number, channel, label, is_active} } → phone_number_id
 * DELETE /api/admin/channels?tenant_id=n&phone_number_id=n
 */
export async function GET(request: Request) {
  return adminRpc(new URL(request.url).searchParams.get('tenant_id'), 'fnd_phone_numbers_get', {});
}

export async function POST(request: Request) {
  const body = await readBody(request);
  if (!body || typeof body.number !== 'object') return NextResponse.json({ error: 'number is required' }, { status: 400 });
  return adminRpc(body.tenant_id, 'fnd_phone_number_save', { p_payload: body.number });
}

export async function DELETE(request: Request) {
  const q = new URL(request.url).searchParams;
  const id = toInt(q.get('phone_number_id'));
  if (id === null) return NextResponse.json({ error: 'phone_number_id is required' }, { status: 400 });
  return adminRpc(q.get('tenant_id'), 'fnd_phone_number_delete', { p_phone_number_id: id });
}
