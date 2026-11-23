import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';

export const dynamic = 'force-dynamic';

/**
 * GET  /api/admin/security?tenant_id=n → the company's security settings
 * POST /api/admin/security { tenant_id, settings: {idle_timeout_minutes, min_password_length, password_max_age_days, password_history_count} }
 */
export async function GET(request: Request) {
  return adminRpc(new URL(request.url).searchParams.get('tenant_id'), 'fnd_security_settings_get', {});
}

export async function POST(request: Request) {
  const body = await readBody(request);
  if (!body || typeof body.settings !== 'object' || body.settings === null) {
    return NextResponse.json({ error: 'settings is required' }, { status: 400 });
  }
  return adminRpc(body.tenant_id, 'fnd_security_settings_save', { p_payload: body.settings });
}
