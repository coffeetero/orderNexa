import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { requireStaff, toInt } from '@/lib/api/nav';
import { recentTypesFor, type RecentRow } from '@/lib/nav-records';

export const dynamic = 'force-dynamic';

/**
 * GET /api/nav/sidebar?tenant_id=<n>&module=<Operations|Customers|Inventory>&page=<menu href>
 * → { data: { pinned: string[], recents: RecentRow[] } }
 * pinned = the user's Quick Buttons (authorized only); recents are per user and tenant, lists chosen by page, then module.
 */
export async function GET(request: Request) {
  const url = new URL(request.url);
  const tenantId = toInt(url.searchParams.get('tenant_id'));
  if (tenantId === null) {
    return NextResponse.json({ error: 'Invalid or missing tenant_id' }, { status: 400 });
  }

  const auth = await requireStaff();
  if (!auth.ok) return auth.response;

  const types = recentTypesFor(url.searchParams.get('module'), url.searchParams.get('page'));

  const supabase = createClient();
  const { data, error } = await supabase.rpc('fnd_nav_sidebar_get', {
    p_tenant_id: tenantId,
    p_types: types.length > 0 ? types : [],
    p_limit: 5,
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });

  const payload = (data ?? {}) as { actions?: { action_key: string; is_pinned: boolean; pin_order: number | null }[]; recents?: RecentRow[] };
  const actions = Array.isArray(payload.actions) ? payload.actions : [];
  const allowed = new Set(auth.allowed.map((a) => a.href));

  return NextResponse.json({
    data: {
      pinned: actions
        .filter((a) => a.is_pinned && allowed.has(a.action_key))
        .sort((a, b) => (a.pin_order ?? 99) - (b.pin_order ?? 99))
        .map((a) => a.action_key),
      recents: types.length > 0 && Array.isArray(payload.recents) ? payload.recents : [],
    },
  });
}
