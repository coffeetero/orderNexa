import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { requireStaff, toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

const isDate = (v: unknown): v is string => typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v);

/**
 * GET /api/reports/financial/open-items?tenant_id=n&account_id=n&as_of=YYYY-MM-DD
 * → one account's open items on that date, each with the payments and credits applied to it and the other documents those covered
 *   (ar_open_item_details_get). Row security limits it to the caller's company and customers.
 */
export async function GET(request: Request) {
  const q = new URL(request.url).searchParams;
  const tenantId = toInt(q.get('tenant_id'));
  const accountId = toInt(q.get('account_id'));
  const asOf = q.get('as_of');
  if (tenantId === null || accountId === null || !isDate(asOf)) {
    return NextResponse.json({ error: 'tenant_id, account_id and as_of (YYYY-MM-DD) are required' }, { status: 400 });
  }
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;
  const { data, error } = await createClient().rpc('ar_open_item_details_get', { p_tenant_id: tenantId, p_account_id: accountId, p_as_of: asOf });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
