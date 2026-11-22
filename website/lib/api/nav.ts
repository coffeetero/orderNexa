import { NextResponse } from 'next/server';
import { getSessionUser } from '@/lib/supabase/server';
import { getUserAccess } from '@/lib/supabase/access';
import { builtActions, tenantNav, type BuiltAction } from '@/lib/nav-config';

export function toInt(value: unknown): number | null {
  if (typeof value === 'number') return Number.isSafeInteger(value) ? value : null;
  if (typeof value === 'string' && /^\d{1,18}$/.test(value)) return Number(value);
  return null;
}

/** Sidebar/Quick Access is a staff feature. Resolves the signed-in staff user and what they may open. */
export async function requireStaff(): Promise<
  { ok: true; allowed: BuiltAction[] } | { ok: false; response: NextResponse }
> {
  const user = await getSessionUser();
  if (!user) return { ok: false, response: NextResponse.json({ error: 'Unauthorized' }, { status: 401 }) };

  const access = await getUserAccess(user.id);
  if (access.userType !== 'TENANCY_USER') {
    return { ok: false, response: NextResponse.json({ error: 'Forbidden' }, { status: 403 }) };
  }
  return { ok: true, allowed: builtActions(tenantNav, access.userType) };
}
