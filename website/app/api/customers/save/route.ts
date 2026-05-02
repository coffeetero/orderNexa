import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';

const ACTIONS = new Set(['create', 'update', 'delete']);

export async function POST(request: Request) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  }

  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    return NextResponse.json({ error: 'Expected a JSON object' }, { status: 400 });
  }

  const o = body as Record<string, unknown>;

  const tenantRaw = o.p_tenant_id;
  const p_tenant_id =
    typeof tenantRaw === 'number' ? tenantRaw : Number(tenantRaw);
  if (!Number.isFinite(p_tenant_id) || !Number.isInteger(p_tenant_id)) {
    return NextResponse.json({ error: 'Invalid p_tenant_id' }, { status: 400 });
  }

  const p_action =
    typeof o.p_action === 'string' ? o.p_action.toLowerCase().trim() : '';
  if (!ACTIONS.has(p_action)) {
    return NextResponse.json({ error: 'Invalid p_action' }, { status: 400 });
  }

  let p_customer_id: number | null = null;
  if (o.p_customer_id !== undefined && o.p_customer_id !== null) {
    const cid =
      typeof o.p_customer_id === 'number' ? o.p_customer_id : Number(o.p_customer_id);
    if (!Number.isFinite(cid) || !Number.isInteger(cid)) {
      return NextResponse.json({ error: 'Invalid p_customer_id' }, { status: 400 });
    }
    p_customer_id = cid;
  }

  const rawPayload = o.p_payload;
  const p_payload =
    rawPayload !== undefined &&
    rawPayload !== null &&
    typeof rawPayload === 'object' &&
    !Array.isArray(rawPayload)
      ? (rawPayload as Record<string, unknown>)
      : {};

  const supabase = createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const { data, error } = await supabase.rpc('fnd_save_customers', {
    p_tenant_id,
    p_customer_id,
    p_action,
    p_payload,
  });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 400 });
  }

  return NextResponse.json({ data });
}
