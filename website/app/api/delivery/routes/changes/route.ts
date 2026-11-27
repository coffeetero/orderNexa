import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

const isDate = (v: unknown): v is string => typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v);

/**
 * GET    /api/delivery/routes/changes?tenant_id=n&from=YYYY-MM-DD&to=YYYY-MM-DD&code=MORNING → one-off date changes (om_route_exceptions_get)
 * POST   /api/delivery/routes/changes { tenant_id, change }  → records a change (om_route_exception_save)
 * DELETE /api/delivery/routes/changes?tenant_id=n&id=n       → removes a change (om_route_exception_delete)
 */
export async function GET(request: Request) {
  const q = new URL(request.url).searchParams;
  const from = q.get('from');
  const to = q.get('to');
  if (!isDate(from) || !isDate(to)) return NextResponse.json({ error: 'Invalid dates' }, { status: 400 });
  return adminRpc(q.get('tenant_id'), 'om_route_exceptions_get', { p_from: from, p_to: to, p_code: q.get('code') || null });
}

export async function POST(request: Request) {
  const body = await readBody(request);
  if (!body) return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  if (!body.change || typeof body.change !== 'object') return NextResponse.json({ error: 'The change is missing' }, { status: 400 });
  return adminRpc(body.tenant_id, 'om_route_exception_save', { p_exception: body.change });
}

export async function DELETE(request: Request) {
  const q = new URL(request.url).searchParams;
  const id = toInt(q.get('id'));
  if (id === null) return NextResponse.json({ error: 'Invalid id' }, { status: 400 });
  return adminRpc(q.get('tenant_id'), 'om_route_exception_delete', { p_exception_id: id });
}
