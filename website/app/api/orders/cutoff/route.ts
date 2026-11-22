import { NextResponse } from 'next/server';
import { createClient, getSessionUser } from '@/lib/supabase/server';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * GET /api/orders/cutoff?tenant_id=<n>&production_date=<YYYY-MM-DD>&production_code=<CODE>[&customer_id=<n>]
 * → om_production_cutoff_get: { cutoff_at, effective_cutoff_at, extra_minutes, time_zone, run_status, is_open }.
 * Never creates a run. The order save function enforces the cutoff for customers; this is for display.
 */
export async function GET(request: Request) {
  const url = new URL(request.url);
  const tenantId = toInt(url.searchParams.get('tenant_id'));
  const date = url.searchParams.get('production_date') ?? '';
  const code = url.searchParams.get('production_code') ?? '';
  if (tenantId === null || !/^\d{4}-\d{2}-\d{2}$/.test(date) || code.trim() === '') {
    return NextResponse.json({ error: 'tenant_id, production_date and production_code are required' }, { status: 400 });
  }
  const user = await getSessionUser();
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const supabase = createClient();
  const { data, error } = await supabase.rpc('om_production_cutoff_get', {
    p_tenant_id: tenantId,
    p_production_date: date,
    p_production_code: code,
    p_customer_id: toInt(url.searchParams.get('customer_id')),
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
