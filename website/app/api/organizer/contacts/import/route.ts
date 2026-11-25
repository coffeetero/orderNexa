import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';

export const dynamic = 'force-dynamic';

/** POST /api/organizer/contacts/import { tenant_id, rows, commit } → preview (commit false) or import (org_contacts_import) */
export async function POST(request: Request) {
  const body = await readBody(request);
  if (!body) return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  if (!Array.isArray(body.rows)) return NextResponse.json({ error: 'Nothing to import' }, { status: 400 });
  return adminRpc(body.tenant_id, 'org_contacts_import', { p_rows: body.rows, p_commit: body.commit === true });
}
