import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { requireStaff, toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * GET  /api/admin/production-codes?tenant_id=<n> → every PRODUCTIONCODE value with its cutoff settings
 * POST /api/admin/production-codes { tenant_id, production_code, cutoff_time 'HH:MM', cutoff_days_before, delivery_days_after, is_active }
 * Staff only (the database also enforces it).
 */
export async function GET(request: Request) {
  const tenantId = toInt(new URL(request.url).searchParams.get('tenant_id'));
  if (tenantId === null) return NextResponse.json({ error: 'Invalid or missing tenant_id' }, { status: 400 });
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;

  const { data, error } = await (await createClient()).rpc('om_production_codes_get', { p_tenant_id: tenantId });
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
  const time = typeof body.cutoff_time === 'string' ? body.cutoff_time : '';
  const daysBefore = toInt(body.cutoff_days_before);
  const daysAfter = toInt(body.delivery_days_after);
  if (tenantId === null || typeof body.production_code !== 'string' || !/^\d{2}:\d{2}$/.test(time) ||
      daysBefore === null || daysAfter === null) {
    return NextResponse.json({ error: 'tenant_id, production_code, cutoff_time (HH:MM) and day offsets are required' }, { status: 400 });
  }
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;

  const { data, error } = await (await createClient()).rpc('om_production_codes_save', {
    p_tenant_id: tenantId,
    p_payload: {
      production_code: body.production_code,
      cutoff_time: time,
      cutoff_days_before: daysBefore,
      delivery_days_after: daysAfter,
      is_active: body.is_active !== false,
    },
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
