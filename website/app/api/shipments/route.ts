import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { requireStaff, toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

const isDate = (v: string | null): v is string => v !== null && /^\d{4}-\d{2}-\d{2}$/.test(v);

/**
 * GET /api/shipments?tenant_id=<n>&from=YYYY-MM-DD&to=YYYY-MM-DD[&production_code=CODE][&status=PLANNED|SHIPPED|DELIVERED]
 * → om_shipments_get: shipments with lines and invoice numbers, for delivery confirmation.
 */
export async function GET(request: Request) {
  const url = new URL(request.url);
  const tenantId = toInt(url.searchParams.get('tenant_id'));
  const from = url.searchParams.get('from');
  const to = url.searchParams.get('to');
  if (tenantId === null || !isDate(from) || !isDate(to)) {
    return NextResponse.json({ error: 'tenant_id, from and to (YYYY-MM-DD) are required' }, { status: 400 });
  }
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;

  const code = url.searchParams.get('production_code');
  const status = url.searchParams.get('status');
  const { data, error } = await createClient().rpc('om_shipments_get', {
    p_tenant_id: tenantId, p_from: from, p_to: to,
    p_production_code: code && code.trim() !== '' ? code : null,
    p_status: status && status.trim() !== '' ? status : null,
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
