import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { requireStaff, toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * POST /api/shipments/confirm { tenant_id, shipment_id, shipment_status, delivery_method_code?, carrier?, tracking_reference?,
 *   route?, delivery_cost?, lines?: [{ shipment_line_id, shipped_quantity }] }
 * → om_shipment_confirm. All rules (tracking required, quantity limits, fulfilled quantities) live in the database function.
 */
export async function POST(request: Request) {
  let body: Record<string, unknown>;
  try {
    body = (await request.json()) as Record<string, unknown>;
  } catch {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  }
  const tenantId = toInt(body.tenant_id);
  const shipmentId = toInt(body.shipment_id);
  if (tenantId === null || shipmentId === null) {
    return NextResponse.json({ error: 'tenant_id and shipment_id are required' }, { status: 400 });
  }
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;

  const { tenant_id: _t, shipment_id: _s, ...payload } = body;
  void _t; void _s;
  const { data, error } = await (await createClient()).rpc('om_shipment_confirm', {
    p_tenant_id: tenantId, p_shipment_id: shipmentId, p_payload: payload,
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
