import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';

export const dynamic = 'force-dynamic';

/**
 * GET  /api/admin/health?tenant_id=n                 → the checks with their last result
 * GET  /api/admin/health?tenant_id=n&view=findings   → open findings (&fixed=1 also lists those fixed in the last 30 days)
 * POST /api/admin/health { tenant_id, action: 'run', check_code? }          → run every enabled check (or one) → status
 * POST /api/admin/health { tenant_id, action: 'enable', check_code, enabled } → turn a check on or off (administrators)
 * POST /api/admin/health { tenant_id, action: 'fix', log_id }                → mark a finding fixed
 */
export async function GET(request: Request) {
  const q = new URL(request.url).searchParams;
  const tenant = q.get('tenant_id');
  if (q.get('view') === 'findings') return adminRpc(tenant, 'fnd_health_findings_get', { p_include_fixed: q.get('fixed') === '1' });
  return adminRpc(tenant, 'fnd_health_checks_get', {});
}

export async function POST(request: Request) {
  const body = await readBody(request);
  if (!body) return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  if (body.action === 'run') {
    const code = typeof body.check_code === 'string' && body.check_code ? body.check_code : null;
    return adminRpc(body.tenant_id, 'fnd_health_run', { p_trigger: 'Manual', p_check_code: code });
  }
  if (body.action === 'enable' && typeof body.check_code === 'string' && typeof body.enabled === 'boolean') {
    return adminRpc(body.tenant_id, 'fnd_health_check_set_enabled', { p_check_code: body.check_code, p_enabled: body.enabled });
  }
  if (body.action === 'fix' && Number.isInteger(body.log_id)) {
    return adminRpc(body.tenant_id, 'fnd_health_finding_fix', { p_log_id: body.log_id });
  }
  return NextResponse.json({ error: 'Unknown action' }, { status: 400 });
}
