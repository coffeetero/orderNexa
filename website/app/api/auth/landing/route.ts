import { NextResponse } from 'next/server';
import { headers } from 'next/headers';
import { createClient, getSessionUser } from '@/lib/supabase/server';
import { parseTenantSubdomain } from '@/lib/tenant-subdomain';

export const dynamic = 'force-dynamic';

/**
 * GET /api/auth/landing → { href } where the signed-in user starts (staff: dashboard; customers: their portal on the
 * bakery's address), or { error } when they cannot sign in here.
 */
export async function GET() {
  const user = await getSessionUser();
  if (!user) return NextResponse.json({ error: 'Not signed in' }, { status: 401 });
  const { data, error } = await (await createClient()).rpc('fnd_user_landing_get');
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  const landing = data as { user_type: string; account_slug: string | null } | null;
  if (!landing) return NextResponse.json({ error: 'Access Denied: User record not found.' }, { status: 403 });
  if (landing.user_type === 'TENANCY_USER') return NextResponse.json({ href: '/dashboard' });
  if (landing.user_type === 'CUSTOMER_USER') {
    // The customer portal is only served on a tenant host (e.g. alpine.ordernexa.com).
    if (!parseTenantSubdomain((await headers()).get('host') || '')) {
      return NextResponse.json({ error: "Customer accounts sign in from your bakery's own web address, not this one." }, { status: 403 });
    }
    if (!landing.account_slug) return NextResponse.json({ error: 'Configuration error: No customer account assigned to this user.' }, { status: 403 });
    return NextResponse.json({ href: `/${landing.account_slug}` });
  }
  return NextResponse.json({ error: 'Access Denied: Unrecognized account type.' }, { status: 403 });
}
