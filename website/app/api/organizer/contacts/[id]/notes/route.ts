import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * POST   /api/organizer/contacts/:id/notes { tenant_id, note_id?, note_text, is_pinned } → adds / edits a note (org_contact_note_save)
 * DELETE /api/organizer/contacts/:id/notes?tenant_id=n&note_id=n → removes a note (org_contact_note_delete)
 */
export async function POST(request: Request, props: { params: Promise<{ id: string }> }) {
  const params = await props.params;
  const id = toInt(params.id);
  if (id === null) return NextResponse.json({ error: 'Invalid id' }, { status: 400 });
  const body = await readBody(request);
  if (!body) return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  return adminRpc(body.tenant_id, 'org_contact_note_save', {
    p_contact_id: id,
    p_note: { note_id: body.note_id ?? null, note_text: body.note_text ?? null, is_pinned: body.is_pinned === true },
  });
}

export async function DELETE(request: Request) {
  const q = new URL(request.url).searchParams;
  const noteId = toInt(q.get('note_id'));
  if (noteId === null) return NextResponse.json({ error: 'Invalid note_id' }, { status: 400 });
  return adminRpc(q.get('tenant_id'), 'org_contact_note_delete', { p_note_id: noteId });
}
