import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { requireStaff, toInt } from '@/lib/api/nav';
import { recentTypesFor, type RecentRow } from '@/lib/nav-records';
import { selectQuickAccess, type ActionRow } from '@/lib/quick-access';

export const dynamic = 'force-dynamic';

/**
 * GET /api/nav/sidebar?tenant_id=<n>&module=<Orders|Customers|Inventory|Production>
 * → { data: { quickAccess: string[], pinned: string[], recents: RecentRow[] } }
 * Quick Access hrefs are ranked/filtered here (built + authorized only); recents are per user and tenant.
 */
export async function GET(request: Request) {
  const url = new URL(request.url);
  const tenantId = toInt(url.searchParams.get('tenant_id'));
  if (tenantId === null) {
    return NextResponse.json({ error: 'Invalid or missing tenant_id' }, { status: 400 });
  }

  const auth = await requireStaff();
  if (!auth.ok) return auth.response;

  const types = recentTypesFor(url.searchParams.get('module'));

  const supabase = createClient();
  const { data, error } = await supabase.rpc('fnd_nav_sidebar_get', {
    p_tenant_id: tenantId,
    p_types: types.length > 0 ? types : [],
    p_limit: 5,
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });

  const payload = (data ?? {}) as { actions?: ActionRow[]; recents?: RecentRow[] };
  const actions = Array.isArray(payload.actions) ? payload.actions : [];
  const allowed = new Set(auth.allowed.map((a) => a.href));

  return NextResponse.json({
    data: {
      quickAccess: selectQuickAccess(actions, auth.allowed),
      pinned: actions
        .filter((a) => a.is_pinned && allowed.has(a.action_key))
        .sort((a, b) => (a.pin_order ?? 99) - (b.pin_order ?? 99))
        .map((a) => a.action_key),
      recents: types.length > 0 && Array.isArray(payload.recents) ? payload.recents : [],
    },
  });
}
