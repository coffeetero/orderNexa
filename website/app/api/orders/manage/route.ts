import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { requireStaff } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

const isDate = (v: string | null) => v !== null && /^\d{4}-\d{2}-\d{2}$/.test(v);
const oneOf = <T extends string>(v: string | null, allowed: readonly T[], fallback: T): T => (allowed.includes(v as T) ? (v as T) : fallback);

/**
 * GET /api/orders/manage?period=&from=&to=&shift=&status=&search=&group=&sort=&desc=&page=
 * One page (50) of orders for Manage Orders, with the summary strip and group subtotals (om_orders_manage_get).
 */
export async function GET(request: Request) {
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) return NextResponse.json({ error: 'No company found' }, { status: 400 });
  const q = new URL(request.url).searchParams;
  const page = Math.max(Number.parseInt(q.get('page') ?? '1', 10) || 1, 1);
  const { data, error } = await (await createClient()).rpc('om_orders_manage_get', {
    p_tenant_id: tenantId,
    p_period: oneOf(q.get('period'), ['yesterday', 'today', 'tomorrow', 'this_week', 'custom'] as const, 'today'),
    p_from: isDate(q.get('from')) ? q.get('from') : null,
    p_to: isDate(q.get('to')) ? q.get('to') : null,
    p_shift: q.get('shift') || null,
    p_status: oneOf(q.get('status'), ['', 'OPEN', 'IN_PRODUCTION', 'SHIPPED', 'INVOICED'] as const, '') || null,
    p_search: (q.get('search') ?? '').slice(0, 100) || null,
    p_group: oneOf(q.get('group'), ['shift', 'customer', 'status', 'none'] as const, 'shift'),
    p_sort: oneOf(q.get('sort'), ['order', 'customer', 'lines', 'amount'] as const, 'order'),
    p_desc: q.get('desc') !== '0',
    p_limit: 50,
    p_offset: (page - 1) * 50,
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
