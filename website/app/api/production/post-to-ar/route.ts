import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { requireStaff, toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

const isDate = (v: unknown): v is string => typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v);

/**
 * POST /api/production/post-to-ar { tenant_id, from, to, production_code? }
 * → om_invoices_post_to_ar: numbers the draft invoices of the runs in the date range (the only step that numbers invoices).
 * Returns { numbered, invoices: [{ ar_transaction_id, document_number, customer_name, production_date, production_code, amount }] }.
 */
export async function POST(request: Request): Promise<NextResponse> {
  let body: Record<string, unknown>;
  try {
    body = (await request.json()) as Record<string, unknown>;
  } catch {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  }
  const tenantId = toInt(body.tenant_id);
  if (tenantId === null || !isDate(body.from) || !isDate(body.to)) {
    return NextResponse.json({ error: 'tenant_id, from and to (YYYY-MM-DD) are required' }, { status: 400 });
  }
  const code = typeof body.production_code === 'string' && body.production_code.trim() !== '' ? body.production_code : null;
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;

  const { data, error } = await createClient().rpc('om_invoices_post_to_ar', {
    p_tenant_id: tenantId, p_from: body.from, p_to: body.to, p_production_code: code,
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
