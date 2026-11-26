import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * GET    /api/delivery/routes?tenant_id=n&code=MORNING → routes with stop counts per day, staff, production codes (om_routes_get)
 * POST   /api/delivery/routes { tenant_id, route }     → creates or saves a route (om_route_save)
 * DELETE /api/delivery/routes?tenant_id=n&id=n         → deletes a route with its stops (om_route_delete)
 */
export async function GET(request: Request) {
  const q = new URL(request.url).searchParams;
  return adminRpc(q.get('tenant_id'), 'om_routes_get', { p_production_code: q.get('code') || null });
}

export async function POST(request: Request) {
  const body = await readBody(request);
  if (!body) return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  if (!body.route || typeof body.route !== 'object') return NextResponse.json({ error: 'The route is missing' }, { status: 400 });
  return adminRpc(body.tenant_id, 'om_route_save', { p_route: body.route });
}

export async function DELETE(request: Request) {
  const q = new URL(request.url).searchParams;
  const id = toInt(q.get('id'));
  if (id === null) return NextResponse.json({ error: 'Invalid id' }, { status: 400 });
  return adminRpc(q.get('tenant_id'), 'om_route_delete', { p_route_id: id });
}
