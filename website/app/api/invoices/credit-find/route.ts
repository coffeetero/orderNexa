import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { requireStaff, toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/** GET /api/invoices/credit-find?tenant_id=<n>&kind=ORDER|INVOICE|PO&q=<number> → ar_credit_find: matching orders with their account and slot. */
export async function GET(request: Request) {
  const url = new URL(request.url);
  const tenantId = toInt(url.searchParams.get('tenant_id'));
  const kind = (url.searchParams.get('kind') ?? '').toUpperCase();
  const q = (url.searchParams.get('q') ?? '').trim();
  if (tenantId === null || !['ORDER', 'INVOICE', 'PO'].includes(kind) || q === '') {
    return NextResponse.json({ error: 'tenant_id, kind (ORDER, INVOICE or PO) and q are required' }, { status: 400 });
  }
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;

  const { data, error } = await (await createClient()).rpc('ar_credit_find', { p_tenant_id: tenantId, p_kind: kind, p_value: q });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
