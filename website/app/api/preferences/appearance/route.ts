import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { requireStaff } from '@/lib/api/nav';
import { readAppearance } from '@/lib/theme/prefs';

export const dynamic = 'force-dynamic';

/**
 * GET  /api/preferences/appearance → { data: AppearancePrefs | null }  (null = this user never saved one)
 * POST /api/preferences/appearance  { appearance } → { data: AppearancePrefs }  (validated and sanitized: colours only)
 */
export async function GET() {
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;

  const supabase = await createClient();
  const { data, error } = await supabase.rpc('fnd_user_preferences_get');
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });

  const raw = (data as { appearance?: unknown } | null)?.appearance;
  const empty = !raw || typeof raw !== 'object' || Object.keys(raw as object).length === 0;
  return NextResponse.json({ data: empty ? null : readAppearance(raw) });
}

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
  const appearanceIn = (body as Record<string, unknown>).appearance;
  if (typeof appearanceIn !== 'object' || appearanceIn === null || Array.isArray(appearanceIn)) {
    return NextResponse.json({ error: 'appearance must be an object' }, { status: 400 });
  }

  const auth = await requireStaff();
  if (!auth.ok) return auth.response;

  // Only known fields survive; colours are re-validated, so nothing else can be stored.
  const appearance = readAppearance(appearanceIn);

  const supabase = await createClient();
  const { error } = await supabase.rpc('fnd_user_preferences_save', { p_appearance: appearance });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });

  return NextResponse.json({ data: appearance });
}
