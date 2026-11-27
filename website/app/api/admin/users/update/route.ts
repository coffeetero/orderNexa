import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { createServiceClient } from '@/lib/supabase/service';
import { readBody } from '@/lib/api/admin-rpc';
import { requireStaff, toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * POST /api/admin/users/update { tenant_id, user_id, user_name, email, customer_id? } → { data: { user_id } }
 * The database decides what may change (email only until the person has signed in). When the email changed, the
 * never-used login made for the old address is removed.
 */
export async function POST(request: Request) {
  const body = await readBody(request);
  const tenantId = toInt(body?.tenant_id);
  const userId = toInt(body?.user_id);
  if (!body || tenantId === null || userId === null) return NextResponse.json({ error: 'tenant_id and user_id are required' }, { status: 400 });
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;

  const { data, error } = await (await createClient()).rpc('fnd_user_update', {
    p_tenant_id: tenantId, p_user_id: userId,
    p_user_name: typeof body.user_name === 'string' ? body.user_name : '',
    p_email: typeof body.email === 'string' ? body.email : '',
    p_customer_id: toInt(body.customer_id),
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  const orphan = (data as { orphan_auth_user_id: string | null }).orphan_auth_user_id;
  if (orphan) {
    const del = await createServiceClient().auth.admin.deleteUser(orphan);
    if (del.error) console.error('[users/update] old login not removed:', del.error.message);
  }
  return NextResponse.json({ data: { user_id: userId } });
}
