import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { requireStaff, toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

const isDate = (v: unknown): v is string => typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v);

/**
 * POST /api/production/process { tenant_id, from, to, production_code? }
 * → om_production_runs_process: processes every non-closed run in the date range (builds shipments and invoice drafts).
 * Returns one summary per run: { production_run_id, production_date, production_code, orders, shipments, invoices }.
 */
export async function POST(request: Request) {
  let body: Record<string, unknown>;
  try {
    body = (await request.json()) as Record<string, unknown>;
  } catch {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  }
  const tenantId = toInt(body.tenant_id);
  if (tenantId === null || !isDate(body.from) || !isDate(body.to)) {
    return NextResponse.json({ error: 'tenant_id, from and to (YYYY-MM-DD) are required' }, { status: 400 });
  }
  const code = typeof body.production_code === 'string' && body.production_code.trim() !== '' ? body.production_code : null;
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;

  const { data, error } = await (await createClient()).rpc('om_production_runs_process', {
    p_tenant_id: tenantId, p_from: body.from, p_to: body.to, p_production_code: code,
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
