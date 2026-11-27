import { NextResponse } from 'next/server';
import { headers } from 'next/headers';
import { createClient } from '@/lib/supabase/server';
import { parseTenantSubdomain } from '@/lib/tenant-subdomain';

/** Records the tenancy chosen for this session. The browser then refreshes its session to receive the new claim. */
export async function POST(request: Request) {
  const body = await request.json().catch(() => ({}));
  const tenantId = Number(body?.tenant_id);
  if (!Number.isFinite(tenantId)) return NextResponse.json({ error: 'tenant_id is required' }, { status: 400 });
  const { error } = await (await createClient()).rpc('fnd_user_select_tenant', {
    p_tenant_id: tenantId,
    p_host_slug: parseTenantSubdomain((await headers()).get('host') || ''),
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 403 });
  return NextResponse.json({ ok: true });
}
