import { NextResponse } from 'next/server';
import { headers } from 'next/headers';
import { createClient, getSessionUser } from '@/lib/supabase/server';
import { getCurrentTenantId } from '@/lib/supabase/tenant';

export const dynamic = 'force-dynamic';

/** A header value the hosting provider URL-encodes (city names with spaces or accents). */
const decoded = (v: string | null) => { if (!v) return null; try { return decodeURIComponent(v); } catch { return v; } };

/**
 * POST /api/activity → { ok: true }
 * "This person is using BPS": records the day, IP address and approximate place (from the hosting provider's location
 * headers; nothing is looked up elsewhere) in fnd_user_access_log. Sent by the browser at most every few minutes, from staff
 * and customer screens alike. Feeds Last activity on Admin > Users and the security To-Dos.
 */
export async function POST() {
  const user = await getSessionUser();
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) return NextResponse.json({ ok: true });

  const h = await headers();
  const ip = (h.get('x-forwarded-for') || h.get('x-real-ip') || '').split(',')[0].trim();
  const { error } = await (await createClient()).rpc('fnd_activity_record', {
    p_tenant_id: tenantId,
    p_ip: ip || null,
    p_city: decoded(h.get('x-vercel-ip-city')),
    p_region: decoded(h.get('x-vercel-ip-country-region')),
    p_country: decoded(h.get('x-vercel-ip-country')),
    p_user_agent: h.get('user-agent'),
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ ok: true });
}
