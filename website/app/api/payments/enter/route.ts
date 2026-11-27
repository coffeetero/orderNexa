import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { readBody } from '@/lib/api/admin-rpc';
import { requireStaff, toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * POST /api/payments/enter { tenant_id, customer_id, payment_date, check_no, amount, allow_duplicate?,
 *                            lines: [{ ar_transaction_id, payment, allowance?, allowance_reason? }] } → { data }
 * Saves one check from Enter Payments: allowances on their invoices, then the payment with its applications and the credits
 * it takes, in one transaction (ar_payment_enter). A duplicate check number comes back as an error starting
 * "Duplicate reference", so the screen can ask and resend with allow_duplicate.
 */
export async function POST(request: Request) {
  const body = await readBody(request);
  const tenantId = toInt(body?.tenant_id);
  if (tenantId === null || !body) return NextResponse.json({ error: 'tenant_id is required' }, { status: 400 });
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;
  const { data, error } = await (await createClient()).rpc('ar_payment_enter', {
    p_tenant_id: tenantId,
    p_payload: {
      customer_id: toInt(body.customer_id), payment_date: body.payment_date, check_no: body.check_no, amount: body.amount,
      allow_duplicate: body.allow_duplicate === true, lines: Array.isArray(body.lines) ? body.lines : [],
    },
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
