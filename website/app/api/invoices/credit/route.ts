import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { requireStaff, toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * POST /api/invoices/credit { tenant_id, ar_transaction_id, reason?, lines: [{ ar_transaction_line_id, quantity }] }
 * → ar_credit_memo_create: a numbered credit memo against an issued invoice. Limits are enforced in the database function.
 */
export async function POST(request: Request) {
  let body: Record<string, unknown>;
  try {
    body = (await request.json()) as Record<string, unknown>;
  } catch {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  }
  const tenantId = toInt(body.tenant_id);
  const invoiceId = toInt(body.ar_transaction_id);
  if (tenantId === null || invoiceId === null || !Array.isArray(body.lines)) {
    return NextResponse.json({ error: 'tenant_id, ar_transaction_id and lines are required' }, { status: 400 });
  }
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;

  const { data, error } = await createClient().rpc('ar_credit_memo_create', {
    p_tenant_id: tenantId,
    p_applies_to_ar_transaction_id: invoiceId,
    p_payload: { reason: typeof body.reason === 'string' ? body.reason : null, lines: body.lines },
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
