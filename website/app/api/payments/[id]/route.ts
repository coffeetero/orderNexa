import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

const list = (v: unknown) => (Array.isArray(v) ? v : []);
const text = (v: unknown) => (typeof v === 'string' ? v.slice(0, 500) : null);

/**
 * POST /api/payments/:id { tenant_id, action, ... }
 *   action 'apply'   { applications, credits, auto_apply }         → ar_payment_apply (reapply unapplied cash)
 *   action 'unapply' { application_ids, credit_application_ids, reason } → ar_payment_unapply (empty lists = all)
 *   action 'void'    { reason }                                    → ar_payment_void
 */
export async function POST(request: Request, { params }: { params: { id: string } }) {
  const id = toInt(params.id);
  if (id === null) return NextResponse.json({ error: 'Invalid payment id' }, { status: 400 });
  const body = await readBody(request);
  if (!body) return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });

  switch (body.action) {
    case 'apply':
      return adminRpc(body.tenant_id, 'ar_payment_apply', {
        p_ar_payment_id: id,
        p_payload: { applications: list(body.applications), credits: list(body.credits), auto_apply: body.auto_apply === true },
      });
    case 'unapply':
      return adminRpc(body.tenant_id, 'ar_payment_unapply', {
        p_ar_payment_id: id,
        p_payload: { application_ids: list(body.application_ids), credit_application_ids: list(body.credit_application_ids), reason: text(body.reason) },
      });
    case 'void':
      return adminRpc(body.tenant_id, 'ar_payment_void', { p_ar_payment_id: id, p_reason: text(body.reason) });
    default:
      return NextResponse.json({ error: 'Unknown action' }, { status: 400 });
  }
}
