import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { requireStaff, toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * Customer addresses on the Contacts tab (fnd_customer_addresses.sql).
 * GET   ?tenant_id&customer_id                              → { pickup, inherited_from, addresses, missing_bill, missing_ship }
 * POST  { tenant_id, customer_id, contact_point_id?, address, instructions?, bill?, ship?, validated? }
 *       → add (no id) or save an address card
 * PATCH { tenant_id, customer_id, contact_point_id, action }  → BILL | SHIP | ACCEPT | REJECT | VERIFY | REMOVE
 */
export async function GET(request: Request): Promise<NextResponse> {
  const q = new URL(request.url).searchParams;
  const tenantId = toInt(q.get('tenant_id'));
  const customerId = toInt(q.get('customer_id'));
  if (tenantId === null || customerId === null) return NextResponse.json({ error: 'tenant_id and customer_id are required' }, { status: 400 });
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;
  const { data, error } = await (await createClient()).rpc('fnd_customer_addresses_get', { p_tenant_id: tenantId, p_customer_id: customerId });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}

async function body(request: Request): Promise<Record<string, unknown> | null> {
  try { return (await request.json()) as Record<string, unknown>; } catch { return null; }
}

export async function POST(request: Request): Promise<NextResponse> {
  const b = await body(request);
  const tenantId = toInt(b?.tenant_id);
  const customerId = toInt(b?.customer_id);
  if (!b || tenantId === null || customerId === null) return NextResponse.json({ error: 'tenant_id and customer_id are required' }, { status: 400 });
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;
  const { data, error } = await (await createClient()).rpc('fnd_customer_address_save', {
    p_tenant_id: tenantId, p_customer_id: customerId, p_contact_point_id: toInt(b.contact_point_id), p_address: typeof b.address === 'string' ? b.address : '',
    p_instructions: typeof b.instructions === 'string' ? b.instructions : null,
    p_bill: typeof b.bill === 'boolean' ? b.bill : null, p_ship: typeof b.ship === 'boolean' ? b.ship : null,
    p_validated: typeof b.validated === 'boolean' ? b.validated : null,
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}

export async function PATCH(request: Request): Promise<NextResponse> {
  const b = await body(request);
  const tenantId = toInt(b?.tenant_id);
  const customerId = toInt(b?.customer_id);
  const pointId = toInt(b?.contact_point_id);
  if (!b || tenantId === null || customerId === null || pointId === null) {
    return NextResponse.json({ error: 'tenant_id, customer_id and contact_point_id are required' }, { status: 400 });
  }
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;
  const { data, error } = await (await createClient()).rpc('fnd_customer_address_action', {
    p_tenant_id: tenantId, p_customer_id: customerId, p_contact_point_id: pointId, p_action: String(b.action ?? ''),
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
