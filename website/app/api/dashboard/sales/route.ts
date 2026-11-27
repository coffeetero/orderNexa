import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { requireStaff, toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * GET /api/dashboard/sales?tenant_id=n[&account_id=n]
 * → Dashboard sales charts, year to date vs the same days last year (ar_sales_dashboard_get): months (for all accounts or one),
 *   accounts for the picker, segments and top items.
 */
export async function GET(request: Request): Promise<NextResponse> {
  const q = new URL(request.url).searchParams;
  const tenantId = toInt(q.get('tenant_id'));
  const accountId = q.get('account_id') ? toInt(q.get('account_id')) : null;
  if (tenantId === null) return NextResponse.json({ error: 'tenant_id is required' }, { status: 400 });
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;
  const { data, error } = await (await createClient()).rpc('ar_sales_dashboard_get', { p_tenant_id: tenantId, p_account_id: accountId });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
