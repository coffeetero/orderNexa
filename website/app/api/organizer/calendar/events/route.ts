import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

const FIELDS = [
  'event_id', 'calendar_id', 'title', 'location', 'notes', 'all_day', 'start_date', 'start_time', 'end_date', 'end_time',
  'repeat_freq', 'repeat_interval', 'repeat_days', 'repeat_until', 'repeat_count', 'scope', 'occurrence_date',
] as const;

/**
 * GET  /api/organizer/calendar/events?tenant_id=n&id=n → one event or series as the dialog edits it (org_event_get)
 * POST /api/organizer/calendar/events { tenant_id, event fields, scope?, occurrence_date? } → creates or changes (org_event_save)
 */
export async function GET(request: Request) {
  const q = new URL(request.url).searchParams;
  const id = toInt(q.get('id'));
  if (id === null) return NextResponse.json({ error: 'Invalid id' }, { status: 400 });
  return adminRpc(q.get('tenant_id'), 'org_event_get', { p_event_id: id });
}

export async function POST(request: Request) {
  const body = await readBody(request);
  if (!body) return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  const payload: Record<string, unknown> = {};
  for (const f of FIELDS) if (body[f] !== undefined) payload[f] = body[f];
  return adminRpc(body.tenant_id, 'org_event_save', { p_payload: payload });
}
