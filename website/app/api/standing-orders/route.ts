import { NextResponse } from 'next/server';
import { createClient, getSessionUser } from '@/lib/supabase/server';

export const dynamic = 'force-dynamic';

function parseInteger(value: unknown): number | null {
  if (value === null || value === undefined || value === '') return null;
  const parsed = typeof value === 'number' ? value : Number(value);
  if (!Number.isFinite(parsed) || !Number.isInteger(parsed)) return null;
  return parsed;
}

export async function GET(request: Request) {
  const url          = new URL(request.url);
  const tenantId     = parseInteger(url.searchParams.get('tenant_id'));
  const customerId   = parseInteger(url.searchParams.get('customer_id'));
  const productionDow  = url.searchParams.get('production_dow');
  const productionCode = url.searchParams.get('production_code');

  if (tenantId === null || customerId === null || !productionDow || !productionCode) {
    return NextResponse.json({ error: 'Missing required parameters' }, { status: 400 });
  }

  const user = await getSessionUser();
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const supabase = createClient();
  const { data, error } = await supabase.rpc('om_standing_orders_get', {
    p_tenant_id:       tenantId,
    p_customer_id:     customerId,
    p_production_dow:  productionDow,
    p_production_code: productionCode,
  });

  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data: data ?? [] });
}

export async function POST(request: Request) {
  let body: unknown;
  try { body = await request.json(); }
  catch { return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 }); }

  const payload = body as Record<string, unknown>;
  const tenantId     = parseInteger(payload.tenant_id);
  const customerId   = parseInteger(payload.customer_id);
  const productionDow  = payload.production_dow  as string | undefined;
  const productionCode = payload.production_code as string | undefined;

  if (tenantId === null || customerId === null || !productionDow || !productionCode) {
    return NextResponse.json({ error: 'Missing required fields' }, { status: 400 });
  }

  const user = await getSessionUser();
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const supabase = createClient();
  const { data, error } = await supabase.rpc('om_standing_orders_save', {
    p_tenant_id:       tenantId,
    p_customer_id:     customerId,
    p_production_dow:  productionDow,
    p_production_code: productionCode,
    p_lines:           payload.lines ?? [],
  });

  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
