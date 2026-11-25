import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * GET  /api/payments/open-items?tenant_id=n&customer_id=n → open invoices, credits and unapplied payments (ar_payment_open_items_get)
 * POST /api/payments/open-items { tenant_id, customer_id | ar_payment_id, amount, credits } → Auto-apply preview, oldest first (ar_payment_allocate)
 */
export async function GET(request: Request) {
  const q = new URL(request.url).searchParams;
  const customerId = toInt(q.get('customer_id'));
  if (customerId === null) return NextResponse.json({ error: 'Invalid customer_id' }, { status: 400 });
  return adminRpc(q.get('tenant_id'), 'ar_payment_open_items_get', { p_customer_id: customerId });
}

export async function POST(request: Request) {
  const body = await readBody(request);
  if (!body) return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  return adminRpc(body.tenant_id, 'ar_payment_allocate', {
    p_payload: {
      customer_id: body.customer_id ?? null,
      ar_payment_id: body.ar_payment_id ?? null,
      amount: body.amount ?? null,
      credits: Array.isArray(body.credits) ? body.credits : [],
    },
  });
}
