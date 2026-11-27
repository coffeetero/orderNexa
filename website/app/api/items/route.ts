import { NextResponse } from 'next/server';
import { createClient, getSessionUser } from '@/lib/supabase/server';

export const dynamic = 'force-dynamic';

function parseInteger(value: string | null): number | null {
  if (value === null || value === '') return null;
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || !Number.isInteger(parsed)) return null;
  return parsed;
}

/**
 * GET /api/items?tenant_id=<n>&customer_id=<n>[&production_date=YYYY-MM-DD&production_code=CODE]
 * Returns active items for a tenant with effective pricing for the given customer on the order's delivery date
 * (production date plus the code's delivery days; today when no production date is given). Uses om_items_get_v2.
 */
export async function GET(request: Request) {
  const url = new URL(request.url);

  const p_tenant_id = parseInteger(url.searchParams.get('tenant_id'));
  if (p_tenant_id === null) {
    return NextResponse.json({ error: 'Invalid or missing tenant_id' }, { status: 400 });
  }

  const customerIdRaw = url.searchParams.get('customer_id');
  let p_customer_id: number | null = null;
  if (customerIdRaw !== null && customerIdRaw !== '') {
    p_customer_id = parseInteger(customerIdRaw);
    if (p_customer_id === null) {
      return NextResponse.json({ error: 'Invalid customer_id' }, { status: 400 });
    }
  }

  const productionDate = url.searchParams.get('production_date');
  if (productionDate && !/^\d{4}-\d{2}-\d{2}$/.test(productionDate)) {
    return NextResponse.json({ error: 'Invalid production_date' }, { status: 400 });
  }
  const productionCode = url.searchParams.get('production_code');

  const user = await getSessionUser();
  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc('om_items_get_v2', {
    p_tenant_id,
    p_customer_id,
    p_production_date: productionDate || null,
    p_production_code: productionCode || null,
  });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 400 });
  }

  return NextResponse.json({ data });
}
