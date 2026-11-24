import { NextResponse } from 'next/server';
import { adminRpc } from '@/lib/api/admin-rpc';

export const dynamic = 'force-dynamic';

const isDate = (v: unknown): v is string => typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v);

/**
 * GET /api/orders/export?tenant_id=n&customer_id=n&production_date=YYYY-MM-DD&production_code=X
 *     → the account's orders for that slot as import-file rows [{cus_no, item_number, item_desc, qty, department_event}] (om_order_export_get)
 */
export async function GET(request: Request) {
  const q = new URL(request.url).searchParams;
  const customerId = Number(q.get('customer_id'));
  const date = q.get('production_date');
  const code = q.get('production_code');
  if (!Number.isSafeInteger(customerId) || customerId <= 0) return NextResponse.json({ error: 'customer_id is required' }, { status: 400 });
  if (!isDate(date)) return NextResponse.json({ error: 'production_date must be YYYY-MM-DD' }, { status: 400 });
  if (!code) return NextResponse.json({ error: 'production_code is required' }, { status: 400 });
  return adminRpc(q.get('tenant_id'), 'om_order_export_get', { p_account_id: customerId, p_production_date: date, p_production_code: code });
}
