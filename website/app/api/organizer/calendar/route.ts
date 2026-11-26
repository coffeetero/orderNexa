import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';

export const dynamic = 'force-dynamic';

/**
 * GET  /api/organizer/calendar?tenant_id=n → calendars the user can see, time zone, today, rights (org_calendars_get)
 * POST /api/organizer/calendar { tenant_id, calendar_id?, calendar_name, calendar_color, visibility } → saves a calendar (org_calendar_save)
 */
export async function GET(request: Request) {
  return adminRpc(new URL(request.url).searchParams.get('tenant_id'), 'org_calendars_get', {});
}

export async function POST(request: Request) {
  const body = await readBody(request);
  if (!body) return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  return adminRpc(body.tenant_id, 'org_calendar_save', {
    p_payload: {
      calendar_id: body.calendar_id ?? null,
      calendar_name: typeof body.calendar_name === 'string' ? body.calendar_name.slice(0, 60) : null,
      calendar_color: typeof body.calendar_color === 'string' ? body.calendar_color : null,
      visibility: body.visibility === 'PRIVATE' ? 'PRIVATE' : 'SHARED',
    },
  });
}
