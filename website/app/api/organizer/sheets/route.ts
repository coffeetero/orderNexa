import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * GET  /api/organizer/sheets?tenant_id=n        → the sheets the user can see, without workbooks (org_sheets_get)
 * GET  /api/organizer/sheets?tenant_id=n&id=n   → one sheet with its workbook (org_sheet_get)
 * POST /api/organizer/sheets { tenant_id, sheet_id?, sheet_name, visibility, workbook, version? } → creates or saves (org_sheet_save)
 */
export async function GET(request: Request) {
  const q = new URL(request.url).searchParams;
  if (q.has('id')) {
    const id = toInt(q.get('id'));
    if (id === null) return NextResponse.json({ error: 'Invalid id' }, { status: 400 });
    return adminRpc(q.get('tenant_id'), 'org_sheet_get', { p_sheet_id: id });
  }
  return adminRpc(q.get('tenant_id'), 'org_sheets_get', {});
}

export async function POST(request: Request) {
  const body = await readBody(request);
  if (!body) return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  if (!body.workbook || typeof body.workbook !== 'object') return NextResponse.json({ error: 'The workbook is missing' }, { status: 400 });
  return adminRpc(body.tenant_id, 'org_sheet_save', {
    p_payload: {
      sheet_id: body.sheet_id ?? null,
      sheet_name: typeof body.sheet_name === 'string' ? body.sheet_name.slice(0, 200) : null,
      visibility: body.visibility === 'SHARED' ? 'SHARED' : 'PRIVATE',
      workbook: body.workbook,
      version: body.version ?? null,
    },
  });
}
