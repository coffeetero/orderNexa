import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

const MAX_ROWS = 5000;

/**
 * GET  /api/customers/import?tenant_id=n&id=n                 → one import with its checked rows (fnd_customer_import_get)
 * POST /api/customers/import { tenant_id, file_name, rows }   → stores and checks the file; nothing changes yet (fnd_customer_import_upload)
 *      rows: [{ customer_number, customer_name, customer_type, parent_number, ... }] keyed like the export, values as text
 */
export async function GET(request: Request) {
  const q = new URL(request.url).searchParams;
  const id = toInt(q.get('id'));
  if (id === null) return NextResponse.json({ error: 'id is required' }, { status: 400 });
  return adminRpc(q.get('tenant_id'), 'fnd_customer_import_get', { p_customer_import_id: id });
}

export async function POST(request: Request) {
  const body = await readBody(request);
  if (!body) return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  if (!Array.isArray(body.rows) || body.rows.length === 0) return NextResponse.json({ error: 'The file has no rows' }, { status: 400 });
  if (body.rows.length > MAX_ROWS) return NextResponse.json({ error: 'The file has more than 5,000 rows' }, { status: 400 });
  const rows = (body.rows as unknown[]).map((r) =>
    Object.fromEntries(Object.entries((r ?? {}) as Record<string, unknown>)
      .filter(([k]) => /^[a-z_]{1,40}$/.test(k))
      .map(([k, v]) => [k, v === null || v === undefined ? '' : String(v).slice(0, 2000)])));
  return adminRpc(body.tenant_id, 'fnd_customer_import_upload', {
    p_payload: { file_name: typeof body.file_name === 'string' ? body.file_name.slice(0, 200) : null, rows },
  });
}
