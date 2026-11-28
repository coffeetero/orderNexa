import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { requireStaff, toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

type Queued = { contact_point_id: number; address: string };
type Result = { contact_point_id: number; status: 'OK' | 'ZERO_RESULTS' | 'FAILED'; latitude?: number; longitude?: number; formatted_address?: string; place_id?: string };

/**
 * POST /api/geocode/run { tenant_id, contact_point_ids?: number[], limit?: number }
 * Looks up PENDING addresses (fnd_geocode_queue_get) with the Google Geocoding API and stores the coordinates
 * (fnd_geocode_save). With contact_point_ids only those (the route map asks for its stops); otherwise the next `limit`
 * (default 50, at most 200) — call again until `remaining` is 0 for the one-time pass over all addresses.
 * The key (GOOGLE_GEOCODING_KEY) stays on the server. → { data: { looked_up, ok, not_found, failed, results, remaining } }
 */
export async function POST(request: Request): Promise<NextResponse> {
  let body: Record<string, unknown>;
  try { body = (await request.json()) as Record<string, unknown>; } catch { return NextResponse.json({ error: 'Invalid JSON' }, { status: 400 }); }
  const tenantId = toInt(body.tenant_id);
  if (tenantId === null) return NextResponse.json({ error: 'tenant_id is required' }, { status: 400 });
  const ids = Array.isArray(body.contact_point_ids) ? body.contact_point_ids.map((v) => toInt(v)).filter((v): v is number => v !== null) : null;
  const limit = toInt(body.limit) ?? 50;
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;

  const key = process.env.GOOGLE_GEOCODING_KEY;
  if (!key) return NextResponse.json({ error: 'Address lookup is not set up (GOOGLE_GEOCODING_KEY is missing)' }, { status: 503 });

  const supabase = await createClient();
  const { data: queue, error } = await supabase.rpc('fnd_geocode_queue_get', { p_tenant_id: tenantId, p_limit: limit, p_ids: ids && ids.length ? ids : null });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });

  const results: Result[] = [];
  for (const q of (queue ?? []) as Queued[]) {
    const address = q.address.replace(/\s*\n\s*/g, ', ');
    try {
      const res = await fetch(`https://maps.googleapis.com/maps/api/geocode/json?address=${encodeURIComponent(address)}&region=us&key=${key}`, { cache: 'no-store' });
      const j = (await res.json()) as { status: string; error_message?: string; results?: { formatted_address: string; place_id: string; geometry: { location: { lat: number; lng: number } } }[] };
      if (j.status === 'OK' && j.results?.[0]) {
        const g = j.results[0];
        results.push({ contact_point_id: q.contact_point_id, status: 'OK', latitude: g.geometry.location.lat, longitude: g.geometry.location.lng, formatted_address: g.formatted_address, place_id: g.place_id });
      } else if (j.status === 'ZERO_RESULTS') {
        results.push({ contact_point_id: q.contact_point_id, status: 'ZERO_RESULTS' });
      } else if (j.status === 'REQUEST_DENIED' || j.status === 'OVER_QUERY_LIMIT' || j.status === 'OVER_DAILY_LIMIT') {
        // the key or quota is the problem: stop, keep these addresses PENDING, and say why
        await saveResults(supabase, tenantId, results);
        return NextResponse.json({ error: `Google refused the lookup (${j.status}${j.error_message ? `: ${j.error_message}` : ''})` }, { status: 502 });
      } else {
        results.push({ contact_point_id: q.contact_point_id, status: 'FAILED' });
      }
    } catch {
      results.push({ contact_point_id: q.contact_point_id, status: 'FAILED' });
    }
  }

  const saveError = await saveResults(supabase, tenantId, results);
  if (saveError) return NextResponse.json({ error: saveError }, { status: 400 });
  const { data: rest } = ids && ids.length ? { data: [] } : await supabase.rpc('fnd_geocode_queue_get', { p_tenant_id: tenantId, p_limit: 200, p_ids: null });
  return NextResponse.json({
    data: {
      looked_up: results.length,
      ok: results.filter((r) => r.status === 'OK').length,
      not_found: results.filter((r) => r.status === 'ZERO_RESULTS').length,
      failed: results.filter((r) => r.status === 'FAILED').length,
      results,
      remaining: Array.isArray(rest) ? rest.length : 0,
    },
  });
}

async function saveResults(supabase: Awaited<ReturnType<typeof createClient>>, tenantId: number, results: Result[]): Promise<string | null> {
  if (results.length === 0) return null;
  const { error } = await supabase.rpc('fnd_geocode_save', { p_tenant_id: tenantId, p_results: results });
  return error ? error.message : null;
}
