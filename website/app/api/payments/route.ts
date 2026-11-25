import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

const list = (v: unknown) => (Array.isArray(v) ? v : []);

/**
 * GET  /api/payments?tenant_id=n&id=n → one payment with its applications (ar_payment_get)
 * GET  /api/payments?tenant_id=n&customer_id&date_from&date_to&payment_method&reference&amount&unapplied_only=1 → search (ar_payments_search)
 * POST /api/payments { tenant_id, customer_id, payment_date, payment_method, reference_number, amount, applications, credits,
 *                      auto_apply, allow_duplicate } → records the payment and its applications in one call (ar_payment_post)
 */
export async function GET(request: Request) {
  const q = new URL(request.url).searchParams;
  if (q.has('id')) {
    const id = toInt(q.get('id'));
    if (id === null) return NextResponse.json({ error: 'Invalid id' }, { status: 400 });
    return adminRpc(q.get('tenant_id'), 'ar_payment_get', { p_ar_payment_id: id });
  }
  const filters: Record<string, unknown> = {};
  for (const k of ['customer_id', 'date_from', 'date_to', 'payment_method', 'reference', 'amount']) {
    const v = q.get(k);
    if (v) filters[k] = v.slice(0, 100);
  }
  filters.unapplied_only = q.get('unapplied_only') === '1';
  return adminRpc(q.get('tenant_id'), 'ar_payments_search', { p_filters: filters });
}

export async function POST(request: Request) {
  const body = await readBody(request);
  if (!body) return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  return adminRpc(body.tenant_id, 'ar_payment_post', {
    p_payload: {
      customer_id: body.customer_id ?? null,
      payment_date: body.payment_date ?? null,
      payment_method: body.payment_method ?? null,
      reference_number: typeof body.reference_number === 'string' ? body.reference_number.slice(0, 100) : null,
      amount: body.amount ?? null,
      applications: list(body.applications),
      credits: list(body.credits),
      auto_apply: body.auto_apply === true,
      allow_duplicate: body.allow_duplicate === true,
    },
  });
}
