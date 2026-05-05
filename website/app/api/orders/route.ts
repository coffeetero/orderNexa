import { NextResponse } from 'next/server';
import { createClient, getSessionUser } from '@/lib/supabase/server';

export const dynamic = 'force-dynamic';

function parseInteger(value: string | null): number | null {
  if (value === null || value === '') return null;
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || !Number.isInteger(parsed)) return null;
  return parsed;
}

function parseDate(value: string | null): string | null {
  if (value === null || value === '') return null;
  const d = new Date(value);
  if (isNaN(d.getTime())) return null;
  return value;
}

/**
 * GET /api/orders
 *   ?tenant_id=<n>              — required
 *   &order_id=<n>               — single order + lines
 *   &customer_id=<n>            — filter by customer
 *   &production_date_from=<date>  — filter from date
 *   &production_date_to=<date>    — filter to date
 *
 * Uses om_orders_get RPC.
 */
export async function GET(request: Request) {
  const url = new URL(request.url);

  const p_tenant_id = parseInteger(url.searchParams.get('tenant_id'));
  if (p_tenant_id === null) {
    return NextResponse.json({ error: 'Invalid or missing tenant_id' }, { status: 400 });
  }

  const p_order_id    = parseInteger(url.searchParams.get('order_id'));
  const p_customer_id = parseInteger(url.searchParams.get('customer_id'));
  const p_production_date_from = parseDate(url.searchParams.get('production_date_from'));
  const p_production_date_to   = parseDate(url.searchParams.get('production_date_to'));

  const user = await getSessionUser();
  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const supabase = createClient();
  const { data, error } = await supabase.rpc('om_orders_get', {
    p_tenant_id,
    p_order_id,
    p_customer_id,
    p_production_date_from,
    p_production_date_to,
  });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 400 });
  }

  return NextResponse.json({ data });
}
