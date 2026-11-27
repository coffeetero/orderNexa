import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { requireStaff, toInt } from '@/lib/api/nav';
import { readBody } from '@/lib/api/admin-rpc';

export const dynamic = 'force-dynamic';

/**
 * Vendor contacts: the shared contact records (fnd_contacts / fnd_contact_points) with source_table 'po_vendors'.
 * GET  /api/purchasing/vendors/contacts?tenant_id=n&vendor_id=n            → contacts of a vendor (fnd_contacts_get)
 * POST /api/purchasing/vendors/contacts { tenant_id, vendor_id, contact } → saves one contact (fnd_contacts_save)
 * The contact functions check the tenant only, so Purchasing access (purchasing.vendors) is checked here first.
 */
type Guarded =
  | { ok: false; response: NextResponse }
  | { ok: true; supabase: ReturnType<typeof createClient>; tenantId: number; vendorId: number };

async function guard(tenantRaw: unknown, vendorRaw: unknown, action: 'R' | 'W'): Promise<Guarded> {
  const tenantId = toInt(tenantRaw);
  const vendorId = toInt(vendorRaw);
  if (tenantId === null || vendorId === null) {
    return { ok: false, response: NextResponse.json({ error: 'Invalid or missing tenant_id / vendor_id' }, { status: 400 }) };
  }
  const auth = await requireStaff();
  if (!auth.ok) return { ok: false, response: auth.response };
  const supabase = createClient();
  const { data: ok } = await supabase.rpc('fnd_has_access', { p_area: 'purchasing.vendors', p_action: action });
  if (ok !== true) return { ok: false, response: NextResponse.json({ error: 'You do not have access to vendors' }, { status: 403 }) };
  return { ok: true, supabase, tenantId, vendorId };
}

export async function GET(request: Request): Promise<NextResponse> {
  const q = new URL(request.url).searchParams;
  const g = await guard(q.get('tenant_id'), q.get('vendor_id'), 'R');
  if (!g.ok) return g.response;
  const { data, error } = await g.supabase.rpc('fnd_contacts_get', {
    p_tenant_id: g.tenantId, p_entity_id: g.vendorId, p_source_table: 'po_vendors',
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data: data ?? [] });
}

export async function POST(request: Request): Promise<NextResponse> {
  const body = await readBody(request);
  if (!body) return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  const g = await guard(body.tenant_id, body.vendor_id, 'W');
  if (!g.ok) return g.response;
  const { data, error } = await g.supabase.rpc('fnd_contacts_save', {
    p_tenant_id: g.tenantId, p_entity_id: g.vendorId, p_source_table: 'po_vendors', p_contact: body.contact,
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
