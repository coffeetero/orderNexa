import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { NextResponse } from 'next/server';

export const dynamic = 'force-dynamic';

/**
 * GET  /api/admin/pricing-settings?tenant_id=n → { pricebook_unused_years }
 * POST /api/admin/pricing-settings { tenant_id, pricebook_unused_years } → saved settings
 */
export async function GET(request: Request) {
  return adminRpc(new URL(request.url).searchParams.get('tenant_id'), 'fnd_pricing_settings_get', {});
}

export async function POST(request: Request) {
  const body = await readBody(request);
  if (!body) return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  return adminRpc(body.tenant_id, 'fnd_pricing_settings_save', { p_payload: { pricebook_unused_years: body.pricebook_unused_years } });
}
