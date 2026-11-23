import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { requireStaff } from '@/lib/api/nav';
import { getCurrentTenantId } from '@/lib/supabase/tenant';

export const dynamic = 'force-dynamic';

/** GET /api/health/status → { state: none|never|ok|warning|error, infos, warnings, errors, last_run_at } for the heart icon (state none without access). */
export async function GET() {
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;
  const tenantId = await getCurrentTenantId();
  if (tenantId === null) return NextResponse.json({ data: { state: 'none', infos: 0, warnings: 0, errors: 0, last_run_at: null } });
  const { data, error } = await createClient().rpc('fnd_health_status', { p_tenant_id: tenantId });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
