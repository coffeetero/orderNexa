import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { requireStaff, toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

type Queued = { contact_point_id: number; address: string };
type GoogleResult = {
  result?: {
    verdict?: Record<string, unknown> & { validationGranularity?: string };
    address?: { postalAddress?: { addressLines?: string[]; locality?: string; administrativeArea?: string; postalCode?: string } };
    uspsData?: { standardizedAddress?: { firstAddressLine?: string; secondAddressLine?: string; cityStateZipAddressLine?: string } };
  };
  error?: { status?: string; message?: string };
};

/**
 * POST /api/address/validate { tenant_id, contact_point_ids?: number[], limit?: number }
 * Sends customer addresses not yet checked (fnd_address_validation_queue_get) to the Google Address Validation API and
 * hands Google's answer to fnd_address_validation_save, which decides verified / suggested / not found.
 * Without ids, the next `limit` (default 50, at most 200); call again until `remaining` is 0.
 * The key (GOOGLE_GEOCODING_KEY, with the Address Validation API allowed) stays on the server.
 * → { data: { checked, verified, suggested, unconfirmed, not_found, remaining } }
 */
export async function POST(request: Request): Promise<NextResponse> {
  let b: Record<string, unknown>;
  try { b = (await request.json()) as Record<string, unknown>; } catch { return NextResponse.json({ error: 'Invalid JSON' }, { status: 400 }); }
  const tenantId = toInt(b.tenant_id);
  if (tenantId === null) return NextResponse.json({ error: 'tenant_id is required' }, { status: 400 });
  const ids = Array.isArray(b.contact_point_ids) ? b.contact_point_ids.map((v) => toInt(v)).filter((v): v is number => v !== null) : null;
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;
  const key = process.env.GOOGLE_GEOCODING_KEY;
  if (!key) return NextResponse.json({ error: 'Address checking is not set up (GOOGLE_GEOCODING_KEY is missing)' }, { status: 503 });

  const supabase = await createClient();
  const { data: queue, error } = await supabase.rpc('fnd_address_validation_queue_get', { p_tenant_id: tenantId, p_limit: toInt(b.limit) ?? 50, p_ids: ids && ids.length ? ids : null });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });

  const results: Record<string, unknown>[] = [];
  let refused: string | null = null;
  for (const q of (queue ?? []) as Queued[]) {
    // name or attention lines stay out: Google gets the street and the city line (the last two)
    const lines = q.address.split('\n').map((l) => l.trim()).filter(Boolean).slice(-2);
    try {
      const res = await fetch(`https://addressvalidation.googleapis.com/v1:validateAddress?key=${key}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, cache: 'no-store',
        body: JSON.stringify({ address: { regionCode: 'US', addressLines: lines } }),
      });
      const j = (await res.json()) as GoogleResult;
      if (j.error) {
        if (res.status === 403 || res.status === 429) { refused = `${j.error.status ?? res.status}: ${j.error.message ?? ''}`; break; }
        results.push({ contact_point_id: q.contact_point_id, status: 'FAILED' });
        continue;
      }
      const usps = j.result?.uspsData?.standardizedAddress;
      const pa = j.result?.address?.postalAddress;
      const street = usps?.firstAddressLine ?? pa?.addressLines?.[0] ?? null;
      const cityLine = usps?.cityStateZipAddressLine
        ?? (pa?.locality ? `${pa.locality}, ${pa.administrativeArea ?? ''} ${pa.postalCode ?? ''}`.trim() : null);
      results.push({
        contact_point_id: q.contact_point_id, status: 'OK', street, city_line: cityLine,
        granularity: j.result?.verdict?.validationGranularity ?? null, verdict: j.result?.verdict ?? null,
      });
    } catch {
      results.push({ contact_point_id: q.contact_point_id, status: 'FAILED' });
    }
  }

  const { data: counts, error: saveError } = results.length
    ? await supabase.rpc('fnd_address_validation_save', { p_tenant_id: tenantId, p_results: results })
    : { data: {}, error: null };
  if (saveError) return NextResponse.json({ error: saveError.message }, { status: 400 });
  if (refused) return NextResponse.json({ error: `Google refused the address check (${refused})` }, { status: 502 });
  const c = (counts ?? {}) as Record<string, number>;
  const { data: rest } = ids && ids.length ? { data: [] } : await supabase.rpc('fnd_address_validation_queue_get', { p_tenant_id: tenantId, p_limit: 200, p_ids: null });
  return NextResponse.json({
    data: {
      checked: results.filter((r) => r.status === 'OK').length,
      verified: c.VERIFIED ?? 0, suggested: c.SUGGESTED ?? 0, unconfirmed: c.UNCONFIRMED ?? 0, not_found: c.NOT_FOUND ?? 0,
      remaining: Array.isArray(rest) ? rest.length : 0,
    },
  });
}
