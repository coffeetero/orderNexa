import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { requireStaff, toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * GET  /api/admin/sequences?tenant_id=<n> → numbering settings (order, invoice, shipment, credit memo)
 * POST /api/admin/sequences { tenant_id, sequence_name, mask, start_value, next_value, increment_by, reset_period, requires_gapless }
 * Staff only; validation lives in fnd_tenant_sequences_save.
 */
export async function GET(request: Request) {
  const tenantId = toInt(new URL(request.url).searchParams.get('tenant_id'));
  if (tenantId === null) return NextResponse.json({ error: 'Invalid or missing tenant_id' }, { status: 400 });
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;

  const { data, error } = await createClient().rpc('fnd_tenant_sequences_get', { p_tenant_id: tenantId });
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
  if (tenantId === null || typeof body.sequence_name !== 'string' || typeof body.mask !== 'string') {
    return NextResponse.json({ error: 'tenant_id, sequence_name and mask are required' }, { status: 400 });
  }
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;

  const { sequence_name, mask, start_value, next_value, increment_by, reset_period, requires_gapless } = body;
  const { data, error } = await createClient().rpc('fnd_tenant_sequences_save', {
    p_tenant_id: tenantId,
    p_payload: { sequence_name, mask, start_value, next_value, increment_by, reset_period, requires_gapless: requires_gapless === true },
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
