import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { NextResponse } from 'next/server';

export const dynamic = 'force-dynamic';

/**
 * GET  /api/admin/accounting-settings?tenant_id=n → { accounting_rules: 'STRICT' | 'RELAXED' }
 * POST /api/admin/accounting-settings { tenant_id, accounting_rules } → saved settings
 */
export async function GET(request: Request) {
  return adminRpc(new URL(request.url).searchParams.get('tenant_id'), 'fnd_accounting_settings_get', {});
}

export async function POST(request: Request) {
  const body = await readBody(request);
  if (!body) return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  return adminRpc(body.tenant_id, 'fnd_accounting_settings_save', { p_payload: { accounting_rules: body.accounting_rules } });
}
