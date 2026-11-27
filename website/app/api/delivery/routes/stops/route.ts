import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * GET    /api/delivery/routes/stops?tenant_id=n&route_id=n&dow=MON&code=MORNING → the route's stops for the day (om_route_stops_get)
 * POST   /api/delivery/routes/stops { tenant_id, action, ... }
 *          action 'add'  { route_id, dow, code, customer_id, stop_no?, move? } → om_route_stop_add
 *          action 'move' { route_stop_id, stop_no }                            → om_route_stop_move
 *          action 'save' { route_stop_id, stop: { window_from, window_to, driver_notes } } → om_route_stop_save
 *          action 'copy' { route_id, dow, code, targets: [{ day_of_week, production_code }], mode } → om_route_stops_copy
 * DELETE /api/delivery/routes/stops?tenant_id=n&id=n → takes the stop off its route (om_route_stop_delete)
 */
export async function GET(request: Request) {
  const q = new URL(request.url).searchParams;
  const routeId = toInt(q.get('route_id'));
  if (routeId === null) return NextResponse.json({ error: 'Invalid route_id' }, { status: 400 });
  return adminRpc(q.get('tenant_id'), 'om_route_stops_get', { p_route_id: routeId, p_dow: q.get('dow'), p_code: q.get('code') });
}

export async function POST(request: Request) {
  const body = await readBody(request);
  if (!body) return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  const stopNo = body.stop_no === null || body.stop_no === undefined ? null : toInt(body.stop_no);
  switch (body.action) {
    case 'add': {
      const routeId = toInt(body.route_id);
      const customerId = toInt(body.customer_id);
      if (routeId === null || customerId === null) return NextResponse.json({ error: 'Route and customer are required' }, { status: 400 });
      return adminRpc(body.tenant_id, 'om_route_stop_add', {
        p_route_id: routeId, p_dow: body.dow, p_code: body.code, p_customer_id: customerId, p_stop_no: stopNo, p_move: body.move === true,
      });
    }
    case 'move': {
      const id = toInt(body.route_stop_id);
      if (id === null || stopNo === null) return NextResponse.json({ error: 'Stop and stop number are required' }, { status: 400 });
      return adminRpc(body.tenant_id, 'om_route_stop_move', { p_route_stop_id: id, p_stop_no: stopNo });
    }
    case 'save': {
      const id = toInt(body.route_stop_id);
      if (id === null || !body.stop || typeof body.stop !== 'object') return NextResponse.json({ error: 'Stop is required' }, { status: 400 });
      return adminRpc(body.tenant_id, 'om_route_stop_save', { p_route_stop_id: id, p_stop: body.stop });
    }
    case 'copy': {
      const routeId = toInt(body.route_id);
      if (routeId === null || !Array.isArray(body.targets)) return NextResponse.json({ error: 'Route and targets are required' }, { status: 400 });
      return adminRpc(body.tenant_id, 'om_route_stops_copy', {
        p_route_id: routeId, p_dow: body.dow, p_code: body.code, p_targets: body.targets, p_mode: body.mode === 'MERGE' ? 'MERGE' : 'REPLACE',
      });
    }
    default:
      return NextResponse.json({ error: 'Unknown action' }, { status: 400 });
  }
}

export async function DELETE(request: Request) {
  const q = new URL(request.url).searchParams;
  const id = toInt(q.get('id'));
  if (id === null) return NextResponse.json({ error: 'Invalid id' }, { status: 400 });
  return adminRpc(q.get('tenant_id'), 'om_route_stop_delete', { p_route_stop_id: id });
}
