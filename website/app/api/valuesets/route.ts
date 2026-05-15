import { NextResponse } from 'next/server';
import { createClient, getSessionUser } from '@/lib/supabase/server';

export const dynamic = 'force-dynamic';

/**
 * GET /api/valuesets?tenant_id=N&code=PRODUCTIONCODE
 * Returns active, enabled valueset values ordered by display_order.
 */
export async function GET(request: Request) {
  const url      = new URL(request.url);
  const tenantId = Number(url.searchParams.get('tenant_id'));
  const code     = url.searchParams.get('code');

  if (!Number.isFinite(tenantId) || !code) {
    return NextResponse.json({ error: 'Missing tenant_id or code' }, { status: 400 });
  }

  const user = await getSessionUser();
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const supabase = createClient();

  const { data: vs, error: vsErr } = await supabase
    .from('fnd_valuesets')
    .select('valueset_id')
    .eq('tenant_id', tenantId)
    .eq('valueset_code', code)
    .eq('is_active', true)
    .single();

  if (vsErr || !vs) return NextResponse.json({ data: [] });

  const { data, error } = await supabase
    .from('fnd_valueset_values')
    .select('value, label, display_order')
    .eq('tenant_id', tenantId)
    .eq('valueset_id', vs.valueset_id)
    .eq('is_disabled', false)
    .order('display_order');

  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data: data ?? [] });
}
