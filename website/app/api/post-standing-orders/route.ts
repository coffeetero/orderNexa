import { NextResponse } from 'next/server';
import { createClient, getSessionUser } from '@/lib/supabase/server';
import { isIsoDate, localDateIso } from '@/lib/date';

export const dynamic = 'force-dynamic';

function parseInteger(v: unknown): number | null {
  if (typeof v === 'number' && Number.isFinite(v) && Number.isInteger(v)) return v;
  if (typeof v === 'string' && v.trim() !== '') {
    const n = Number(v);
    return Number.isFinite(n) && Number.isInteger(n) ? n : null;
  }
  return null;
}

/** GET — posting candidates for a date range (production_date .. production_date_to) + available production codes */
export async function GET(request: Request) {
  const url            = new URL(request.url);
  const tenantId       = parseInteger(url.searchParams.get('tenant_id'));
  const dateFrom       = url.searchParams.get('production_date');
  const dateTo         = url.searchParams.get('production_date_to') || dateFrom;
  const codesParam     = url.searchParams.get('production_codes'); // comma-separated

  if (tenantId === null || !isIsoDate(dateFrom) || !isIsoDate(dateTo)) {
    return NextResponse.json({ error: 'Missing tenant_id or production dates' }, { status: 400 });
  }

  const user = await getSessionUser();
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const supabase = createClient();

  // Available production codes for this tenant
  const { data: codesData } = await supabase
    .from('om_standing_orders')
    .select('production_code')
    .eq('tenant_id', tenantId)
    .eq('is_active', true);

  const availableCodes = Array.from(new Set((codesData ?? []).map((r: { production_code: string }) => r.production_code))).sort();

  const productionCodes = codesParam
    ? codesParam.split(',').map(c => c.trim()).filter(Boolean)
    : availableCodes;

  if (productionCodes.length === 0) {
    return NextResponse.json({ data: [], availableCodes });
  }

  const { data, error } = await (supabase.rpc as any)('om_post_standing_orders_list', {
    p_tenant_id:        tenantId,
    p_date_from:        dateFrom,
    p_date_to:          dateTo,
    p_production_codes: productionCodes,
  });

  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data: data ?? [], availableCodes });
}

type PostResult = {
  production_date: string; production_code: string; customer_id: number; status: string;
  order_id?: number | null; order_number?: string | null; department_event?: string | null; lines_added?: number; message?: string | null;
};

/** POST — post the selected standing orders (customer + production date + production code); the database does the work */
export async function POST(request: Request) {
  let body: unknown;
  try { body = await request.json(); }
  catch { return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 }); }

  const payload   = body as Record<string, unknown>;
  const tenantId  = parseInteger(payload.tenant_id);
  const orders    = payload.orders as { customer_id: number; production_date: string; production_code: string }[] | undefined;
  // Order date is the caller's local "today" (the server may run in another time zone).
  const orderDate = isIsoDate(payload.order_date) ? payload.order_date : localDateIso();

  if (tenantId === null || !Array.isArray(orders) || orders.length === 0) {
    return NextResponse.json({ error: 'Missing tenant_id or orders' }, { status: 400 });
  }
  if (orders.some(o => !isIsoDate(o?.production_date) || typeof o?.production_code !== 'string' || parseInteger(o?.customer_id) === null)) {
    return NextResponse.json({ error: 'Each order needs customer_id, production_date and production_code' }, { status: 400 });
  }

  const user = await getSessionUser();
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const supabase = createClient();

  // One call per production date + code with the selected customers.
  const groups = new Map<string, { date: string; code: string; customerIds: number[] }>();
  for (const o of orders) {
    const key = `${o.production_date}|${o.production_code}`;
    const g = groups.get(key) ?? { date: o.production_date, code: o.production_code, customerIds: [] };
    g.customerIds.push(Number(o.customer_id));
    groups.set(key, g);
  }

  const results: PostResult[] = [];
  for (const g of Array.from(groups.values())) {
    const { data, error } = await (supabase.rpc as any)('om_standing_orders_post', {
      p_tenant_id:        tenantId,
      p_date_from:        g.date,
      p_date_to:          g.date,
      p_production_codes: [g.code],
      p_customer_ids:     g.customerIds,
      p_order_date:       orderDate,
    });
    if (error) {
      g.customerIds.forEach(id => results.push({ production_date: g.date, production_code: g.code, customer_id: id, status: 'FAILED', message: error.message }));
      continue;
    }
    results.push(...(((data as { results?: PostResult[] } | null)?.results) ?? []));
  }

  const count = (...s: string[]) => results.filter(r => s.includes(r.status)).length;
  return NextResponse.json({
    results,
    summary: {
      posted: count('POSTED'), added: count('ADDED'), up_to_date: count('UP_TO_DATE'),
      skipped: count('POSTED_TO_AR', 'ORDER_DELETED'), failed: count('FAILED'),
    },
  });
}
