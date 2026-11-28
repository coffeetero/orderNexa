import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { requireStaff, toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * GET /api/dashboard/address-review?tenant_id=n
 * → customer addresses needing attention (fnd_address_review_get): { suggestions, not_found, no_bill, no_ship, total, customer_ids }
 */
export async function GET(request: Request): Promise<NextResponse> {
  const tenantId = toInt(new URL(request.url).searchParams.get('tenant_id'));
  if (tenantId === null) return NextResponse.json({ error: 'tenant_id is required' }, { status: 400 });
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;
  const { data, error } = await (await createClient()).rpc('fnd_address_review_get', { p_tenant_id: tenantId });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
