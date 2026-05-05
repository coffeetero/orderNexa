import { NextResponse } from 'next/server';
import { createClient, getSessionUser } from '@/lib/supabase/server';

export const dynamic = 'force-dynamic';

/**
 * POST /api/orders/save
 * Body: { p_tenant_id, p_order_id?, p_payload?, p_action? }
 *
 * Upsert mode is driven by p_order_id nullability:
 *   p_order_id = null  -> create
 *   p_order_id != null -> update
 *
 * p_action is optional and currently used only for delete compatibility.
 * Uses om_orders_save RPC.
 */
export async function POST(request: Request) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  }

  if (typeof body !== 'object' || body === null) {
    return NextResponse.json({ error: 'Request body must be a JSON object' }, { status: 400 });
  }

  const { p_tenant_id, p_action = null, p_order_id = null, p_payload = null } =
    body as Record<string, unknown>;

  if (typeof p_tenant_id !== 'number' || !Number.isInteger(p_tenant_id)) {
    return NextResponse.json({ error: 'Invalid or missing p_tenant_id' }, { status: 400 });
  }

  if (p_action !== null && p_action !== 'delete') {
    return NextResponse.json({ error: 'p_action is only supported for delete' }, { status: 400 });
  }

  if (p_order_id !== null && (typeof p_order_id !== 'number' || !Number.isInteger(p_order_id))) {
    return NextResponse.json({ error: 'Invalid p_order_id' }, { status: 400 });
  }

  if (p_action !== 'delete') {
    if (typeof p_payload !== 'object' || p_payload === null) {
      return NextResponse.json({ error: 'Invalid or missing p_payload' }, { status: 400 });
    }
    const payload = p_payload as Record<string, unknown>;
    if (!Array.isArray(payload.lines)) {
      return NextResponse.json({ error: 'p_payload.lines must be an array' }, { status: 400 });
    }
  }

  const user = await getSessionUser();
  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const supabase = createClient();
  const { data, error } = await supabase.rpc('om_orders_save', {
    p_tenant_id,
    p_action: p_action ?? null,
    p_order_id: p_order_id ?? null,
    p_payload: p_payload ?? null,
  });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 400 });
  }

  return NextResponse.json({ data });
}
