import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * GET  /api/organizer/contacts?tenant_id=n                 → the address book list (org_contacts_get)
 * GET  /api/organizer/contacts?tenant_id=n&id=n            → one contact with photo and notes timeline (org_contact_get)
 * POST /api/organizer/contacts { tenant_id, contact }      → creates or saves a contact (org_contact_save)
 * POST /api/organizer/contacts { tenant_id, export: ids? } → full details for vCard / CSV export (org_contacts_export)
 */
export async function GET(request: Request) {
  const q = new URL(request.url).searchParams;
  if (q.has('id')) {
    const id = toInt(q.get('id'));
    if (id === null) return NextResponse.json({ error: 'Invalid id' }, { status: 400 });
    return adminRpc(q.get('tenant_id'), 'org_contact_get', { p_contact_id: id });
  }
  return adminRpc(q.get('tenant_id'), 'org_contacts_get', {});
}

export async function POST(request: Request) {
  const body = await readBody(request);
  if (!body) return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  if ('export' in body) {
    const ids = Array.isArray(body.export) ? body.export.map(toInt).filter((n): n is number => n !== null) : null;
    return adminRpc(body.tenant_id, 'org_contacts_export', { p_contact_ids: ids });
  }
  if (!body.contact || typeof body.contact !== 'object') return NextResponse.json({ error: 'The contact is missing' }, { status: 400 });
  return adminRpc(body.tenant_id, 'org_contact_save', { p_contact: body.contact });
}
