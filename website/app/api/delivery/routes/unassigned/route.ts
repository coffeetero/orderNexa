import { adminRpc } from '@/lib/api/admin-rpc';

export const dynamic = 'force-dynamic';

/** GET /api/delivery/routes/unassigned?tenant_id=n&dow=MON&code=MORNING&all=1 → ship-to locations with no route that day (om_route_unassigned_get) */
export async function GET(request: Request) {
  const q = new URL(request.url).searchParams;
  return adminRpc(q.get('tenant_id'), 'om_route_unassigned_get', { p_dow: q.get('dow'), p_code: q.get('code'), p_ordering_only: q.get('all') !== '1' });
}
