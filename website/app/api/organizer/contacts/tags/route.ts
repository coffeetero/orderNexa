import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * GET    /api/organizer/contacts/tags?tenant_id=n                      → tags with contact counts (org_contact_tags_get)
 * POST   /api/organizer/contacts/tags { tenant_id, tag_id?, tag_name, tag_color } → creates / renames (org_contact_tag_save)
 * DELETE /api/organizer/contacts/tags?tenant_id=n&id=n                 → deletes a tag (org_contact_tag_delete)
 */
export async function GET(request: Request) {
  return adminRpc(new URL(request.url).searchParams.get('tenant_id'), 'org_contact_tags_get', {});
}

export async function POST(request: Request) {
  const body = await readBody(request);
  if (!body) return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  return adminRpc(body.tenant_id, 'org_contact_tag_save', {
    p_tag: { tag_id: body.tag_id ?? null, tag_name: body.tag_name ?? null, tag_color: body.tag_color ?? null },
  });
}

export async function DELETE(request: Request) {
  const q = new URL(request.url).searchParams;
  const id = toInt(q.get('id'));
  if (id === null) return NextResponse.json({ error: 'Invalid id' }, { status: 400 });
  return adminRpc(q.get('tenant_id'), 'org_contact_tag_delete', { p_tag_id: id });
}
