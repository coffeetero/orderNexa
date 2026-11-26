import { NextResponse } from 'next/server';
import { adminRpc } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * DELETE /api/organizer/calendar/events/:id?tenant_id=n&scope=ONE|FOLLOWING|ALL&occurrence_date=YYYY-MM-DD
 * → deletes the event, or for a repeating event that occurrence / it and later ones / the series (org_event_delete)
 */
export async function DELETE(request: Request, { params }: { params: { id: string } }) {
  const id = toInt(params.id);
  if (id === null) return NextResponse.json({ error: 'Invalid id' }, { status: 400 });
  const q = new URL(request.url).searchParams;
  const scope = q.get('scope') ?? 'ALL';
  if (!['ONE', 'FOLLOWING', 'ALL'].includes(scope)) return NextResponse.json({ error: 'Invalid scope' }, { status: 400 });
  const occ = q.get('occurrence_date');
  if (occ && !/^\d{4}-\d{2}-\d{2}$/.test(occ)) return NextResponse.json({ error: 'Invalid date' }, { status: 400 });
  return adminRpc(q.get('tenant_id'), 'org_event_delete', { p_event_id: id, p_scope: scope, p_occurrence_date: occ || null });
}
