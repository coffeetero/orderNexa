import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { requireStaff, toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

const isDate = (v: string | null) => v === null || /^\d{4}-\d{2}-\d{2}$/.test(v);

/**
 * GET  /api/admin/production-runs?tenant_id=<n>[&from=YYYY-MM-DD][&to=YYYY-MM-DD][&upcoming=true] → runs with order counts
 * POST /api/admin/production-runs { tenant_id, production_run_id, cutoff_local 'YYYY-MM-DDTHH:MM' in the tenant's time zone } → change an OPEN run's cutoff
 * Staff only.
 */
export async function GET(request: Request) {
  const url = new URL(request.url);
  const tenantId = toInt(url.searchParams.get('tenant_id'));
  const from = url.searchParams.get('from');
  const to = url.searchParams.get('to');
  if (tenantId === null || !isDate(from) || !isDate(to)) {
    return NextResponse.json({ error: 'Invalid tenant_id, from or to' }, { status: 400 });
  }
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;

  const { data, error } = await createClient().rpc('om_production_runs_get', {
    p_tenant_id: tenantId, p_from: from, p_to: to, p_upcoming_only: url.searchParams.get('upcoming') === 'true',
  });
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
  const runId = toInt(body.production_run_id);
  const cutoff = typeof body.cutoff_local === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(body.cutoff_local) ? body.cutoff_local : null;
  if (tenantId === null || runId === null || !cutoff) {
    return NextResponse.json({ error: 'tenant_id, production_run_id and cutoff_local (YYYY-MM-DDTHH:MM) are required' }, { status: 400 });
  }
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;

  const { data, error } = await createClient().rpc('om_production_run_cutoff_save', {
    p_tenant_id: tenantId, p_production_run_id: runId, p_cutoff_local: cutoff,
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
