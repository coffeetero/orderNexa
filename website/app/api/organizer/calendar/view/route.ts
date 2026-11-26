import { NextResponse } from 'next/server';
import { adminRpc } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

const VIEWS = ['day', 'week', 'month', 'agenda', 'mini'];
const isDate = (s: string | null) => s !== null && /^\d{4}-\d{2}-\d{2}$/.test(s);

/**
 * GET /api/organizer/calendar/view?tenant_id=n&view=month&anchor=YYYY-MM-DD&q=text&calendars=1,2,3&production=1
 * → the days and event occurrences of one view, worked out by the database (org_calendar_view_get).
 * calendars omitted = every calendar the user can see; calendars= (empty) = none.
 */
export async function GET(request: Request) {
  const q = new URL(request.url).searchParams;
  const view = q.get('view') ?? 'month';
  if (!VIEWS.includes(view)) return NextResponse.json({ error: 'Invalid view' }, { status: 400 });
  const anchor = q.get('anchor');
  if (anchor && !isDate(anchor)) return NextResponse.json({ error: 'Invalid date' }, { status: 400 });
  let ids: number[] | null = null;
  if (q.has('calendars')) {
    const raw = q.get('calendars') ?? '';
    ids = raw === '' ? [] : raw.split(',').map(toInt).filter((n): n is number => n !== null);
  }
  return adminRpc(q.get('tenant_id'), 'org_calendar_view_get', {
    p_view: view,
    p_anchor: anchor || null,
    p_search: (q.get('q') ?? '').slice(0, 100) || null,
    p_calendar_ids: ids,
    p_production: q.get('production') !== '0',
  });
}
