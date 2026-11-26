import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { requireStaff, toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * GET /api/invoices/credit-orders?tenant_id=<n>&customer_id=<account>&production_date=YYYY-MM-DD&production_code=<code>
 * → ar_credit_orders_get: the account's orders for that slot with their invoice and the lines that can be credited.
 */
export async function GET(request: Request) {
  const url = new URL(request.url);
  const tenantId = toInt(url.searchParams.get('tenant_id'));
  const customerId = toInt(url.searchParams.get('customer_id'));
  const date = url.searchParams.get('production_date') ?? '';
  const code = (url.searchParams.get('production_code') ?? '').trim();
  if (tenantId === null || customerId === null || !/^\d{4}-\d{2}-\d{2}$/.test(date) || code === '') {
    return NextResponse.json({ error: 'tenant_id, customer_id, production_date and production_code are required' }, { status: 400 });
  }
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;

  const { data, error } = await createClient().rpc('ar_credit_orders_get', {
    p_tenant_id: tenantId, p_customer_id: customerId, p_production_date: date, p_production_code: code,
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
