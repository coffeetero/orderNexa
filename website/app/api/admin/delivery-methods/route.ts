import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { requireStaff, toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * GET  /api/admin/delivery-methods?tenant_id=<n> → the tenant's delivery methods
 * POST /api/admin/delivery-methods { tenant_id, delivery_method_code, delivery_method_name, is_own_fleet, requires_tracking, is_active }
 * Methods are never deleted; set is_active false. Staff only.
 */
export async function GET(request: Request) {
  const tenantId = toInt(new URL(request.url).searchParams.get('tenant_id'));
  if (tenantId === null) return NextResponse.json({ error: 'Invalid or missing tenant_id' }, { status: 400 });
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;

  const { data, error } = await (await createClient()).rpc('om_delivery_methods_get', { p_tenant_id: tenantId });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}

export async function POST(request: Request) {
  let body: Record<string, unknown>;
  try {
    body = (await request.json()) as Record<string, unknown>;
  } catch {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  }
  const tenantId = toInt(body.tenant_id);
  if (tenantId === null || typeof body.delivery_method_code !== 'string' || typeof body.delivery_method_name !== 'string') {
    return NextResponse.json({ error: 'tenant_id, delivery_method_code and delivery_method_name are required' }, { status: 400 });
  }
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;

  const { data, error } = await (await createClient()).rpc('om_delivery_methods_save', {
    p_tenant_id: tenantId,
    p_payload: {
      delivery_method_code: body.delivery_method_code,
      delivery_method_name: body.delivery_method_name,
      is_own_fleet: body.is_own_fleet === true,
      requires_tracking: body.requires_tracking === true,
      is_active: body.is_active !== false,
    },
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
