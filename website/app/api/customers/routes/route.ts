import { NextResponse } from 'next/server';
import { adminRpc } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/** GET /api/customers/routes?tenant_id=n&customer_id=n → the ship-to's route stops per day and upcoming date changes, read only (om_customer_routes_get) */
export async function GET(request: Request) {
  const q = new URL(request.url).searchParams;
  const id = toInt(q.get('customer_id'));
  if (id === null) return NextResponse.json({ error: 'Invalid customer_id' }, { status: 400 });
  return adminRpc(q.get('tenant_id'), 'om_customer_routes_get', { p_customer_id: id });
}
