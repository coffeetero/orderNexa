import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { readBody } from '@/lib/api/admin-rpc';
import { requireStaff, toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * POST /api/admin/users/create { tenant_id, email, user_name, user_type, customer_id?, role_ids, group_ids } → { data: user_id }
 * When the email belongs to a former (deactivated) staff member, the answer also carries release_user_id, so the screen can
 * offer to release the email (/api/admin/users/release) and add again.
 */
export async function POST(request: Request) {
  const body = await readBody(request);
  if (!body) return NextResponse.json({ error: 'Invalid body' }, { status: 400 });
  const tenantId = toInt(body.tenant_id);
  if (tenantId === null) return NextResponse.json({ error: 'Invalid or missing tenant_id' }, { status: 400 });
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;
  const ids = (v: unknown) => (Array.isArray(v) ? v.map(toInt).filter((n): n is number => n !== null) : []);
  const db = await createClient();
  const email = typeof body.email === 'string' ? body.email : '';
  const { data, error } = await db.rpc('fnd_user_create', {
    p_tenant_id: tenantId,
    p_email: email,
    p_user_name: typeof body.user_name === 'string' ? body.user_name : '',
    p_user_type: typeof body.user_type === 'string' ? body.user_type : '',
    p_customer_id: toInt(body.customer_id),
    p_role_ids: ids(body.role_ids),
    p_group_ids: ids(body.group_ids),
  });
  if (error) {
    const detail = error.details ?? '';
    const former = /^EMAIL_HELD_BY_FORMER_STAFF:(\d+)$/.exec(detail);
    if (detail === 'EMAIL_HELD_BY_STAFF') await db.rpc('fnd_email_conflict_record', { p_tenant_id: tenantId, p_email: email });
    return NextResponse.json({ error: error.message, ...(former ? { release_user_id: Number(former[1]) } : {}) }, { status: 400 });
  }
  return NextResponse.json({ data });
}
