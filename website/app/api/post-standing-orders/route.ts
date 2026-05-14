import { NextResponse } from 'next/server';
import { createClient, getSessionUser } from '@/lib/supabase/server';

export const dynamic = 'force-dynamic';

function parseInteger(v: unknown): number | null {
  if (typeof v === 'number' && Number.isFinite(v) && Number.isInteger(v)) return v;
  if (typeof v === 'string' && v.trim() !== '') {
    const n = Number(v);
    return Number.isFinite(n) && Number.isInteger(n) ? n : null;
  }
  return null;
}

function todayIso(): string {
  return new Date().toISOString().slice(0, 10);
}

/** GET — retrieve posting candidates + available production codes */
export async function GET(request: Request) {
  const url           = new URL(request.url);
  const tenantId      = parseInteger(url.searchParams.get('tenant_id'));
  const productionDate = url.searchParams.get('production_date');
  const codesParam    = url.searchParams.get('production_codes'); // comma-separated

  if (tenantId === null || !productionDate) {
    return NextResponse.json({ error: 'Missing tenant_id or production_date' }, { status: 400 });
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

  // Candidates
  const productionCodes = codesParam
    ? codesParam.split(',').map(c => c.trim()).filter(Boolean)
    : availableCodes;

  if (productionCodes.length === 0) {
    return NextResponse.json({ data: [], availableCodes });
  }

  const { data, error } = await (supabase.rpc as any)('om_post_standing_orders_list', {
    p_tenant_id:        tenantId,
    p_production_date:  productionDate,
    p_production_codes: productionCodes,
  });

  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data: data ?? [], availableCodes });
}

/** POST — post standing orders for selected customers */
export async function POST(request: Request) {
  let body: unknown;
  try { body = await request.json(); }
  catch { return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 }); }

  const payload     = body as Record<string, unknown>;
  const tenantId    = parseInteger(payload.tenant_id);
  const orders      = payload.orders as { customer_id: number; production_date: string; production_code: string }[] | undefined;

  if (tenantId === null || !Array.isArray(orders) || orders.length === 0) {
    return NextResponse.json({ error: 'Missing tenant_id or orders' }, { status: 400 });
  }

  const user = await getSessionUser();
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const supabase   = createClient();
  const orderDate  = todayIso();
  const results: { customer_id: number; production_code: string; status: string; order_id?: number; order_number?: string; message?: string }[] = [];

  for (const order of orders) {
    const { customer_id, production_date, production_code } = order;
    try {
      // 1. Get standing order lines
      const { data: lines, error: linesErr } = await supabase.rpc('om_standing_orders_get', {
        p_tenant_id:       tenantId,
        p_customer_id:     customer_id,
        p_production_dow:  dowFromDate(production_date),
        p_production_code: production_code,
      });

      if (linesErr) throw new Error(linesErr.message);

      const soLines = (lines ?? []) as { item_id: number; item_name: string; quantity: number; prep_options: string[] }[];

      // 2. Build order payload — same structure as Enter Orders
      const savePayload = {
        customer_id,
        order_number:    null,   // new order — RPC assigns
        order_date:      orderDate,
        production_date,
        production_code,
        department_event: null,
        delivery_amount:  0,
        lines: soLines.map((l, i) => ({
          client_temp_id:  `so-${customer_id}-${i}`,
          order_line_id:   null,
          item_id:         l.item_id,
          item_description: l.item_name,
          quantity:         l.quantity,
          unit_price:       0,
          unit_discount:    0,
          prep_options:     l.prep_options ?? [],
          is_scored:        false,
        })),
      };

      // 3. Save the order
      const { data: saved, error: saveErr } = await supabase.rpc('om_orders_save', {
        p_tenant_id: tenantId,
        p_action:    null,
        p_order_id:  null,
        p_payload:   savePayload,
      });

      if (saveErr) throw new Error(saveErr.message);

      const result = saved as { order_id?: number; order_number?: string } | null;
      results.push({
        customer_id, production_code, status: 'POSTED',
        order_id:     result?.order_id,
        order_number: result?.order_number,
      });
    } catch (err) {
      results.push({
        customer_id, production_code, status: 'FAILED',
        message: err instanceof Error ? err.message : 'Unknown error',
      });
    }
  }

  const posted  = results.filter(r => r.status === 'POSTED').length;
  const failed  = results.filter(r => r.status === 'FAILED').length;

  return NextResponse.json({ results, summary: { posted, failed } });
}

/** Derive MON/TUE/etc from an ISO date string */
function dowFromDate(dateStr: string): string {
  const d = new Date(dateStr + 'T00:00:00');
  return ['SUN','MON','TUE','WED','THU','FRI','SAT'][d.getDay()];
}
