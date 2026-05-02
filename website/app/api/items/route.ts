import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';

export const dynamic = 'force-dynamic';

function parseInteger(value: string | null): number | null {
  if (value === null || value === '') return null;
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || !Number.isInteger(parsed)) return null;
  return parsed;
}

/**
 * GET /api/items?tenant_id=<n>&customer_id=<n>
 * Returns active items for a tenant with effective pricing for the given customer.
 * Uses om_get_items_for_order RPC.
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

  const supabase = createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const { data, error } = await supabase.rpc('om_get_items_for_order', {
    p_tenant_id,
    p_customer_id,
  });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 400 });
  }

  return NextResponse.json({ data });
}
