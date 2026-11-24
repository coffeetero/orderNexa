import { NextResponse } from 'next/server';
import { adminRpc } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/** DELETE /api/organizer/sheets/:id?tenant_id=n → deletes the sheet; owner only (org_sheet_delete) */
export async function DELETE(request: Request, { params }: { params: { id: string } }) {
  const id = toInt(params.id);
  if (id === null) return NextResponse.json({ error: 'Invalid id' }, { status: 400 });
  return adminRpc(new URL(request.url).searchParams.get('tenant_id'), 'org_sheet_delete', { p_sheet_id: id });
}
