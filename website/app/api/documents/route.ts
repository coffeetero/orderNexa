import { NextResponse } from 'next/server';
import { createClient, getSessionUser } from '@/lib/supabase/server';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/** GET /api/documents?tenant_id=n[&customer_id=n][&types=INVOICE,STATEMENT] → saved documents, newest first (no file bytes). Row security decides what is visible. */
export async function GET(request: Request) {
  const q = new URL(request.url).searchParams;
  const tenantId = toInt(q.get('tenant_id'));
  if (tenantId === null) return NextResponse.json({ error: 'Invalid or missing tenant_id' }, { status: 400 });
  if (!(await getSessionUser())) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  const types = q.get('types')?.split(',').map((t) => t.trim().toUpperCase()).filter(Boolean);
  const { data, error } = await (await createClient()).rpc('fnd_documents_get', {
    p_tenant_id: tenantId, p_customer_id: toInt(q.get('customer_id')), p_types: types && types.length ? types : null,
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
