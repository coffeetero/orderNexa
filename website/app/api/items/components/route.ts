import { NextResponse } from 'next/server';
import { createClient, getSessionUser } from '@/lib/supabase/server';

export const dynamic = 'force-dynamic';

function parseInteger(value: unknown): number | null {
  if (value === null || value === undefined || value === '') return null;
  const parsed = typeof value === 'number' ? value : Number(value);
  return Number.isInteger(parsed) ? parsed : null;
}

/**
 * GET  /api/items/components?tenant_id=n&item_id=n → the compound item's components [{item_id, item_number, item_name, is_active, quantity}]
 * POST /api/items/components { tenant_id, item_id, entries: [{item_id, quantity}] } → count saved (the full list; others are removed)
 * Rules (compound parent, simple components, quantity above 0) are enforced in the database.
 */
export async function GET(request: Request) {
  const q = new URL(request.url).searchParams;
  const tenantId = parseInteger(q.get('tenant_id'));
  const itemId = parseInteger(q.get('item_id'));
  if (tenantId === null || itemId === null) return NextResponse.json({ error: 'Invalid or missing tenant_id / item_id' }, { status: 400 });
  if (!(await getSessionUser())) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  const { data, error } = await (await createClient()).rpc('fnd_item_components_get', { p_tenant_id: tenantId, p_item_id: itemId });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data: data ?? [] });
}

export async function POST(request: Request) {
  let body: Record<string, unknown>;
  try {
    body = (await request.json()) as Record<string, unknown>;
  } catch {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  }
  const tenantId = parseInteger(body.tenant_id);
  const itemId = parseInteger(body.item_id);
  if (tenantId === null || itemId === null || !Array.isArray(body.entries)) {
    return NextResponse.json({ error: 'tenant_id, item_id and entries are required' }, { status: 400 });
  }
  if (!(await getSessionUser())) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  const { data, error } = await (await createClient()).rpc('fnd_item_components_set', { p_tenant_id: tenantId, p_item_id: itemId, p_entries: body.entries });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
