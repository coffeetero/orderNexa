import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

const VIEWS = ['LIST', 'UPCOMING', 'STARRED', 'ASSIGNED'];

/**
 * GET  /api/organizer/tasks?tenant_id=n&view=LIST&list_id=n      → one list's open and completed tasks (org_tasks_get)
 * GET  /api/organizer/tasks?tenant_id=n&view=UPCOMING|STARRED|ASSIGNED → a view across lists (org_tasks_get)
 * POST /api/organizer/tasks { tenant_id, task }                   → creates or changes a task, only the keys sent (org_task_save)
 */
export async function GET(request: Request) {
  const q = new URL(request.url).searchParams;
  const view = (q.get('view') ?? 'LIST').toUpperCase();
  if (!VIEWS.includes(view)) return NextResponse.json({ error: 'Unknown view' }, { status: 400 });
  const listId = toInt(q.get('list_id'));
  if (view === 'LIST' && listId === null) return NextResponse.json({ error: 'Invalid list_id' }, { status: 400 });
  return adminRpc(q.get('tenant_id'), 'org_tasks_get', { p_view: view, p_list_id: listId });
}

export async function POST(request: Request) {
  const body = await readBody(request);
  if (!body) return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  if (!body.task || typeof body.task !== 'object') return NextResponse.json({ error: 'The task is missing' }, { status: 400 });
  return adminRpc(body.tenant_id, 'org_task_save', { p_task: body.task });
}
