import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * PATCH  /api/organizer/contacts/:id { tenant_id, is_favorite } → marks / unmarks a favourite (org_contact_favorite_set)
 * DELETE /api/organizer/contacts/:id?tenant_id=n → deletes, or deactivates when it has notes (org_contact_delete)
 */
export async function PATCH(request: Request, props: { params: Promise<{ id: string }> }) {
  const params = await props.params;
  const id = toInt(params.id);
  if (id === null) return NextResponse.json({ error: 'Invalid id' }, { status: 400 });
  const body = await readBody(request);
  if (!body) return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  return adminRpc(body.tenant_id, 'org_contact_favorite_set', { p_contact_id: id, p_is_favorite: body.is_favorite === true });
}

export async function DELETE(request: Request, props: { params: Promise<{ id: string }> }) {
  const params = await props.params;
  const id = toInt(params.id);
  if (id === null) return NextResponse.json({ error: 'Invalid id' }, { status: 400 });
  return adminRpc(new URL(request.url).searchParams.get('tenant_id'), 'org_contact_delete', { p_contact_id: id });
}
