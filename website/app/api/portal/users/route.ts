import { NextResponse } from 'next/server';
import { createClient, getSessionUser } from '@/lib/supabase/server';
import { getCurrentTenantId } from '@/lib/supabase/tenant';
import { readBody } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

const ids = (v: unknown) => (Array.isArray(v) ? v.map(toInt).filter((n): n is number => n !== null) : []);

async function context() {
  const user = await getSessionUser();
  if (!user) return { error: NextResponse.json({ error: 'Unauthorized' }, { status: 401 }) };
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) return { error: NextResponse.json({ error: 'No company found' }, { status: 400 }) };
  return { tenantId, db: createClient() };
}

/**
 * GET /api/portal/users → { data: { users, roles } }
 * A customer administrator's own users and the roles they may give (fnd_portal_users_get / fnd_portal_roles_get). The
 * database refuses anyone without Users access in the portal.
 */
export async function GET() {
  const c = await context();
  if ('error' in c) return c.error;
  const [users, roles] = await Promise.all([
    c.db.rpc('fnd_portal_users_get', { p_tenant_id: c.tenantId }),
    c.db.rpc('fnd_portal_roles_get', { p_tenant_id: c.tenantId }),
  ]);
  const err = users.error ?? roles.error;
  if (err) return NextResponse.json({ error: err.message }, { status: 403 });
  return NextResponse.json({ data: { users: users.data, roles: roles.data } });
}

/**
 * POST /api/portal/users
 *   { action: 'create', email, user_name, role_ids } → { data: user_id }
 *   { action: 'save', user_id, role_ids, is_active }  → { data: null }
 * Customer users of the administrator's own account only. An email held by the bakery's staff is refused; the bakery is told
 * (fnd_email_conflict_record), so a person who left without being deactivated shows up on its Dashboard.
 */
export async function POST(request: Request) {
  const c = await context();
  if ('error' in c) return c.error;
  const body = await readBody(request);
  if (body?.action === 'create') {
    const email = typeof body.email === 'string' ? body.email : '';
    const { data, error } = await c.db.rpc('fnd_user_create', {
      p_tenant_id: c.tenantId, p_email: email, p_user_name: typeof body.user_name === 'string' ? body.user_name : '',
      p_user_type: 'CUSTOMER_USER', p_customer_id: null, p_role_ids: ids(body.role_ids), p_group_ids: [],
    });
    if (error) {
      if ((error.details ?? '').startsWith('EMAIL_HELD_BY')) await c.db.rpc('fnd_email_conflict_record', { p_tenant_id: c.tenantId, p_email: email });
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    return NextResponse.json({ data });
  }
  if (body?.action === 'save') {
    const userId = toInt(body.user_id);
    if (userId === null) return NextResponse.json({ error: 'user_id is required' }, { status: 400 });
    const { error } = await c.db.rpc('fnd_portal_user_save', {
      p_tenant_id: c.tenantId, p_user_id: userId, p_role_ids: ids(body.role_ids), p_is_active: body.is_active !== false,
    });
    if (error) return NextResponse.json({ error: error.message }, { status: 400 });
    return NextResponse.json({ data: null });
  }
  return NextResponse.json({ error: 'Unknown action' }, { status: 400 });
}
