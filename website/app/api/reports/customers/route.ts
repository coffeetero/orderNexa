import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { requireStaff, toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

const isDate = (v: string | null): v is string => v !== null && /^\d{4}-\d{2}-\d{2}$/.test(v);

/**
 * GET /api/reports/customers?tenant_id=<n>&from=YYYY-MM-DD&to=YYYY-MM-DD[&production_code=CODE]&basis=ORDER|INVOICE|PRINT
 * → om_report_customers_get: customers to pick from on the Labels (ORDER) and Packaging (INVOICE) pages.
 */
export async function GET(request: Request) {
  const url = new URL(request.url);
  const tenantId = toInt(url.searchParams.get('tenant_id'));
  const from = url.searchParams.get('from');
  const to = url.searchParams.get('to');
  const basis = (url.searchParams.get('basis') ?? 'ORDER').toUpperCase();
  if (tenantId === null || !isDate(from) || !isDate(to) || !['ORDER', 'INVOICE', 'PRINT'].includes(basis)) {
    return NextResponse.json({ error: 'tenant_id, from, to and basis (ORDER, INVOICE or PRINT) are required' }, { status: 400 });
  }
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;

  const code = url.searchParams.get('production_code');
  const { data, error } = await (await createClient()).rpc('om_report_customers_get', {
    p_tenant_id: tenantId, p_from: from, p_to: to, p_production_code: code && code.trim() !== '' ? code : null, p_basis: basis,
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
