import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * GET    /api/organizer/tasks/lists?tenant_id=n                   → lists, view counts, assignable users (org_task_lists_get)
 * POST   /api/organizer/tasks/lists { tenant_id, list }           → creates or changes a list (org_task_list_save)
 * POST   /api/organizer/tasks/lists { tenant_id, clear_completed } → deletes a list's completed tasks (org_tasks_clear_completed)
 * DELETE /api/organizer/tasks/lists?tenant_id=n&id=n              → deletes a list and its tasks (org_task_list_delete)
 */
export async function GET(request: Request) {
  return adminRpc(new URL(request.url).searchParams.get('tenant_id'), 'org_task_lists_get', {});
}

export async function POST(request: Request) {
  const body = await readBody(request);
  if (!body) return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  if ('clear_completed' in body) {
    const id = toInt(body.clear_completed);
    if (id === null) return NextResponse.json({ error: 'Invalid list id' }, { status: 400 });
    return adminRpc(body.tenant_id, 'org_tasks_clear_completed', { p_list_id: id });
  }
  if (!body.list || typeof body.list !== 'object') return NextResponse.json({ error: 'The list is missing' }, { status: 400 });
  return adminRpc(body.tenant_id, 'org_task_list_save', { p_list: body.list });
}

export async function DELETE(request: Request) {
  const q = new URL(request.url).searchParams;
  const id = toInt(q.get('id'));
  if (id === null) return NextResponse.json({ error: 'Invalid id' }, { status: 400 });
  return adminRpc(q.get('tenant_id'), 'org_task_list_delete', { p_list_id: id });
}
