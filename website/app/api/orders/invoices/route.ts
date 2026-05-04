import { NextResponse } from 'next/server';
import { createClient, getSessionUser } from '@/lib/supabase/server';

export const dynamic = 'force-dynamic';

/**
 * GET /api/orders/invoices?tenant_id=<n>&customer_id=<n>&production_date=<YYYY-MM-DD>&production_code=<AM|PM|SPECIAL>
 *
 * Returns the AR invoice and linked production orders for the given
 * customer + production date + window, or { data: null } when none exist.
 */
export async function GET(request: Request) {
  const url = new URL(request.url);

  const tenantIdRaw = url.searchParams.get('tenant_id');
  const customerIdRaw = url.searchParams.get('customer_id');
  const productionDate = url.searchParams.get('production_date');
  const productionCode = url.searchParams.get('production_code');

  if (!tenantIdRaw || !customerIdRaw || !productionDate || !productionCode) {
    return NextResponse.json(
      { error: 'tenant_id, customer_id, production_date and production_code are required' },
      { status: 400 },
    );
  }

  const p_tenant_id = parseInt(tenantIdRaw, 10);
  const p_customer_id = parseInt(customerIdRaw, 10);

  if (!Number.isFinite(p_tenant_id) || !Number.isFinite(p_customer_id)) {
    return NextResponse.json({ error: 'Invalid tenant_id or customer_id' }, { status: 400 });
  }

  const user = await getSessionUser();
  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const supabase = createClient();
  const { data, error } = await supabase.rpc('om_get_invoices', {
    p_tenant_id,
    p_customer_id,
    p_production_date: productionDate,
    p_production_code: productionCode,
  });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 400 });
  }

  return NextResponse.json({ data });
}
