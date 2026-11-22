import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { requireStaff, toInt } from '@/lib/api/nav';
import { isValidActionKey, normalizeRecord } from '@/lib/nav-records';

export const dynamic = 'force-dynamic';

/**
 * POST /api/nav/touch  { tenant_id, action_key?, record?: { type, key, label, sublabel? } }
 * Fire-and-forget usage tracking: bumps the user's menu-action count and/or records a recently opened record.
 */
export async function POST(request: Request) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  }
  if (typeof body !== 'object' || body === null || Array.isArray(body)) {
    return NextResponse.json({ error: 'Request body must be a JSON object' }, { status: 400 });
  }

  const o = body as Record<string, unknown>;
  const tenantId = toInt(o.tenant_id);
  if (tenantId === null) return NextResponse.json({ error: 'Invalid tenant_id' }, { status: 400 });

  const hasAction = o.action_key !== undefined && o.action_key !== null;
  const hasRecord = o.record !== undefined && o.record !== null;
  if (!hasAction && !hasRecord) return NextResponse.json({ error: 'Nothing to record' }, { status: 400 });

  const auth = await requireStaff();
  if (!auth.ok) return auth.response;

  let actionKey: string | null = null;
  if (hasAction) {
    if (!isValidActionKey(o.action_key) || !auth.allowed.some((a) => a.href === o.action_key)) {
      return NextResponse.json({ error: 'Unknown action' }, { status: 400 });
    }
    actionKey = o.action_key;
  }

  const record = hasRecord ? normalizeRecord(o.record) : null;
  if (hasRecord && !record) return NextResponse.json({ error: 'Invalid record' }, { status: 400 });

  const supabase = createClient();
  const { error } = await supabase.rpc('fnd_nav_touch', {
    p_tenant_id: tenantId,
    p_action_key: actionKey,
    p_record_type: record?.type ?? null,
    p_record_key: record?.key ?? null,
    p_label: record?.label ?? null,
    p_sublabel: record?.sublabel ?? null,
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });

  return NextResponse.json({ ok: true });
}
