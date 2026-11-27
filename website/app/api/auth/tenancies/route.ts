import { NextResponse } from 'next/server';
import { headers } from 'next/headers';
import { createClient } from '@/lib/supabase/server';
import { parseTenantSubdomain } from '@/lib/tenant-subdomain';

/** The signed-in user's tenancies for the picker, plus the tenant implied by the web address (if any). */
export async function GET() {
  const { data, error } = await (await createClient()).rpc('fnd_user_tenancies_get');
  if (error) return NextResponse.json({ error: error.message }, { status: 401 });
  return NextResponse.json({ tenancies: data ?? [], host_slug: parseTenantSubdomain((await headers()).get('host') || '') });
}
