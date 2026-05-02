import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';

export const dynamic = 'force-dynamic';

/**
 * POST /api/orders/save
 * Body: { p_tenant_id, p_action, p_order_id?, p_payload? }
 *
 * p_action: 'create' | 'update' | 'delete'
 * Uses om_save_order RPC.
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

  const { p_tenant_id, p_action, p_order_id = null, p_payload = null } =
    body as Record<string, unknown>;

  if (typeof p_tenant_id !== 'number' || !Number.isInteger(p_tenant_id)) {
    return NextResponse.json({ error: 'Invalid or missing p_tenant_id' }, { status: 400 });
  }

  const validActions = ['create', 'update', 'delete'] as const;
  if (typeof p_action !== 'string' || !validActions.includes(p_action as (typeof validActions)[number])) {
    return NextResponse.json(
      { error: 'p_action must be one of: create, update, delete' },
      { status: 400 },
    );
  }

  if (p_order_id !== null && (typeof p_order_id !== 'number' || !Number.isInteger(p_order_id))) {
    return NextResponse.json({ error: 'Invalid p_order_id' }, { status: 400 });
  }

  const supabase = createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const { data, error } = await supabase.rpc('om_save_order', {
    p_tenant_id,
    p_action,
    p_order_id: p_order_id ?? null,
    p_payload: p_payload ?? null,
  });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 400 });
  }

  return NextResponse.json({ data });
}
