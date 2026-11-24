import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { NextResponse } from 'next/server';

export const dynamic = 'force-dynamic';

/**
 * GET  /api/admin/format-settings?tenant_id=n → { customer_number_mask }
 * POST /api/admin/format-settings { tenant_id, customer_number_mask } → saved settings (empty mask = print numbers as stored)
 */
export async function GET(request: Request) {
  return adminRpc(new URL(request.url).searchParams.get('tenant_id'), 'fnd_format_settings_get', {});
}

export async function POST(request: Request) {
  const body = await readBody(request);
  if (!body) return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  return adminRpc(body.tenant_id, 'fnd_format_settings_save', { p_payload: { customer_number_mask: body.customer_number_mask ?? null } });
}
