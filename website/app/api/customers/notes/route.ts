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
  const url        = new URL(request.url);
  const tenantId   = parseInteger(url.searchParams.get('tenant_id'));
  const customerId = parseInteger(url.searchParams.get('customer_id'));

  if (tenantId === null || customerId === null) {
    return NextResponse.json({ error: 'Invalid or missing tenant_id / customer_id' }, { status: 400 });
  }

  const user = await getSessionUser();
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const supabase = createClient();
  const { data, error } = await supabase.rpc('fnd_notes_get', {
    p_tenant_id:    tenantId,
    p_entity_id:    customerId,
    p_source_table: 'fnd_customers',
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

  const payload  = body as Record<string, unknown>;
  const tenantId = parseInteger(payload.tenant_id);
  if (tenantId === null) {
    return NextResponse.json({ error: 'Invalid tenant_id' }, { status: 400 });
  }

  const user = await getSessionUser();
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const supabase = createClient();
  const { data, error } = await supabase.rpc('fnd_notes_save', {
    p_tenant_id: tenantId,
    p_entry:     payload.entry,
  });

  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}

export async function DELETE(request: Request) {
  const url      = new URL(request.url);
  const tenantId = parseInteger(url.searchParams.get('tenant_id'));
  const noteId   = parseInteger(url.searchParams.get('note_id'));

  if (tenantId === null || noteId === null) {
    return NextResponse.json({ error: 'Invalid or missing tenant_id / note_id' }, { status: 400 });
  }

  const user = await getSessionUser();
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const supabase = createClient();
  const { data, error } = await supabase.rpc('fnd_notes_delete', {
    p_tenant_id: tenantId,
    p_note_id:   noteId,
  });

  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
