import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { requireStaff, toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

const isDate = (v: unknown): v is string => typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v);

/**
 * GET  /api/call-up?tenant_id&date → the day's Call Up List (om_call_up_list_get)
 * POST /api/call-up { tenant_id, customer_id, date, called } → ticks or unticks Called for the customer on that date
 */
export async function GET(request: Request): Promise<NextResponse> {
  const url = new URL(request.url);
  const tenantId = toInt(url.searchParams.get('tenant_id'));
  const date = url.searchParams.get('date');
  if (tenantId === null || !isDate(date)) {
    return NextResponse.json({ error: 'tenant_id and date (YYYY-MM-DD) are required' }, { status: 400 });
  }
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;
  const { data, error } = await (await createClient()).rpc('om_call_up_list_get', { p_tenant_id: tenantId, p_date: date });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data: data ?? [] });
}

export async function POST(request: Request): Promise<NextResponse> {
  let body: Record<string, unknown>;
  try {
    body = (await request.json()) as Record<string, unknown>;
  } catch {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  }
  const tenantId = toInt(body.tenant_id);
  const customerId = toInt(body.customer_id);
  if (tenantId === null || customerId === null || !isDate(body.date) || typeof body.called !== 'boolean') {
    return NextResponse.json({ error: 'tenant_id, customer_id, date and called are required' }, { status: 400 });
  }
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;
  const { data, error } = await (await createClient()).rpc('om_call_up_called_set', {
    p_tenant_id: tenantId, p_customer_id: customerId, p_date: body.date, p_called: body.called,
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
