import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * GET  /api/organizer/contacts/duplicates?tenant_id=n                  → possible duplicates (org_contact_duplicates_get)
 * POST /api/organizer/contacts/duplicates { tenant_id, keep_id, merge_id } → merges merge_id into keep_id (org_contact_merge)
 */
export async function GET(request: Request) {
  return adminRpc(new URL(request.url).searchParams.get('tenant_id'), 'org_contact_duplicates_get', {});
}

export async function POST(request: Request) {
  const body = await readBody(request);
  if (!body) return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  const keep = toInt(body.keep_id);
  const merge = toInt(body.merge_id);
  if (keep === null || merge === null) return NextResponse.json({ error: 'Pick the contacts to merge' }, { status: 400 });
  return adminRpc(body.tenant_id, 'org_contact_merge', { p_keep_id: keep, p_merge_id: merge });
}
