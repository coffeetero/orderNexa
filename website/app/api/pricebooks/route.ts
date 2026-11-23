import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * GET  /api/pricebooks?tenant_id=n                   → every pricing book with item and assigned-customer counts
 * GET  /api/pricebooks?tenant_id=n&pricebook_id=n    → one book's items and the customers it is assigned to
 * GET  /api/pricebooks?tenant_id=n&accounts=1        → active accounts (for "made for customer")
 * POST /api/pricebooks { tenant_id, pricebook: {pricebook_id?, pricebook_name, description, is_active, owner_customer_id} } → pricebook_id
 */
export async function GET(request: Request) {
  const q = new URL(request.url).searchParams;
  const tenant = q.get('tenant_id');
  if (q.get('accounts')) return adminRpc(tenant, 'fnd_report_accounts_get', {});
  const id = toInt(q.get('pricebook_id'));
  if (q.get('pricebook_id') !== null && id === null) return NextResponse.json({ error: 'Invalid pricebook_id' }, { status: 400 });
  return id === null ? adminRpc(tenant, 'fnd_pricebooks_list_get', {}) : adminRpc(tenant, 'fnd_pricebook_detail_get', { p_pricebook_id: id });
}

export async function POST(request: Request) {
  const body = await readBody(request);
  if (!body || typeof body.pricebook !== 'object' || body.pricebook === null) return NextResponse.json({ error: 'pricebook is required' }, { status: 400 });
  return adminRpc(body.tenant_id, 'fnd_pricebook_save', { p_payload: body.pricebook });
}
