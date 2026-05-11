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
  const url = new URL(request.url);
  const tenantId = parseInteger(url.searchParams.get('tenant_id'));
  const itemId = parseInteger(url.searchParams.get('item_id'));

  if (tenantId === null || itemId === null) {
    return NextResponse.json({ error: 'Invalid or missing tenant_id / item_id' }, { status: 400 });
  }

  const user = await getSessionUser();
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const supabase = createClient();
  const { data, error } = await supabase.rpc('fnd_pricebook_items_get', {
    p_tenant_id: tenantId,
    p_item_id: itemId,
  });

  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data: data ?? [] });
}

export async function POST(request: Request) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  }

  const payload = body as Record<string, unknown>;
  const tenantId = parseInteger(payload.tenant_id);
  const itemId = parseInteger(payload.item_id);

  if (tenantId === null || itemId === null) {
    return NextResponse.json({ error: 'Invalid tenant_id or item_id' }, { status: 400 });
  }

  const user = await getSessionUser();
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const changes = Array.isArray(payload.changes) ? payload.changes : [];
  if (changes.length === 0) {
    return NextResponse.json({ data: { saved: 0 } });
  }

  const supabase = createClient();
  const { data, error } = await supabase.rpc('fnd_pricebook_items_save', {
    p_tenant_id: tenantId,
    p_item_id: itemId,
    p_entries: changes,
  });

  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
