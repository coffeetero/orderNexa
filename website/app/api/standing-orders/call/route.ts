import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { requireStaff, toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

const DOWS = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

/**
 * GET  /api/standing-orders/call?tenant_id&customer_id&production_dow&production_code
 *      → { is_call, assigned_user_id, users: [{ user_id, user_name }] }
 * POST /api/standing-orders/call { tenant_id, customer_id, production_dows[], production_code, is_call, assigned_user_id? }
 *      → the saved setting (Call + Assigned to for the Call Up List)
 */
export async function GET(request: Request): Promise<NextResponse> {
  const url = new URL(request.url);
  const tenantId = toInt(url.searchParams.get('tenant_id'));
  const customerId = toInt(url.searchParams.get('customer_id'));
  const dow = (url.searchParams.get('production_dow') ?? '').toUpperCase();
  const code = url.searchParams.get('production_code') ?? '';
  if (tenantId === null || customerId === null || !DOWS.includes(dow) || !code) {
    return NextResponse.json({ error: 'tenant_id, customer_id, production_dow and production_code are required' }, { status: 400 });
  }
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;
  const { data, error } = await (await createClient()).rpc('om_standing_order_call_get', {
    p_tenant_id: tenantId, p_customer_id: customerId, p_production_dow: dow, p_production_code: code,
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}

export async function POST(request: Request): Promise<NextResponse> {
  let body: Record<string, unknown>;
  try {
    body = (await request.json()) as Record<string, unknown>;
  } catch {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  }
  const tenantId = toInt(body.tenant_id);
  const customerId = toInt(body.customer_id);
  const dows = Array.isArray(body.production_dows) ? body.production_dows.filter((d): d is string => typeof d === 'string' && DOWS.includes(d.toUpperCase())) : [];
  const code = typeof body.production_code === 'string' ? body.production_code : '';
  const assigned = body.assigned_user_id == null || body.assigned_user_id === '' ? null : toInt(body.assigned_user_id);
  if (tenantId === null || customerId === null || dows.length === 0 || !code || typeof body.is_call !== 'boolean') {
    return NextResponse.json({ error: 'tenant_id, customer_id, production_dows, production_code and is_call are required' }, { status: 400 });
  }
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;
  const { data, error } = await (await createClient()).rpc('om_standing_order_call_save', {
    p_tenant_id: tenantId, p_customer_id: customerId, p_production_dows: dows, p_production_code: code,
    p_is_call: body.is_call, p_assigned_user_id: assigned,
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
