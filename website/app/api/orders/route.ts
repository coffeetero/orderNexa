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
 * Maps `headers_only` query to `p_return_headers_only`.
 * When absent, defaults to TRUE (matches SQL default; header-only detail).
 * Callers that need line items must pass `headers_only=false`.
 */
function parseHeadersOnly(value: string | null): boolean {
  if (value === null || value === '') return true;
  const v = value.toLowerCase();
  if (v === 'true' || v === '1') return true;
  if (v === 'false' || v === '0') return false;
  return true;
}

/**
 * GET /api/orders
 *
 * Detail (single order):
 *   ?tenant_id=<n>&order_id=<n>[&headers_only=true|false]
 *   → om_orders_get with p_order_id set; optional headers_only (default true).
 *   Pass headers_only=false to load lines for editing / grids.
 *
 * List (order headers):
 *   ?tenant_id=<n>&customer_id=<n>&production_date=<YYYY-MM-DD>&production_code=<AM|PM|SPECIAL>
 *   → p_production_date_from / p_production_date_to both set from production_date; p_order_id null.
 *   List branch always returns headers only; p_return_headers_only is passed as true.
 *
 * Optional legacy list filters (otherwise omitted): production_date_from, production_date_to.
 *
 * Uses om_orders_get RPC.
 */
export async function GET(request: Request) {
  const url = new URL(request.url);

  const p_tenant_id = parseInteger(url.searchParams.get('tenant_id'));
  if (p_tenant_id === null) {
    return NextResponse.json({ error: 'Invalid or missing tenant_id' }, { status: 400 });
  }

  const p_order_id = parseInteger(url.searchParams.get('order_id'));

  const user = await getSessionUser();
  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const supabase = createClient();

  if (p_order_id !== null) {
    const p_return_headers_only = parseHeadersOnly(url.searchParams.get('headers_only'));
    const { data, error } = await supabase.rpc('om_orders_get', {
      p_tenant_id,
      p_order_id,
      p_customer_id: null,
      p_production_date_from: null,
      p_production_date_to: null,
      p_production_code: null,
      p_return_headers_only,
    });

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }

    return NextResponse.json({ data });
  }

  const p_customer_id = parseInteger(url.searchParams.get('customer_id'));

  const productionDateSingle = parseDate(url.searchParams.get('production_date'));
  let p_production_date_from: string | null = null;
  let p_production_date_to: string | null = null;

  if (productionDateSingle !== null) {
    p_production_date_from = productionDateSingle;
    p_production_date_to = productionDateSingle;
  } else {
    p_production_date_from = parseDate(url.searchParams.get('production_date_from'));
    p_production_date_to = parseDate(url.searchParams.get('production_date_to'));
  }

  const productionCodeRaw = url.searchParams.get('production_code');
  const p_production_code =
    productionCodeRaw !== null && productionCodeRaw !== '' ? productionCodeRaw.trim() : null;

  const { data, error } = await supabase.rpc('om_orders_get', {
    p_tenant_id,
    p_order_id: null,
    p_customer_id,
    p_production_date_from,
    p_production_date_to,
    p_production_code,
    p_return_headers_only: true,
  });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 400 });
  }

  return NextResponse.json({ data });
}
