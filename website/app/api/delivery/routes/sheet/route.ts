import { NextResponse } from 'next/server';
import { adminRpc } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/** GET /api/delivery/routes/sheet?tenant_id=n&dow=MON&code=MORNING&route_id=n?&date=YYYY-MM-DD? → route sheet(s) in stop order (om_route_sheet_get) */
export async function GET(request: Request) {
  const q = new URL(request.url).searchParams;
  const date = q.get('date');
  if (date && !/^\d{4}-\d{2}-\d{2}$/.test(date)) return NextResponse.json({ error: 'Invalid date' }, { status: 400 });
  const routeId = q.get('route_id') ? toInt(q.get('route_id')) : null;
  return adminRpc(q.get('tenant_id'), 'om_route_sheet_get', { p_dow: q.get('dow'), p_code: q.get('code'), p_route_id: routeId, p_date: date || null });
}
