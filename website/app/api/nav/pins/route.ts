import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { requireStaff } from '@/lib/api/nav';
import { normalizePins } from '@/lib/quick-access';

export const dynamic = 'force-dynamic';

/** POST /api/nav/pins  { action_keys: string[] } — replaces the user's pinned Quick Access (ordered, max 4). */
export async function POST(request: Request) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  }
  if (typeof body !== 'object' || body === null || Array.isArray(body)) {
    return NextResponse.json({ error: 'Request body must be a JSON object' }, { status: 400 });
  }

  const auth = await requireStaff();
  if (!auth.ok) return auth.response;

  const pins = normalizePins((body as Record<string, unknown>).action_keys, auth.allowed);
  if (pins === null) {
    return NextResponse.json({ error: 'action_keys must be up to 4 unique, available actions' }, { status: 400 });
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc('fnd_nav_pins_set', { p_action_keys: pins });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });

  return NextResponse.json({ ok: true, pinned: pins });
}
