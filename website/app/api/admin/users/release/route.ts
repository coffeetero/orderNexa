import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { createServiceClient } from '@/lib/supabase/service';
import { readBody } from '@/lib/api/admin-rpc';
import { requireStaff, toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * POST /api/admin/users/release { tenant_id, user_id } → { data: { released: true } }
 * Ends a deactivated staff member so their email can be used for a new account (fnd_user_release_email): their record is
 * kept unchanged for history. Their old sign-in account is retired: disabled for good and its address replaced by a
 * placeholder, so the email is free for a new sign-in and the old audit trail stays with the old record. Safe to repeat.
 */
export async function POST(request: Request) {
  const body = await readBody(request);
  const tenantId = toInt(body?.tenant_id);
  const userId = toInt(body?.user_id);
  if (tenantId === null || userId === null) return NextResponse.json({ error: 'tenant_id and user_id are required' }, { status: 400 });
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;

  const { data, error } = await (await createClient()).rpc('fnd_user_release_email', { p_tenant_id: tenantId, p_user_id: userId });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  const authUserId = data as string | null;
  if (authUserId) {
    const upd = await createServiceClient().auth.admin.updateUserById(authUserId, {
      email: `ended-${userId}@invalid.ordernexa.com`, email_confirm: true, ban_duration: '876000h',
    });
    if (upd.error && !/not found/i.test(upd.error.message)) {
      return NextResponse.json({ error: `The account was ended, but its old sign-in could not be retired: ${upd.error.message}. Try again.` }, { status: 500 });
    }
  }
  return NextResponse.json({ data: { released: true } });
}
