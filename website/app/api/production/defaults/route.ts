import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { requireStaff, toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/** GET /api/production/defaults?tenant_id=<n> → { from_date, to_date, production_codes: [{value,label}] } (om_report_defaults_get). */
export async function GET(request: Request) {
  const tenantId = toInt(new URL(request.url).searchParams.get('tenant_id'));
  if (tenantId === null) return NextResponse.json({ error: 'Invalid or missing tenant_id' }, { status: 400 });
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;

  const { data, error } = await createClient().rpc('om_report_defaults_get', { p_tenant_id: tenantId });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
