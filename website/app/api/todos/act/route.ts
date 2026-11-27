import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { requireStaff, toInt } from '@/lib/api/nav';
import { readBody } from '@/lib/api/admin-rpc';

export const dynamic = 'force-dynamic';

const ACTIONS = ['DEACTIVATE', 'STILL_HERE', 'EXPECTED'] as const;

/**
 * POST /api/todos/act { tenant_id, user_id, action: DEACTIVATE | STILL_HERE | EXPECTED, city?, region?, country?, event_id? } → { ok: true }
 * Acts on a security To-Do (fnd_security_signal_act). The database refuses one's own signals, non-administrators and a
 * change that would leave nobody able to manage users.
 */
export async function POST(request: Request) {
  const body = await readBody(request);
  const tenantId = toInt(body?.tenant_id);
  const userId = toInt(body?.user_id);
  const action = typeof body?.action === 'string' ? body.action : '';
  if (tenantId === null || userId === null || !(ACTIONS as readonly string[]).includes(action)) {
    return NextResponse.json({ error: 'tenant_id, user_id and a valid action are required' }, { status: 400 });
  }
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;
  const str = (v: unknown) => (typeof v === 'string' && v.trim() ? v.trim() : null);
  const { error } = await (await createClient()).rpc('fnd_security_signal_act', {
    p_tenant_id: tenantId, p_user_id: userId, p_action: action, p_city: str(body?.city), p_region: str(body?.region), p_country: str(body?.country),
    p_event_id: toInt(body?.event_id),
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ ok: true });
}
