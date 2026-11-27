import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { requireStaff, toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/** GET /api/invoices/lookup?tenant_id=<n>&q=<invoice or order number> → ar_document_lookup: matching invoices with lines and credits. */
export async function GET(request: Request) {
  const url = new URL(request.url);
  const tenantId = toInt(url.searchParams.get('tenant_id'));
  const q = url.searchParams.get('q') ?? '';
  if (tenantId === null || q.trim() === '') {
    return NextResponse.json({ error: 'tenant_id and q (an invoice or order number) are required' }, { status: 400 });
  }
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;

  const { data, error } = await (await createClient()).rpc('ar_document_lookup', { p_tenant_id: tenantId, p_search: q });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
