import { NextResponse } from 'next/server';
import { adminRpc } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * GET /api/customers/export?tenant_id=n[&all=true][&account_id=n]
 *     → customers as Export Customers rows, parents before children (fnd_customer_export_get).
 *       all=true includes inactive customers; account_id limits the file to one account and everything under it.
 */
export async function GET(request: Request) {
  const q = new URL(request.url).searchParams;
  const accountRaw = q.get('account_id');
  const accountId = accountRaw ? toInt(accountRaw) : null;
  if (accountRaw && accountId === null) return NextResponse.json({ error: 'Invalid account_id' }, { status: 400 });
  return adminRpc(q.get('tenant_id'), 'fnd_customer_export_get', { p_active_only: q.get('all') !== 'true', p_account_id: accountId });
}
