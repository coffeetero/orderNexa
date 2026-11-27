import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * PATCH  /api/organizer/tasks/:id { tenant_id, completed: bool }               → done / not done; repeats create the next (org_task_complete)
 * PATCH  /api/organizer/tasks/:id { tenant_id, move: { parent_task_id, index } } → reorder, indent, outdent (org_task_move)
 * PATCH  /api/organizer/tasks/:id { tenant_id, restore: true }                → undo a delete (org_task_delete)
 * DELETE /api/organizer/tasks/:id?tenant_id=n                                 → deletes with its subtasks (org_task_delete)
 */
export async function PATCH(request: Request, props: { params: Promise<{ id: string }> }) {
  const params = await props.params;
  const id = toInt(params.id);
  if (id === null) return NextResponse.json({ error: 'Invalid id' }, { status: 400 });
  const body = await readBody(request);
  if (!body) return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  if (typeof body.completed === 'boolean') {
    return adminRpc(body.tenant_id, 'org_task_complete', { p_task_id: id, p_done: body.completed });
  }
  if (body.move && typeof body.move === 'object') {
    const m = body.move as Record<string, unknown>;
    return adminRpc(body.tenant_id, 'org_task_move', { p_task_id: id, p_parent_task_id: toInt(m.parent_task_id), p_index: toInt(m.index) ?? 0 });
  }
  if (body.restore === true) {
    return adminRpc(body.tenant_id, 'org_task_delete', { p_task_id: id, p_restore: true });
  }
  return NextResponse.json({ error: 'Nothing to change' }, { status: 400 });
}

export async function DELETE(request: Request, props: { params: Promise<{ id: string }> }) {
  const params = await props.params;
  const id = toInt(params.id);
  if (id === null) return NextResponse.json({ error: 'Invalid id' }, { status: 400 });
  return adminRpc(new URL(request.url).searchParams.get('tenant_id'), 'org_task_delete', { p_task_id: id, p_restore: false });
}
